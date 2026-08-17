import SwiftUI

/// Top-level switch between the signed-out login screen and the signed-in
/// tab shell, driven by `AuthStore.isAuthenticated`.
struct RootView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        Group {
            if authStore.isAuthenticated {
                MainTab()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authStore.isAuthenticated)
    }
}
