import Foundation

extension Notification.Name {
    /// Posted on the main thread whenever the server pushes a `new_email`
    /// event over SSE. `InboxView` observes this to reload its list.
    static let newEmailReceived = Notification.Name("com.openmail.newEmailReceived")
}

/// A single long-lived Server-Sent Events connection per session.
///
/// Streams `GET {baseURL}/api/events` (cookie attached explicitly via
/// `APIClient.sseEventsRequest()`, because the client's session disables
/// automatic cookie handling) and parses the `event:` / `data:` frames
/// separated by blank lines. Reconnects with exponential backoff
/// (1 s → 2 s → 4 s … max 60 s), reset after every `connected` event.
/// When the stream cannot be established the app keeps working as before
/// (sync on start / pull-to-refresh) — this client is purely additive.
final class SSEClient: NSObject {
    static let shared = SSEClient()

    /// Called on the main thread with the SSE event name
    /// (`connected`, `new_email`, …). The `data:` payload is intentionally
    /// not forwarded — callers reload from the API instead.
    var onEvent: ((String) -> Void)?

    private let lock = NSLock()
    private var streamTask: Task<Void, Never>?
    private weak var client: APIClient?
    private var backoff: TimeInterval = SSEClient.initialBackoff

    private static let initialBackoff: TimeInterval = 1
    private static let maxBackoff: TimeInterval = 60

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        // The backend sends a `: keepalive` comment every 15 s, so an idle
        // gap well beyond that means the connection is dead.
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration)
    }()

    private override init() {
        super.init()
    }

    /// Opens the stream for the given client. A second call with the same
    /// client is a no-op; a different client restarts the connection so only
    /// one stream exists per session.
    func connect(client: APIClient) {
        lock.lock()
        if streamTask != nil, self.client === client {
            lock.unlock()
            return
        }
        disconnectLocked()
        self.client = client
        backoff = Self.initialBackoff
        streamTask = Task { [weak self] in await self?.runLoop() }
        lock.unlock()
    }

    /// Closes the stream and cancels any pending reconnect. Safe to call
    /// when no connection is open (logout, background, profile switch).
    func disconnect() {
        lock.lock()
        disconnectLocked()
        lock.unlock()
    }

    private func disconnectLocked() {
        streamTask?.cancel()
        streamTask = nil
        client = nil
        backoff = Self.initialBackoff
    }

    private func runLoop() async {
        while !Task.isCancelled {
            do {
                try await streamOnce()
            } catch is CancellationError {
                break
            } catch {
                // Transport / HTTP / decode failure — fall through to backoff.
                #if DEBUG
                print("[SSE] stream ended: \(error.localizedDescription)")
                #endif
            }
            guard !Task.isCancelled else { break }
            let delay = currentBackoff()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            increaseBackoff()
        }
    }

    private func currentBackoff() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return backoff
    }

    private func increaseBackoff() {
        lock.lock()
        backoff = min(backoff * 2, Self.maxBackoff)
        lock.unlock()
    }

    private func resetBackoff() {
        lock.lock()
        backoff = Self.initialBackoff
        lock.unlock()
    }

    /// One streaming attempt: reads response lines incrementally and emits
    /// complete events. Returns when the server closes the stream; throws on
    /// transport errors, cancellation or unexpected HTTP status.
    private func streamOnce() async throws {
        guard let request = currentRequest() else { throw CancellationError() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw APIClientError.unauthorized }
            throw APIClientError.http(http.statusCode)
        }

        var eventName = ""
        var dataLines: [String] = []

        func emit() async {
            let name = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
            let data = dataLines.joined(separator: "\n")
            eventName = ""
            dataLines = []
            guard !name.isEmpty else { return }
            await handleEvent(name: name, data: data)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty {
                // Blank line terminates the current frame.
                if !eventName.isEmpty || !dataLines.isEmpty {
                    await emit()
                }
                continue
            }
            if line.hasPrefix(":") {
                // Keepalive comment (`: keepalive`) — no payload.
                continue
            }
            if line.hasPrefix("event:") {
                eventName = String(line.dropFirst("event:".count))
            } else if line.hasPrefix("data:") {
                // A single space after the colon is conventional, not required.
                var value = String(line.dropFirst("data:".count))
                if value.hasPrefix(" ") { value.removeFirst() }
                dataLines.append(value)
            }
        }
    }

    private func currentRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return client?.sseEventsRequest()
    }

    @MainActor
    private func handleEvent(name: String, data: String) {
        switch name {
        case "connected":
            resetBackoff()
        case "new_email":
            NotificationCenter.default.post(name: .newEmailReceived, object: nil)
        default:
            break
        }
        onEvent?(name)
    }
}
