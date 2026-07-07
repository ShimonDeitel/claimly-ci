import SwiftUI

@main
struct ClaimlyApp: App {
    @StateObject private var store = Store()
    @StateObject private var purchases = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(purchases)
        }
    }
}
