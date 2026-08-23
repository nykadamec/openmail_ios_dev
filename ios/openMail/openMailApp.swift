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
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        NotificationsCoordinator.shared.scheduleNextRefresh()
                    }
                }
        }
    }
}