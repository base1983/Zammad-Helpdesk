import Foundation
import StoreKit
import Combine

typealias TransactionUpdateListener = Task<Void, Error>
typealias SubscriptionStatus = StoreKit.Product.SubscriptionInfo.RenewalState

@MainActor
class StoreManager: ObservableObject {
    @Published var monthlyProduct: Product?
    @Published var yearlyProduct: Product?
    @Published var isTransactionInProgress = false
    @Published var subscriptionGroupStatus: SubscriptionStatus?
    @Published var isLoadingProducts = false

    private let monthlyProductID = "com.baseonline.zammadmobile.premium.month"
    private let yearlyProductID = "com.baseonline.zammadmobile.premium.yearly"
    private var transactionListener: TransactionUpdateListener?

    init() {
        transactionListener = listenForTransactionUpdates()
        Task {
            isLoadingProducts = true
            await fetchProducts()
            await checkSubscriptionStatus()
            isLoadingProducts = false
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }

    func fetchProducts() async {
        do {
            let products = try await Product.products(for: [monthlyProductID, yearlyProductID])
            for product in products {
                if product.id == monthlyProductID { monthlyProduct = product }
                else if product.id == yearlyProductID { yearlyProduct = product }
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
    }

    func checkSubscriptionStatus() async {
        guard let product = monthlyProduct ?? yearlyProduct,
              let statuses = try? await product.subscription?.status else { return }
        
        var highestStatus: SubscriptionStatus?
        for status in statuses {
             highestStatus = status.state
        }
        
        if let status = highestStatus {
            subscriptionGroupStatus = status
            updateAdRemovalStatus(for: status)
        }
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
            await checkSubscriptionStatus()
            await transaction.finish()
        }
    }
    
    private func updateAdRemovalStatus(for status: SubscriptionStatus) {
        let areAdsRemoved = status == .subscribed || status == .inGracePeriod
        SettingsManager.shared.save(areAdsRemoved: areAdsRemoved)
    }
}
