package com.baseonline.zammadmobile.managers

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClient.BillingResponseCode
import com.android.billingclient.api.BillingClient.ProductType
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.SettingsManager
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Premium via Google Play Billing, the counterpart of the iOS `StoreManager`.
 * Premium is derived from a lifetime purchase or an active subscription and
 * from nothing else: there is no debug shortcut, so a tester sees the paywall
 * exactly as a customer does. Product ids match the App Store ones; create
 * them in Play Console (lifetime as a one-time product, month/yearly as
 * subscriptions).
 */
object StoreManager : PurchasesUpdatedListener {
    private const val TAG = "StoreManager"
    const val MONTHLY_ID = "com.baseonline.zammadmobile.premium.month"
    const val YEARLY_ID = "com.baseonline.zammadmobile.premium.yearly"
    const val LIFETIME_ID = "com.baseonline.zammadmobile.premium.lifetime"

    var monthlyProduct by mutableStateOf<ProductDetails?>(null); private set
    var yearlyProduct by mutableStateOf<ProductDetails?>(null); private set
    var lifetimeProduct by mutableStateOf<ProductDetails?>(null); private set
    var isTransactionInProgress by mutableStateOf(false); private set
    var isLoadingProducts by mutableStateOf(false); private set
    /** A user-facing status line (products unavailable, purchase pending/failed). */
    var storeMessage by mutableStateOf<String?>(null); private set
    /** Which subscription is active, if any (for the "current plan" marker). */
    var activeSubscriptionId by mutableStateOf<String?>(null); private set
    var hasLifetime by mutableStateOf(false); private set

    val hasProducts: Boolean get() = monthlyProduct != null || yearlyProduct != null || lifetimeProduct != null

    private lateinit var appContext: Context
    private lateinit var client: BillingClient
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val connectMutex = Mutex()
    private var activeSubscriptionToken: String? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        client = BillingClient.newBuilder(appContext)
            .setListener(this)
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
        scope.launch { reload() }
    }

    private suspend fun connect(): Boolean = connectMutex.withLock {
        if (client.isReady) return true
        val result = CompletableDeferred<Boolean>()
        try {
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(billingResult: BillingResult) {
                    result.complete(billingResult.responseCode == BillingResponseCode.OK)
                }
                override fun onBillingServiceDisconnected() { result.complete(false) }
            })
        } catch (e: Exception) {
            Log.w(TAG, "Billing connection failed: ${e.message}")
            return false
        }
        return result.await()
    }

    /** Price as Play formats it for the user's country, e.g. "€ 2,99". */
    fun price(product: ProductDetails?): String? {
        product ?: return null
        product.oneTimePurchaseOfferDetails?.let { return it.formattedPrice }
        return product.subscriptionOfferDetails?.firstOrNull()
            ?.pricingPhases?.pricingPhaseList?.lastOrNull()?.formattedPrice
    }

    suspend fun reload() {
        isLoadingProducts = true
        storeMessage = null
        fetchProducts()
        checkEntitlements()
        isLoadingProducts = false
    }

    private fun productList(type: String, vararg ids: String) = QueryProductDetailsParams.newBuilder()
        .setProductList(ids.map {
            QueryProductDetailsParams.Product.newBuilder().setProductId(it).setProductType(type).build()
        }).build()

    private suspend fun fetchProducts() {
        if (!connect()) {
            storeMessage = appContext.getString(R.string.products_unavailable)
            return
        }
        try {
            val subs = client.queryProductDetails(productList(ProductType.SUBS, MONTHLY_ID, YEARLY_ID))
            val inapp = client.queryProductDetails(productList(ProductType.INAPP, LIFETIME_ID))
            val all = subs.productDetailsList.orEmpty() + inapp.productDetailsList.orEmpty()
            monthlyProduct = all.firstOrNull { it.productId == MONTHLY_ID }
            yearlyProduct = all.firstOrNull { it.productId == YEARLY_ID }
            lifetimeProduct = all.firstOrNull { it.productId == LIFETIME_ID }
            storeMessage = if (all.isEmpty()) appContext.getString(R.string.products_unavailable) else null
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch products: ${e.message}")
            storeMessage = appContext.getString(R.string.products_load_failed) + " " + (e.localizedMessage ?: "")
        }
    }

    /**
     * Recomputes Premium from what Play says the account owns, and acknowledges
     * new purchases (Play refunds a purchase that is not acknowledged in 3 days).
     * When Play cannot be reached the stored entitlement is left untouched, so
     * a customer does not lose Premium for being offline.
     */
    suspend fun checkEntitlements() {
        if (!connect()) return
        try {
            val inapp = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(ProductType.INAPP).build())
            val subs = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(ProductType.SUBS).build())
            if (inapp.billingResult.responseCode != BillingResponseCode.OK ||
                subs.billingResult.responseCode != BillingResponseCode.OK) return

            val owned = (inapp.purchasesList + subs.purchasesList)
                .filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
            owned.filter { !it.isAcknowledged }.forEach { purchase ->
                client.acknowledgePurchase(
                    AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build())
            }
            hasLifetime = owned.any { LIFETIME_ID in it.products }
            val subscription = owned.firstOrNull { MONTHLY_ID in it.products || YEARLY_ID in it.products }
            activeSubscriptionId = subscription?.products?.firstOrNull()
            activeSubscriptionToken = subscription?.purchaseToken
            val premium = hasLifetime || subscription != null
            val wasPremium = SettingsManager.isPremium
            SettingsManager.savePremium(premium)
            if (wasPremium && !premium) PushManager.onPremiumLost()

            val pending = (inapp.purchasesList + subs.purchasesList).any { it.purchaseState == Purchase.PurchaseState.PENDING }
            if (pending && !premium) storeMessage = appContext.getString(R.string.purchase_pending)
        } catch (e: Exception) {
            Log.w(TAG, "Entitlement check failed: ${e.message}")
        }
    }

    fun purchase(activity: Activity, product: ProductDetails) {
        scope.launch {
            if (!connect()) {
                storeMessage = appContext.getString(R.string.products_unavailable)
                return@launch
            }
            isTransactionInProgress = true
            storeMessage = null
            val details = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product)
            product.subscriptionOfferDetails?.firstOrNull()?.let { details.setOfferToken(it.offerToken) }
            val flow = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(details.build()))
            // Switching between monthly and yearly replaces the running subscription
            // instead of starting a second one next to it.
            val oldToken = activeSubscriptionToken
            if (product.productType == ProductType.SUBS && oldToken != null && product.productId != activeSubscriptionId) {
                flow.setSubscriptionUpdateParams(
                    BillingFlowParams.SubscriptionUpdateParams.newBuilder().setOldPurchaseToken(oldToken).build())
            }
            val result = client.launchBillingFlow(activity, flow.build())
            if (result.responseCode != BillingResponseCode.OK) {
                isTransactionInProgress = false
                if (result.responseCode != BillingResponseCode.USER_CANCELED) {
                    storeMessage = appContext.getString(R.string.purchase_failed) + " " + result.debugMessage
                }
            }
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        scope.launch {
            when (result.responseCode) {
                BillingResponseCode.OK, BillingResponseCode.ITEM_ALREADY_OWNED -> checkEntitlements()
                BillingResponseCode.USER_CANCELED -> Unit
                else -> storeMessage = appContext.getString(R.string.purchase_failed) + " " + result.debugMessage
            }
            isTransactionInProgress = false
        }
    }

    /** Play has no separate "restore": re-reading owned purchases is the restore. */
    suspend fun restorePurchases() {
        storeMessage = null
        checkEntitlements()
    }
}
