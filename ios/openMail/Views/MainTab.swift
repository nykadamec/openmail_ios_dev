import SwiftUI

/// The signed-in shell. Three tabs give quick access to the inbox, a new
/// message and account settings.
struct MainTab: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem {
                    Label("inbox.title", systemImage: "tray.full")
                }

            ComposerView()
                .tabItem {
                    Label("action.compose", systemImage: "square.and.pencil")
                }

            SettingsView()
                .tabItem {
                    Label("settings.account", systemImage: "person.crop.circle")
                }
        }
    }
}
