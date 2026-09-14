import Foundation
import StoreKit
import Combine

typealias TransactionUpdateListener = Task<Void, Error>
typealias SubscriptionStatus = StoreKit.Product.SubscriptionInfo.RenewalState

@MainActor
class StoreManager: ObservableObject {
    @Published var monthlyProduct: Product?
    @Published var yearlyProduct: Product?
    @Published var lifetimeProduct: Product?
    @Published var isTransactionInProgress = false
    @Published var subscriptionGroupStatus: SubscriptionStatus?
    @Published var isLoadingProducts = false
    /// Why the store section is empty or a purchase did not go through. Shown
    /// in Settings so a TestFlight tester (or App Review) sees the cause
    /// instead of a section with nothing to buy.
    @Published var storeMessage: String?

    private let monthlyProductID = "com.baseonline.zammadmobile.premium.month"
    private let yearlyProductID = "com.baseonline.zammadmobile.premium.yearly"
    private let lifetimeProductID = "com.baseonline.zammadmobile.premium.lifetime"
    private var transactionListener: TransactionUpdateListener?

    var hasProducts: Bool { monthlyProduct != nil || yearlyProduct != nil || lifetimeProduct != nil }

    init() {
        transactionListener = listenForTransactionUpdates()
        Task {
            isLoadingProducts = true
            await fetchProducts()
            await checkEntitlements()
            isLoadingProducts = false
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }

    func fetchProducts() async {
        let wanted = [monthlyProductID, yearlyProductID, lifetimeProductID]
        do {
            let products = try await Product.products(for: wanted)
            for product in products {
                if product.id == monthlyProductID { monthlyProduct = product }
                else if product.id == yearlyProductID { yearlyProduct = product }
                else if product.id == lifetimeProductID { lifetimeProduct = product }
            }
            let missing = wanted.filter { id in !products.contains { $0.id == id } }
            if !missing.isEmpty {
                // The App Store silently drops ids it cannot serve: not "Ready to
                // Submit", missing localisation, unsigned Paid Apps agreement.
                print("Store: products not returned by the App Store: \(missing)")
            }
            storeMessage = products.isEmpty ? "products_unavailable".localized() : nil
        } catch {
            print("Failed to fetch products: \(error)")
            storeMessage = "products_load_failed".localized() + " " + error.localizedDescription
        }
    }

    /// Retry after a failed or empty load.
    func reload() async {
        isLoadingProducts = true
        storeMessage = nil
        await fetchProducts()
        await checkEntitlements()
        isLoadingProducts = false
    }
    
    func purchase(_ product: Product) async {
        isTransactionInProgress = true
        storeMessage = nil
        do {
            let result = try await product.purchase()
            try await handlePurchaseResult(result)
        } catch StoreKitError.userCancelled {
            // Sheet dismissed; nothing to report.
        } catch {
            print("Purchase failed: \(error)")
            storeMessage = "purchase_failed".localized() + " " + error.localizedDescription
        }
        isTransactionInProgress = false
    }
    
    func restorePurchases() async {
        storeMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            print("Failed to restore purchases: \(error)")
            storeMessage = "purchase_failed".localized() + " " + error.localizedDescription
        }
        // Re-evaluate entitlements regardless of the sync outcome.
        await checkEntitlements()
    }

    /// Premium comes from the lifetime unlock or an active subscription, and
    /// from nothing else. There is deliberately no automatic grant for
    /// non-production builds: App Review runs in the same sandbox environment
    /// as TestFlight, so granting there would hide the paywall from the
    /// reviewer and leave the purchase untestable. Sandbox purchases are free,
    /// so testers can still unlock everything without paying.
    func checkEntitlements() async {
        var hasLifetime = false
        for await result in Transaction.currentEntitlements(for: lifetimeProductID) {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                hasLifetime = true
            }
        }

        var isSubscribed = false
        if let product = monthlyProduct ?? yearlyProduct,
           let statuses = try? await product.subscription?.status {
            var highestStatus: SubscriptionStatus?
            for status in statuses {
                highestStatus = status.state
            }
            if let status = highestStatus {
                subscriptionGroupStatus = status
                isSubscribed = status == .subscribed || status == .inGracePeriod
            }
        }

        SettingsManager.shared.save(areAdsRemoved: hasLifetime || isSubscribed)
    }

    private func listenForTransactionUpdates() -> TransactionUpdateListener {
        return Task.detached {
            for await result in Transaction.updates {
                await self.handleTransactionVerification(result)
            }
        }
    }
    
    private func handlePurchaseResult(_ result: Product.PurchaseResult) async throws {
        switch result {
        case .success(let verification):
            await handleTransactionVerification(verification)
        case .pending:
            // Ask to Buy or a pending SCA step; the transaction arrives via Transaction.updates.
            storeMessage = "purchase_pending".localized()
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }
    
    private func handleTransactionVerification(_ result: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = result {
            await checkEntitlements()
            await transaction.finish()
        }
    }
}
