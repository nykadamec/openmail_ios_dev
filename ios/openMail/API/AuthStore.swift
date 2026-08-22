import Foundation
import Observation

/// Holds the signed-in user and drives the login/logout flows.
///
/// Instances are meant to live at the app root (e.g. a `@State` on the
/// `App`) and are observed by SwiftUI views.
@Observable
final class AuthStore {
    struct SessionToken {
        let client: APIClient
        let generation: Int
    }
    let profileStore: ServerProfileStore
    private(set) var activeProfile: ServerProfile
    private(set) var activeClient: APIClient
    /// Invalidates in-flight auth work when a newer auth action takes over.
    private var sessionGeneration = 0

    func sessionToken() -> SessionToken {
        SessionToken(client: activeClient, generation: sessionGeneration)
    }

    func isCurrent(_ token: SessionToken) -> Bool {
        token.generation == sessionGeneration && token.client === activeClient
    }

    /// The signed-in user, or `nil` when logged out.
    var user: User?
    /// Derived from `user`; the UI can bind navigation to this flag.
    var isAuthenticated = false
    var isRestoringSession = false
    var restoreError: APIClientError?

    init(profileStore: ServerProfileStore = ServerProfileStore()) {
        self.profileStore = profileStore
        let profile = profileStore.activeProfile ?? .defaultPublicProfile
        activeProfile = profile
        activeClient = APIClient(baseURL: profile.baseURL, profileID: profile.id)
    }

    /// Switches the endpoint and deliberately requires authentication again.
    /// Each client has its own cookie jar and profile-namespaced keychain entry.
    func switchProfile(id: UUID) async {
        guard let profile = profileStore.profiles.first(where: { $0.id == id }), profile.id != activeProfile.id else { return }
        sessionGeneration += 1
        isRestoringSession = false
        let oldClient = activeClient
        let clearToken = oldClient.invalidateAuthOperations()
        oldClient.cancelPendingRequests()
        oldClient.clearSession(ifCurrent: clearToken)
        activeProfile = profile
        activeClient = APIClient(baseURL: profile.baseURL, profileID: profile.id)
        try? profileStore.setActiveProfile(id: id)
        user = nil
        isAuthenticated = false
        restoreError = nil
    }

    /// Signs in with the Flask backend: stores the session cookie, resolves
    /// the user via `/api/me` and caches it in `user`.
    func login(username: String, password: String, rememberMe: Bool = false) async throws {
        // Invalidate a restore before its network request can complete.  A
        // stale restore must not overwrite the session established by login.
        sessionGeneration += 1
        let generation = sessionGeneration
        isRestoringSession = false

        let client = activeClient
        let loggedInUser = try await client.login(username: username, password: password, rememberMe: rememberMe)
        guard generation == sessionGeneration else { return }
        user = loggedInUser
        isAuthenticated = true
    }

    /// Validates the current in-memory cookie, then tries the persisted cookie.
    /// Transport errors are retained so the UI can offer a retry without
    /// pretending that the user has signed out.
    func restoreSession() async {
        // The root view's task can be recreated when the login view is
        // replaced by the main shell.  Never validate (or clear) a session
        // that has already been established by a successful login.
        guard !isAuthenticated else { return }

        sessionGeneration += 1
        let generation = sessionGeneration
        let client = activeClient
        let operation = client.invalidateAuthOperations()

        isRestoringSession = true
        restoreError = nil
        defer {
            if generation == sessionGeneration {
                isRestoringSession = false
            }
        }

        do {
            if !client.hasSessionCookie { _ = client.restorePersistedSession(for: operation) }
            let restoredUser = try await client.me()
            guard generation == sessionGeneration else { return }
            user = restoredUser
            isAuthenticated = true
        } catch let error as APIClientError {
            guard generation == sessionGeneration else { return }
            switch error {
            case .unauthorized:
                client.clearSession(ifCurrent: operation)
                user = nil
                isAuthenticated = false
            case .network:
                restoreError = error
            default:
                restoreError = error
            }
        } catch {
            guard generation == sessionGeneration else { return }
            restoreError = .unexpectedResponse
        }
    }

    /// Calls `/api/logout` (best effort) and resets the local state so the UI
    /// returns to the login screen.
    func logout() async {
        sessionGeneration += 1
        let generation = sessionGeneration
        isRestoringSession = false

        let client = activeClient
        // APIClient invalidates its auth generation before awaiting the
        // server request and clears credentials afterwards with that token.
        // This keeps a newer login safe from a late logout completion.
        client.cancelPendingRequests()
        user = nil
        isAuthenticated = false
        await client.logout()
        guard generation == sessionGeneration else { return }
    }
}
