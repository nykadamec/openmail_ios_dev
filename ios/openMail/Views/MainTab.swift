import SwiftUI

/// The signed-in shell. Three tabs give quick access to the inbox, a new
/// message and account settings. The native tab bar is hidden – navigation
/// is driven by the floating `CraftTabBar` (směr C) overlaid at the bottom.
struct MainTab: View {
    @State private var selection = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                InboxView()
                    .tag(0)
                    .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    ComposerView(isPresented: false)
                }
                .tag(1)
                .toolbar(.hidden, for: .tabBar)

                SettingsView()
                    .tag(2)
                    .toolbar(.hidden, for: .tabBar)
            }
            // Volný prostor pod obsahem tabů, aby ho nepřekrývala
            // plovoucí pilulka (68) + spodní odsazení.
            .safeAreaPadding(.bottom, 86)

            CraftTabBar(selection: $selection)
                .padding(.init(top: 4, leading: 16, bottom: 14, trailing: 16))
        }
    }
}
