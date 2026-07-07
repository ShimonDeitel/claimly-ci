import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var purchases: PurchaseManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "clock.fill") }
                .environmentObject(store)
                .environmentObject(purchases)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .environmentObject(store)
                .environmentObject(purchases)
        }
        .tint(Theme.safeBlue)
    }
}
