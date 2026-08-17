import Foundation
import os

// MARK: - Errors

enum APIClientError: Error, LocalizedError {
    /// A transport failure (DNS, timeout, offline device, etc.).
    case network(URLError.Code)
    /// The server returned a JSON error payload with a message.
    case server(String)
    /// Unexpected HTTP status code.
    case http(Int)
    /// HTTP 401 – session is missing, expired or the credentials were rejected.
    case unauthorized
    /// A successful HTTP response which was not the expected API payload
    /// (for example a Cloudflare/login HTML page).
    case unexpectedResponse
    /// The API returned JSON, but it did not match the expected model.
    case decode

    var errorDescription: String? {
        switch self {
        case .network: return NSLocalizedString("errors.network", comment: "Network failure")
        case .server(let message): return message
        case .http(let code): return "Server error (HTTP \(code))"
        case .unauthorized: return "Session expired"
        case .unexpectedResponse: return NSLocalizedString("errors.unexpectedResponse", comment: "Unexpected server response")
        case .decode: return NSLocalizedString("errors.unexpectedResponse", comment: "Unexpected server response")
        }
    }
}

/// Captures the authentication cookie on every response, including an
/// intermediate redirect response.  The delegate deliberately imports only
/// the session_id cookie; no response headers are retained or logged.
private final class CookieCaptureDelegate: NSObject, URLSessionDataDelegate {
    private let storage: HTTPCookieStorage
    private let baseHost: String
    private let lock = NSLock()
    private var lastCapturedSessionCookie: HTTPCookie?

    init(storage: HTTPCookieStorage, baseHost: String) {
        self.storage = storage
        self.baseHost = baseHost.lowercased()
    }

    /// The last valid session cookie captured from the openMail host.  Access
    /// is synchronized because URLSession delegate callbacks are not required
    /// to run on the caller's thread.
    var capturedSessionCookie: HTTPCookie? {
        lock.lock()
        defer { lock.unlock() }
        return lastCapturedSessionCookie
    }

    func clearCapturedSessionCookie() {
        lock.lock()
        lastCapturedSessionCookie = nil
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        capture(from: response)
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let capturedCookie = capture(from: response) ?? capturedSessionCookie
        guard request.url?.host?.lowercased() == baseHost,
              let capturedCookie,
              let cookieHeader = HTTPCookie.requestHeaderFields(with: [capturedCookie])["Cookie"] else {
            completionHandler(request)
            return
        }

        var redirectRequest = request
        redirectRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        completionHandler(redirectRequest)
    }

    @discardableResult
    private func capture(from response: URLResponse) -> HTTPCookie? {
        guard let http = response as? HTTPURLResponse,
              let responseURL = http.url,
              responseURL.host?.lowercased() == baseHost,
              let setCookie = http.value(forHTTPHeaderField: "Set-Cookie"),
              !setCookie.isEmpty else { return nil }

        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": setCookie],
            for: responseURL
        )
        let validCookies = cookies.filter { cookie in
            cookie.name == "session_id" && cookieDomainMatches(cookie) && !cookie.value.isEmpty
        }
        guard let capturedCookie = validCookies.last else { return nil }

        // Remove older domain/path variants so sessionCookie() cannot select a
        // stale cookie instead of the one just issued by the server.
        for cookie in storage.cookies ?? [] where cookie.name == "session_id" && cookieDomainMatches(cookie) {
            storage.deleteCookie(cookie)
        }
        storage.setCookie(capturedCookie)

        lock.lock()
        lastCapturedSessionCookie = capturedCookie
        lock.unlock()
        return capturedCookie
    }

    private func cookieDomainMatches(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return domain == baseHost || baseHost.hasSuffix("." + domain)
    }
}

// MARK: - Client

/// Thin async/await wrapper around the openMail Flask JSON API.
///
/// Uses a private cookie jar so only the openMail session is persisted/removed.
final class APIClient {
    static let shared = APIClient()

    let base = URL(string: "https://email.adamec.pro")!
    private let cookieStorage = HTTPCookieStorage()
    private let keychain = KeychainStore()
    private let cookieCaptureDelegate: CookieCaptureDelegate
    /// Private session – its cookie jar holds only this client's cookies.
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        // URLSession normally imports Set-Cookie headers itself, but doing this
        // explicitly is important for the 302 response between /login and the
        // final response.  In particular, this keeps the cookie when a custom
        // ephemeral cookie jar is used.
        cookieCaptureDelegate = CookieCaptureDelegate(storage: cookieStorage, baseHost: base.host ?? "")
        session = URLSession(configuration: configuration, delegate: cookieCaptureDelegate, delegateQueue: nil)
    }

    /// An attachment to send with `send(to:subject:body:attachments:)`.
    struct SendAttachment {
        let filename: String
        let data: Data
        let contentType: String
    }

    // MARK: Auth

    /// POST /login (form-urlencoded), then GET /api/me to resolve the user.
    func login(username: String, password: String, rememberMe: Bool = false) async throws -> User {
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "remember_me", value: rememberMe ? "1" : "0"),
        ]
        var request = URLRequest(url: url("login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.query?.data(using: .utf8)
        let (_, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.server("Invalid response")
        }
        // 401 = invalid credentials (rendered login page). After a successful
        // login the server redirects and the shared cookie jar keeps the
        // session_id, so the final response is the app shell (200).
        if http.statusCode == 401 { throw APIClientError.unauthorized }
        guard (200..<400).contains(http.statusCode) else {
            throw APIClientError.http(http.statusCode)
        }
        let loggedInUser = try await me()
        if rememberMe {
            if let cookie = sessionCookie() {
                do {
                    // Persist the cookie captured by this login, while keeping
                    // a successful server login independent of Keychain state.
                    try keychain.save(cookie.value)
                } catch let error as KeychainStore.StoreError {
                    #if DEBUG
                    switch error {
                    case .keychain(let status):
                        Logger(subsystem: "com.openmail", category: "keychain").debug(
                            "Session save failed category=keychain status=\(status, privacy: .public)"
                        )
                    case .invalidValue:
                        Logger(subsystem: "com.openmail", category: "keychain").debug(
                            "Session save failed category=keychain status=invalid-value"
                        )
                    }
                    #endif
                } catch {
                    #if DEBUG
                    Logger(subsystem: "com.openmail", category: "keychain").debug(
                        "Session save failed category=keychain status=unknown"
                    )
                    #endif
                }
            }
        } else {
            try? keychain.delete()
        }
        return loggedInUser
    }

    /// Whether this private session currently has an openMail session cookie.
    var hasSessionCookie: Bool { sessionCookie() != nil }

    /// Imports the persisted cookie, if available. Keychain failures are treated
    /// as an unavailable credential rather than an application-fatal error.
    @discardableResult
    func restorePersistedSession() -> Bool {
        let storedValue: String?
        do {
            storedValue = try keychain.read()
        } catch {
            return false
        }
        guard let value = storedValue, !value.isEmpty,
              let cookie = makeCookie(value: value) else { return false }
        for storedCookie in cookieStorage.cookies ?? [] where storedCookie.name == "session_id" && cookieDomainMatches(storedCookie) {
            cookieStorage.deleteCookie(storedCookie)
        }
        cookieStorage.setCookie(cookie)
        return true
    }

    /// Removes only the openMail session cookie and its persisted copy.
    func clearSession() {
        for cookie in cookieStorage.cookies ?? [] where cookie.name == "session_id" && cookieDomainMatches(cookie) {
            cookieStorage.deleteCookie(cookie)
        }
        cookieCaptureDelegate.clearCapturedSessionCookie()
        try? keychain.delete()
    }

    /// GET /api/me – validates the session and returns the current user.
    func me() async throws -> User {
        let (data, response) = try await perform(URLRequest(url: url("api/me")))
        try validate(response)
        return try decode(User.self, from: data)
    }

    // MARK: Emails

    /// GET /api/emails. When no filter is given the server defaults to inbox.
    func emails(
        folder: String? = nil,
        q: String? = nil,
        starred: Bool? = nil,
        isSpam: Bool? = nil,
        isTrash: Bool? = nil,
        customFolderId: Int? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> EmailPage {
        var items: [URLQueryItem] = []
        if let folder { items.append(URLQueryItem(name: "folder", value: folder)) }
        if let q { items.append(URLQueryItem(name: "q", value: q)) }
        if let starred { items.append(URLQueryItem(name: "starred", value: starred ? "1" : "0")) }
        if let isSpam { items.append(URLQueryItem(name: "is_spam", value: isSpam ? "1" : "0")) }
        if let isTrash { items.append(URLQueryItem(name: "is_trash", value: isTrash ? "1" : "0")) }
        if let customFolderId { items.append(URLQueryItem(name: "custom_folder_id", value: String(customFolderId))) }
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        items.append(URLQueryItem(name: "offset", value: String(offset)))
        let (data, response) = try await perform(URLRequest(url: url("api/emails", query: items)))
        try validate(response)
        try validateJSONResponse(response)
        return try decode(EmailPage.self, from: data)
    }

    /// GET /api/emails/<id> – full email including body and attachments.
    func email(id: Int) async throws -> EmailDetail {
        let (data, response) = try await perform(URLRequest(url: url("api/emails/\(id)")))
        try validate(response)
        return try decode(EmailDetail.self, from: data)
    }

    /// PATCH /api/emails/<id> with allowed fields (is_starred, is_read,
    /// folder, is_spam, is_trash, custom_folder_id).
    func patchEmail(id: Int, fields: [String: Any]) async throws -> EmailDetail {
        var request = URLRequest(url: url("api/emails/\(id)"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await perform(request)
        try validate(response)
        return try decode(EmailDetail.self, from: data)
    }

    /// GET /api/stats.
    func stats() async throws -> Stats {
        let (data, response) = try await perform(URLRequest(url: url("api/stats")))
        try validate(response)
        return try decode(Stats.self, from: data)
    }

    // MARK: Folders

    /// GET /api/folders. The response may be `{system: [...], custom: [...]}`;
    /// only the `custom` array is parsed – anything else yields an empty list.
    func folders() async throws -> [FolderItem] {
        let (data, response) = try await perform(URLRequest(url: url("api/folders")))
        try validate(response)
        let decoded = try? decode(FoldersResponse.self, from: data)
        return decoded?.custom ?? []
    }

    // MARK: Send

    /// POST /api/send with JSON `{to, subject, body, attachments}` where each
    /// attachment is `{filename, content: base64, content_type}`.
    func send(
        to: String,
        subject: String,
        body: String,
        attachments: [SendAttachment] = []
    ) async throws -> SendResult {
        var payload: [String: Any] = ["to": to, "subject": subject, "body": body]
        if !attachments.isEmpty {
            payload["attachments"] = attachments.map { att -> [String: String] in
                [
                    "filename": att.filename,
                    "content": att.data.base64EncodedString(),
                    "content_type": att.contentType,
                ]
            }
        }
        var request = URLRequest(url: url("api/send"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await perform(request)
        try validate(response)
        return try decode(SendResult.self, from: data)
    }

    // MARK: Attachments / logout

    /// GET /api/attachments/<email_id>/<filename> – the filename is split into
    /// path components so slashes inside it survive URL encoding.
    func attachmentURL(emailId: Int, filename: String) -> URL {
        var url = base
            .appendingPathComponent("api")
            .appendingPathComponent("attachments")
            .appendingPathComponent(String(emailId))
        for component in filename.split(separator: "/", omittingEmptySubsequences: false) {
            url.appendPathComponent(String(component))
        }
        return url
    }

    /// POST /api/logout, then wipe any stored credentials and cookies.
    func logout() async {
        var request = URLRequest(url: url("logout"))
        request.httpMethod = "POST"
        _ = try? await session.data(for: request)
        clearSession()
    }

    // MARK: Helpers

    /// Strict container for the `/api/folders` response envelope.
    private struct FoldersResponse: Decodable {
        let custom: [FolderItem]?
    }

    /// Builds a URL from a slash-separated path relative to `base`,
    /// percent-encoding each segment separately.
    private func url(_ path: String, query: [URLQueryItem]? = nil) -> URL {
        var url = base
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard let query, !query.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query
        return components.url ?? url
    }

    private func sessionCookie() -> HTTPCookie? {
        if let cookie = cookieStorage.cookies?.first(where: { cookie in
            cookie.name == "session_id" && cookieDomainMatches(cookie)
        }) {
            return cookie
        }
        guard let capturedCookie = cookieCaptureDelegate.capturedSessionCookie,
              capturedCookie.name == "session_id",
              cookieDomainMatches(capturedCookie) else { return nil }
        return capturedCookie
    }

    private func cookieDomainMatches(_ cookie: HTTPCookie) -> Bool {
        let host = base.host ?? ""
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let normalizedHost = host.lowercased()
        // A host-only cookie has the exact host as its domain.  A domain cookie
        // may also be set on a parent domain (for example .adamec.pro), but a
        // plain suffix check would incorrectly accept eviladamec.pro.
        return domain == normalizedHost || normalizedHost.hasSuffix("." + domain)
    }

    private func makeCookie(value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: base.host ?? "email.adamec.pro",
            .path: "/",
            .name: "session_id",
            .value: value,
            .secure: "TRUE",
        ])
    }

    /// Throws the appropriate `APIClientError` for an HTTP response;
    /// 401 always maps to `.unauthorized`.
    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse
        }
        if http.statusCode == 401 { throw APIClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIClientError.http(http.statusCode)
        }
    }

    /// API endpoints must return JSON. A proxy/login page can otherwise be a
    /// 200 response and would misleadingly look like an empty mailbox to the
    /// caller. Missing Content-Type is tolerated for backwards compatibility.
    private func validateJSONResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
              !contentType.isEmpty else { return }
        guard contentType.contains("application/json") || contentType.contains("+json") else {
            throw APIClientError.unexpectedResponse
        }
    }

    /// Decodes JSON defensively – a missing field must never crash the app,
    /// so any decode failure surfaces as a server-presentable error.
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            #if DEBUG
            Logger(subsystem: "com.openmail", category: "api").debug("Decode failed: \(String(describing: error), privacy: .public)")
            #endif
            throw APIClientError.decode
        }
    }

    /// One boundary for transport diagnostics. We deliberately never log
    /// request headers, cookies, query values or response bodies.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        let isBaseHostRequest = request.url?.host?.lowercased() == base.host?.lowercased()
        let isLoginRequest = request.url?.path == "/login"
        if isBaseHostRequest && isLoginRequest {
            // Do not let URLSession attach an old cookie to a new login.  The
            // delegate still captures and forwards the newly issued cookie on
            // redirects.
            request.httpShouldHandleCookies = false
        } else if isBaseHostRequest,
                  let cookie = sessionCookie(),
                  let cookieHeader = HTTPCookie.requestHeaderFields(with: [cookie])["Cookie"] {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        do {
            let result = try await session.data(for: request)
            #if DEBUG
            if let http = result.1 as? HTTPURLResponse {
                Logger(subsystem: "com.openmail", category: "api").debug(
                    "HTTP \(http.statusCode, privacy: .public) \(request.httpMethod ?? "GET", privacy: .public) \(request.url?.path ?? "", privacy: .public) content-type=\(http.value(forHTTPHeaderField: "Content-Type") ?? "none", privacy: .public)"
                )
            }
            #endif
            if let http = result.1 as? HTTPURLResponse, http.statusCode == 401 {
                clearSession()
                throw APIClientError.unauthorized
            }
            return result
        } catch let error as URLError {
            #if DEBUG
            Logger(subsystem: "com.openmail", category: "api").debug("Network error \(error.code.rawValue, privacy: .public)")
            #endif
            throw APIClientError.network(error.code)
        }
    }
}
