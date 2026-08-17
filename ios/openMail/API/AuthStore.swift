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

    /// Signs in with the Flask backend: stores the session cookie, resolves
    /// the user via `/api/me` and caches it in `user`.
    func login(username: String, password: String) async throws {
        let loggedInUser = try await client.login(username: username, password: password)
        user = loggedInUser
        isAuthenticated = true
    }

    /// Calls `/api/logout` (best effort) and resets the local state so the UI
    /// returns to the login screen.
    func logout() async {
        await client.logout()
        user = nil
        isAuthenticated = false
    }
}