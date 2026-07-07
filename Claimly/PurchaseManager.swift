import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let proProductId = "claimly_pro"

    @Published private(set) var isPro: Bool = false
    @Published private(set) var product: Product?
    @Published var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update: update)
            }
        }
        Task { await refreshProduct() }
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refreshProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductId])
            product = products.first
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.proProductId {
                isPro = true
                return
            }
        }
        isPro = false
    }

    func purchasePro() async {
        guard let product else {
            await refreshProduct()
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isPro = true
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func handle(update: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = update, transaction.productID == Self.proProductId {
            isPro = true
            await transaction.finish()
        }
    }
}
