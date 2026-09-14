import SwiftUI

@main
struct OpenMailApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var authStore = AuthStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authStore)
                .task {
                    // Ask for notification permission the first time the app
                    // launches.  Idempotent — subsequent launches are no-ops
                    // when the user has already answered.
                    await NotificationsCoordinator.shared.requestAuthorizationIfNeeded()
                    if authStore.isAuthenticated {
                        SSEClient.shared.connect(client: authStore.activeClient)
                    }
                }
                .onChange(of: authStore.isAuthenticated) { _, authenticated in
                    // Login / restored session opens the live stream, logout
                    // closes it. Profile switches recreate the client while
                    // unauthenticated, so the next login connects the new one.
                    if authenticated {
                        SSEClient.shared.connect(client: authStore.activeClient)
                    } else {
                        SSEClient.shared.disconnect()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        NotificationsCoordinator.shared.scheduleNextRefresh()
                        // iOS suspends sockets in the background anyway.
                        SSEClient.shared.disconnect()
                    } else if phase == .active, authStore.isAuthenticated {
                        SSEClient.shared.connect(client: authStore.activeClient)
                    }
                }
        }
    }
}