import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var purchases: PurchaseManager

    @State private var notificationsEnabled: Bool = true
    @State private var leadDays: Int = 3
    @State private var showPaywall = false

    private let leadOptions = [1, 2, 3, 5, 7, 14]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Deadline Reminders", isOn: $notificationsEnabled)
                        .accessibilityIdentifier("notificationsToggle")
                        .onChange(of: notificationsEnabled) { _, newValue in
                            store.notificationsEnabled = newValue
                            if newValue { store.requestNotificationPermission() }
                        }

                    Picker("Remind Me Before Deadline", selection: $leadDays) {
                        ForEach(leadOptions, id: \.self) { days in
                            Text("\(days) day\(days == 1 ? "" : "s")").tag(days)
                        }
                    }
                    .accessibilityIdentifier("leadTimePicker")
                    .disabled(!notificationsEnabled)
                    .onChange(of: leadDays) { _, newValue in
                        store.notificationLeadDays = newValue
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Claimly will notify you this many days before a rebate's submission deadline.")
                }

                Section("Claimly Pro") {
                    if purchases.isPro {
                        Label("Pro Unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.stampGreen)
                    } else {
                        Button("Upgrade to Pro") { showPaywall = true }
                            .accessibilityIdentifier("upgradeToProButton")
                    }
                    Button("Restore Purchases") {
                        Task { await purchases.restorePurchases() }
                    }
                    .accessibilityIdentifier("restorePurchasesButtonSettings")
                }

                Section("About") {
                    Link("Privacy Policy", destination: URL(string: "https://shimondeitel.github.io/claimly-site/privacy.html")!)
                        .accessibilityIdentifier("privacyPolicyLink")
                    Link("Contact Support", destination: URL(string: "mailto:s0533495227@gmail.com")!)
                        .accessibilityIdentifier("contactSupportLink")
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(purchases)
            }
            .onAppear {
                notificationsEnabled = store.notificationsEnabled
                leadDays = store.notificationLeadDays
            }
        }
        .preferredColorScheme(.dark)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
