import SwiftUI

@main
struct OpenMailApp: App {
    @State private var authStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authStore)
        }
    }
}
