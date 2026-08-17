import Foundation
import Observation

/// Holds the signed-in user and drives the login/logout flows.
///
/// Instances are meant to live at the app root (e.g. a `@State` on the
/// `App`) and are observed by SwiftUI views.
@Observable
final class AuthStore {
    private let client = APIClient.shared

    /// The signed-in user, or `nil` when logged out.
    var user: User?
    /// Derived from `user`; the UI can bind navigation to this flag.
    var isAuthenticated = false
    var isRestoringSession = false
    var restoreError: APIClientError?

    /// Signs in with the Flask backend: stores the session cookie, resolves
    /// the user via `/api/me` and caches it in `user`.
    func login(username: String, password: String, rememberMe: Bool = false) async throws {
        let loggedInUser = try await client.login(username: username, password: password, rememberMe: rememberMe)
        user = loggedInUser
        isAuthenticated = true
    }

    /// Validates the current in-memory cookie, then tries the persisted cookie.
    /// Transport errors are retained so the UI can offer a retry without
    /// pretending that the user has signed out.
    func restoreSession() async {
        isRestoringSession = true
        restoreError = nil
        defer { isRestoringSession = false }

        do {
            if !client.hasSessionCookie { _ = client.restorePersistedSession() }
            let restoredUser = try await client.me()
            user = restoredUser
            isAuthenticated = true
        } catch let error as APIClientError {
            switch error {
            case .unauthorized:
                client.clearSession()
                user = nil
                isAuthenticated = false
            case .network:
                restoreError = error
            default:
                restoreError = error
            }
        } catch {
            restoreError = .unexpectedResponse
        }
    }

    /// Calls `/api/logout` (best effort) and resets the local state so the UI
    /// returns to the login screen.
    func logout() async {
        await client.logout()
        user = nil
        isAuthenticated = false
    }
}
