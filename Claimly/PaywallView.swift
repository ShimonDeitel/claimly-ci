import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.stampGreen)
                    .padding(.top, 24)

                Text("Claimly Pro")
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)

                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "infinity", text: "Track unlimited rebates (free tier caps at \(Store.freeLimit))")
                    featureRow(icon: "exclamationmark.triangle.fill", text: "See total dollars at risk of expiring soon")
                    featureRow(icon: "checkmark.seal.fill", text: "Support ongoing development")
                }
                .padding(.horizontal, 24)

                Spacer()

                if let product = purchases.product {
                    Button {
                        Task {
                            isPurchasing = true
                            await purchases.purchasePro()
                            isPurchasing = false
                            if purchases.isPro { dismiss() }
                        }
                    } label: {
                        HStack {
                            if isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Unlock Pro - \(product.displayPrice)")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.stampGreen)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("purchaseProButton")
                } else {
                    ProgressView("Loading price...")
                }

                Button("Restore Purchases") {
                    Task { await purchases.restorePurchases() }
                }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("restorePurchasesButtonPaywall")

                if let error = purchases.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.criticalRed)
                }
            }
            .padding(.bottom, 24)
            .background(Theme.backdrop.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("closePaywallButton")
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await purchases.refreshProduct() }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.safeBlue)
                .frame(width: 24)
            Text(text)
                .foregroundStyle(Theme.textPrimary)
                .font(.subheadline)
        }
    }
}
