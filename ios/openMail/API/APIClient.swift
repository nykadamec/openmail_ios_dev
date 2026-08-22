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
/// intermediate redirect response. The captured cookie is kept per task and
/// is never written to the client's active cookie jar from a URLSession
/// callback. The auth operation which owns the task must explicitly commit it.
private final class CookieCaptureDelegate: NSObject, URLSessionDataDelegate {
    private let baseHost: String
    private let lock = NSLock()
    private final class TaskState {
        var response: URLResponse?
        var data = Data()
        var capturedSessionCookie: HTTPCookie?
        var completion: ((Result<CaptureResult, Error>) -> Void)?
    }

    private var tasks: [Int: TaskState] = [:]

    init(baseHost: String) {
        self.baseHost = baseHost.lowercased()
    }

    func register(
        _ task: URLSessionDataTask,
        completion: @escaping (Result<CaptureResult, Error>) -> Void
    ) {
        lock.lock()
        let state = TaskState()
        state.completion = completion
        tasks[task.taskIdentifier] = state
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        if let state = tasks[dataTask.taskIdentifier] {
            state.response = response
            if let cookie = capture(from: response) {
                state.capturedSessionCookie = cookie
            }
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        tasks[dataTask.taskIdentifier]?.data.append(data)
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        let state = tasks[task.taskIdentifier]
        if let cookie = capture(from: response) {
            state?.capturedSessionCookie = cookie
        }
        let capturedCookie = state?.capturedSessionCookie
        lock.unlock()
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

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let state = tasks.removeValue(forKey: task.taskIdentifier),
              let completion = state.completion else {
            lock.unlock()
            return
        }
        let result: Result<CaptureResult, Error>
        if let error {
            result = .failure(error)
        } else if let response = state.response {
            result = .success(CaptureResult(
                data: state.data,
                response: response,
                capturedSessionCookie: state.capturedSessionCookie
            ))
        } else {
            result = .failure(URLError(.badServerResponse))
        }
        lock.unlock()
        completion(result)
    }

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
        return validCookies.last
    }

    private func cookieDomainMatches(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return domain == baseHost || baseHost.hasSuffix("." + domain)
    }
}

private struct CaptureResult {
    let data: Data
    let response: URLResponse
    let capturedSessionCookie: HTTPCookie?
}

// MARK: - Client

/// Thin async/await wrapper around the openMail Flask JSON API.
///
/// Uses a private cookie jar so only the openMail session is persisted/removed.
final class APIClient {
    static let shared = APIClient()

    let base: URL
    let profileID: UUID
    private let cookieStorage = HTTPCookieStorage()
    private let keychain: KeychainStore
    private let cookieCaptureDelegate: CookieCaptureDelegate
    private let authOperationLock = NSLock()
    private var authOperationGeneration = 0

    /// A capability for the auth coordinator to clear only the session which
    /// belongs to the currently active auth operation.
    struct AuthOperationToken {
        fileprivate let generation: Int
    }
    /// Private session – its cookie jar holds only this client's cookies.
    let session: URLSession

    init(baseURL: URL = ServerProfile.defaultPublicProfile.baseURL,
         profileID: UUID = ServerProfile.defaultPublicProfile.id) {
        self.base = baseURL
        self.profileID = profileID
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = cookieStorage
        // Cookie state is committed only while authOperationLock is held.
        // Letting URLSession mutate the jar from a callback would reintroduce
        // a stale login/restore race, so requests attach cookies explicitly.
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        cookieCaptureDelegate = CookieCaptureDelegate(baseHost: base.host ?? "")
        session = URLSession(configuration: configuration, delegate: cookieCaptureDelegate, delegateQueue: nil)
        keychain = KeychainStore(account: profileID.uuidString)
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
        let operation = beginAuthOperation()
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
        let (_, response, capturedCookie) = try await performWithCookie(request)
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
        // Validate with this login's captured cookie, not with the mutable
        // active jar. The final cookie/Keychain commit follows below and is
        // generation-checked as one critical section.
        guard let capturedCookie else { throw APIClientError.unexpectedResponse }
        let loggedInUser = try await me(using: capturedCookie)
        guard commitLogin(cookie: capturedCookie, rememberMe: rememberMe, for: operation) else {
            return loggedInUser
        }
        return loggedInUser
    }

    /// Whether this private session currently has an openMail session cookie.
    var hasSessionCookie: Bool { sessionCookie() != nil }

    /// Imports the persisted cookie, if available. Keychain failures are treated
    /// as an unavailable credential rather than an application-fatal error.
    @discardableResult
    func restorePersistedSession() -> Bool {
        restorePersistedSession(for: beginAuthOperation())
    }

    @discardableResult
    func restorePersistedSession(for operation: AuthOperationToken?) -> Bool {
        let operation = operation ?? beginAuthOperation()
        let storedValue: String?
        do {
            storedValue = try keychain.read()
        } catch {
            return false
        }
        guard let value = storedValue, !value.isEmpty,
              let cookie = makeCookie(value: value) else { return false }
        authOperationLock.lock()
        defer { authOperationLock.unlock() }
        if operation.generation != authOperationGeneration { return false }
        replaceSessionCookieLocked(with: cookie)
        return true
    }

    /// Removes only the openMail session cookie and its persisted copy.
    func clearSession() {
        authOperationLock.lock()
        authOperationGeneration += 1
        removeSessionCredentialsLocked()
        authOperationLock.unlock()
    }

    /// Clears credentials only when the caller still owns the auth operation.
    func clearSession(ifCurrent token: AuthOperationToken) {
        authOperationLock.lock()
        guard token.generation == authOperationGeneration else {
            authOperationLock.unlock()
            return
        }
        // Invalidate first, but keep invalidation and the clear in the same
        // critical section so no commit can slip between the two operations.
        authOperationGeneration += 1
        removeSessionCredentialsLocked()
        authOperationLock.unlock()
    }

    private func removeSessionCredentialsLocked() {
        for cookie in cookieStorage.cookies ?? [] where cookie.name == "session_id" && cookieDomainMatches(cookie) {
            cookieStorage.deleteCookie(cookie)
        }
        try? keychain.delete()
    }

    /// Commits a successful login only while its operation generation still
    /// owns the client. Cookie storage and Keychain are deliberately mutated
    /// under the same lock as the generation check.
    private func commitLogin(
        cookie: HTTPCookie?,
        rememberMe: Bool,
        for operation: AuthOperationToken
    ) -> Bool {
        guard let cookie,
              cookie.name == "session_id",
              cookieDomainMatches(cookie),
              !cookie.value.isEmpty else { return false }

        authOperationLock.lock()
        defer { authOperationLock.unlock() }
        guard operation.generation == authOperationGeneration else { return false }

        if rememberMe {
            do {
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
        } else {
            try? keychain.delete()
        }
        replaceSessionCookieLocked(with: cookie)
        return true
    }

    /// Cancels requests belonging to this profile without affecting any other
    /// profile's private URLSession.
    func cancelPendingRequests() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }

    /// Invalidates authentication work whose result must no longer be persisted.
    @discardableResult
    func invalidateAuthOperations() -> AuthOperationToken {
        authOperationLock.lock()
        authOperationGeneration += 1
        let token = AuthOperationToken(generation: authOperationGeneration)
        authOperationLock.unlock()
        return token
    }

    private func beginAuthOperation() -> AuthOperationToken {
        authOperationLock.lock()
        defer { authOperationLock.unlock() }
        authOperationGeneration += 1
        return AuthOperationToken(generation: authOperationGeneration)
    }

    /// GET /api/me – validates the session and returns the current user.
    func me() async throws -> User {
        let (data, response) = try await perform(URLRequest(url: url("api/me")))
        try validate(response)
        return try decode(User.self, from: data)
    }

    private func me(using cookie: HTTPCookie) async throws -> User {
        var request = URLRequest(url: url("api/me"))
        request.setValue(
            HTTPCookie.requestHeaderFields(with: [cookie])["Cookie"],
            forHTTPHeaderField: "Cookie"
        )
        let (data, response) = try await perform(request, cookieOverride: cookie)
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

    // MARK: Contacts and domain rules

    /// GET /api/contacts, optionally filtered by the server-side `q` search.
    func contacts(q: String? = nil) async throws -> [Contact] {
        var query: [URLQueryItem] = []
        if let q, !q.isEmpty { query.append(URLQueryItem(name: "q", value: q)) }
        let (data, response) = try await perform(URLRequest(url: url("api/contacts", query: query)))
        try validate(response)
        return try decodeCollection(Contact.self, from: data, keys: ["contacts", "items"])
    }

    /// Convenience alias for callers which explicitly expose a search action.
    func searchContacts(_ query: String) async throws -> [Contact] {
        try await contacts(q: query)
    }

    /// Named variant of `contacts(q:)` for callers that separate list/search.
    func listContacts(query: String? = nil) async throws -> [Contact] {
        try await contacts(q: query)
    }

    /// Labeled search variant for use from SwiftUI view models.
    func searchContacts(query: String) async throws -> [Contact] {
        try await contacts(q: query)
    }

    /// POST /api/contacts with `{name, email, notes}`.
    func createContact(name: String, email: String, notes: String? = nil) async throws -> Contact {
        var fields: [String: Any] = ["name": name, "email": email]
        if let notes { fields["notes"] = notes }
        return try await contactRequest(path: "api/contacts", method: "POST", fields: fields)
    }

    /// PATCH /api/contacts/<id>. Allowed fields are determined by the server.
    func updateContact(id: Int, fields: [String: Any]) async throws -> Contact {
        try await contactRequest(path: "api/contacts/\(id)", method: "PATCH", fields: fields)
    }

    /// DELETE /api/contacts/<id>.
    func deleteContact(id: Int) async throws {
        var request = URLRequest(url: url("api/contacts/\(id)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await perform(request)
        try validate(response)
    }

    /// GET /api/domain-rules. Rules are consistently addressed by this path.
    func contactRules() async throws -> [ContactRule] {
        let (data, response) = try await perform(URLRequest(url: url("api/domain-rules")))
        try validate(response)
        return try decodeCollection(ContactRule.self, from: data, keys: ["rules", "contact_rules", "items"])
    }

    func listContactRules() async throws -> [ContactRule] {
        try await contactRules()
    }

    /// POST /api/domain-rules with `{domain, ...}`.
    func createContactRule(domain: String, isStarred: Bool = true) async throws -> ContactRule {
        try await contactRuleRequest(path: "api/domain-rules", method: "POST",
                                     fields: ["domain": domain, "is_starred": isStarred])
    }

    /// PATCH /api/domain-rules/<id>.
    func updateContactRule(id: Int, fields: [String: Any]) async throws -> ContactRule {
        try await contactRuleRequest(path: "api/domain-rules/\(id)", method: "PATCH", fields: fields)
    }

    /// DELETE /api/domain-rules/<id>.
    func deleteContactRule(id: Int) async throws {
        var request = URLRequest(url: url("api/domain-rules/\(id)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await perform(request)
        try validate(response)
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

    /// Downloads an attachment through this client's private, authenticated session.
    func downloadAttachment(emailId: Int, filename: String) async throws -> Data {
        let (data, response) = try await perform(URLRequest(url: attachmentURL(emailId: emailId, filename: filename)))
        try validate(response)
        return data
    }

    /// POST /api/logout, then wipe any stored credentials and cookies.
    func logout() async {
        // Invalidate before awaiting the network request. The same token is
        // used after the await, so a newer login can never be cleared by this
        // logout's late completion.
        let operation = beginAuthOperation()
        var request = URLRequest(url: url("logout"))
        request.httpMethod = "POST"
        _ = try? await perform(request)
        clearSession(ifCurrent: operation)
    }

    // MARK: Helpers

    /// Strict container for the `/api/folders` response envelope.
    private struct FoldersResponse: Decodable {
        let custom: [FolderItem]?
    }

    private func contactRequest(path: String, method: String, fields: [String: Any]) async throws -> Contact {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await perform(request)
        try validate(response)
        return try decodeEnvelope(Contact.self, from: data, keys: ["contact"])
    }

    private func contactRuleRequest(path: String, method: String, fields: [String: Any]) async throws -> ContactRule {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await perform(request)
        try validate(response)
        return try decodeEnvelope(ContactRule.self, from: data, keys: ["rule", "contact_rule"])
    }

    private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data, keys: [String]) throws -> T {
        if let value = try? decode(type, from: data) { return value }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        for key in keys where object?[key] != nil {
            let nested = try JSONSerialization.data(withJSONObject: object![key]!)
            return try decode(type, from: nested)
        }
        throw APIClientError.decode
    }

    private func decodeCollection<T: Decodable>(_ type: T.Type, from data: Data, keys: [String]) throws -> [T] {
        if let values = try? decode([T].self, from: data) { return values }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        for key in keys where object?[key] != nil {
            let nested = try JSONSerialization.data(withJSONObject: object![key]!)
            return try decode([T].self, from: nested)
        }
        throw APIClientError.decode
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
        authOperationLock.lock()
        defer { authOperationLock.unlock() }
        return sessionCookieLocked()
    }

    private func sessionCookieLocked() -> HTTPCookie? {
        cookieStorage.cookies?.first(where: { cookie in
            cookie.name == "session_id" && cookieDomainMatches(cookie)
        })
    }

    private func replaceSessionCookieLocked(with cookie: HTTPCookie) {
        // Remove older domain/path variants so requests cannot select a stale
        // session after a successful login or restore.
        for storedCookie in cookieStorage.cookies ?? []
            where storedCookie.name == "session_id" && cookieDomainMatches(storedCookie) {
            cookieStorage.deleteCookie(storedCookie)
        }
        cookieStorage.setCookie(cookie)
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
        let result = try await performWithCookie(request)
        return (result.0, result.1)
    }

    private func perform(
        _ request: URLRequest,
        cookieOverride: HTTPCookie
    ) async throws -> (Data, URLResponse) {
        let result = try await performWithCookie(request, cookieOverride: cookieOverride)
        return (result.0, result.1)
    }

    private func performWithCookie(
        _ request: URLRequest,
        cookieOverride: HTTPCookie? = nil
    ) async throws -> (Data, URLResponse, HTTPCookie?) {
        var request = request
        let isBaseHostRequest = request.url?.host?.lowercased() == base.host?.lowercased()
        let isLoginRequest = request.url?.path == "/login"
        if isBaseHostRequest && isLoginRequest {
            // Do not let URLSession attach an old cookie to a new login.  The
            // delegate still captures and forwards the newly issued cookie on
            // redirects.
            request.httpShouldHandleCookies = false
        } else if isBaseHostRequest,
                  let cookie = cookieOverride ?? sessionCookie(),
                  let cookieHeader = HTTPCookie.requestHeaderFields(with: [cookie])["Cookie"] {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        do {
            let task = session.dataTask(with: request)
            let result = try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CaptureResult, Error>) in
                    cookieCaptureDelegate.register(task) { result in
                        continuation.resume(with: result)
                    }
                    task.resume()
                }
            }, onCancel: {
                task.cancel()
            })
            #if DEBUG
            if let http = result.response as? HTTPURLResponse {
                Logger(subsystem: "com.openmail", category: "api").debug(
                    "HTTP \(http.statusCode, privacy: .public) \(request.httpMethod ?? "GET", privacy: .public) \(request.url?.path ?? "", privacy: .public) content-type=\(http.value(forHTTPHeaderField: "Content-Type") ?? "none", privacy: .public)"
                )
            }
            #endif
            return (result.data, result.response, result.capturedSessionCookie)
        } catch let error as URLError {
            #if DEBUG
            Logger(subsystem: "com.openmail", category: "api").debug("Network error \(error.code.rawValue, privacy: .public)")
            #endif
            throw APIClientError.network(error.code)
        }
    }
}
