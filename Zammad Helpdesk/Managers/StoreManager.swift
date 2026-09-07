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

    private let monthlyProductID = "com.baseonline.zammadmobile.premium.month"
    private let yearlyProductID = "com.baseonline.zammadmobile.premium.yearly"
    private let lifetimeProductID = "com.baseonline.zammadmobile.premium.lifetime"
    private var transactionListener: TransactionUpdateListener?

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
        do {
            let products = try await Product.products(for: [monthlyProductID, yearlyProductID, lifetimeProductID])
            for product in products {
                if product.id == monthlyProductID { monthlyProduct = product }
                else if product.id == yearlyProductID { yearlyProduct = product }
                else if product.id == lifetimeProductID { lifetimeProduct = product }
            }
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }
    
    func purchase(_ product: Product) async {
        isTransactionInProgress = true
        do {
            let result = try await product.purchase()
            try await handlePurchaseResult(result)
        } catch {
            print("Purchase failed: \(error)")
        }
        isTransactionInProgress = false
    }
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
        // Re-evaluate entitlements regardless of the sync outcome — this also
        // (re)applies the automatic TestFlight grant.
        await checkEntitlements()
    }

    /// Premium is granted by the lifetime unlock, an active subscription, or
    /// automatically for TestFlight/development builds so testers get the
    /// full feature set without purchasing.
    func checkEntitlements() async {
        var isTestBuild = false
        if let result = try? await AppTransaction.shared,
           case .verified(let appTransaction) = result {
            isTestBuild = appTransaction.environment != .production
        }

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

        SettingsManager.shared.save(areAdsRemoved: hasLifetime || isSubscribed || isTestBuild)
    }

    private func listenForTransactionUpdates() -> TransactionUpdateListener {
        return Task.detached {
            for await result in Transaction.updates {
                await self.handleTransactionVerification(result)
            }
        }
    }
    
    private func handlePurchaseResult(_ result: Product.PurchaseResult) async throws {
        if case .success(let verification) = result {
            await handleTransactionVerification(verification)
        }
    }
    
    private func handleTransactionVerification(_ result: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = result {
            await checkEntitlements()
            await transaction.finish()
        }
    }
}
