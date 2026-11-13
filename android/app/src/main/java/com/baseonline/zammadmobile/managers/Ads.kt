package com.baseonline.zammadmobile.managers

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.baseonline.zammadmobile.BuildConfig
import com.baseonline.zammadmobile.data.SettingsManager
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.appopen.AppOpenAd
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform

/**
 * Gates the Google Mobile Ads SDK behind UMP consent (required in the EEA).
 * Nothing ad-related is initialised or requested until [canShowAds] is true.
 */
object AdConsentManager {
    private const val TAG = "Ads"
    var canShowAds by mutableStateOf(false); private set
    var isPrivacyOptionsRequired by mutableStateOf(false); private set
    private var didStartMobileAds = false
    private var started = false

    fun start(activity: Activity) {
        if (started) return
        started = true
        val info = UserMessagingPlatform.getConsentInformation(activity)
        val params = ConsentRequestParameters.Builder().setTagForUnderAgeOfConsent(false).build()
        info.requestConsentInfoUpdate(activity, params, {
            UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { error ->
                if (error != null) Log.i(TAG, "Consent form: ${error.message}")
                startMobileAdsIfAllowed(activity, info)
            }
        }, { error ->
            Log.i(TAG, "Consent info update failed: ${error.message}")
            // A previous session's consent may still allow ads.
            startMobileAdsIfAllowed(activity, info)
        })
    }

    fun presentPrivacyOptions(activity: Activity) {
        UserMessagingPlatform.showPrivacyOptionsForm(activity) {
            startMobileAdsIfAllowed(activity, UserMessagingPlatform.getConsentInformation(activity))
        }
    }

    private fun startMobileAdsIfAllowed(context: Context, info: ConsentInformation) {
        isPrivacyOptionsRequired =
            info.privacyOptionsRequirementStatus == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
        if (!info.canRequestAds()) { canShowAds = false; return }
        if (!didStartMobileAds) {
            didStartMobileAds = true
            MobileAds.initialize(context.applicationContext) { }
        }
        canShowAds = true
    }
}

/** Whether this user sees ads at all: not Premium, and consent allows it. */
val showsAds: Boolean get() = !SettingsManager.isPremium && AdConsentManager.canShowAds

/**
 * Adaptive banner. Mounted but zero-height until an ad has actually loaded, so
 * a failed or slow request never leaves an empty strip in the layout.
 */
@Composable
fun AdBanner(modifier: Modifier = Modifier) {
    if (!showsAds) return
    val context = LocalContext.current
    val widthDp = LocalConfiguration.current.screenWidthDp
    var loaded by remember { mutableStateOf(false) }
    val adView = remember(widthDp) {
        AdView(context).apply {
            adUnitId = BuildConfig.AD_BANNER
            setAdSize(AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(context, widthDp))
            adListener = object : AdListener() {
                override fun onAdLoaded() { loaded = true }
                override fun onAdFailedToLoad(error: LoadAdError) { loaded = false }
            }
            loadAd(AdRequest.Builder().build())
        }
    }
    DisposableEffect(adView) { onDispose { adView.destroy() } }
    AndroidView(
        factory = { adView },
        modifier = modifier.fillMaxWidth().then(if (loaded) Modifier else Modifier.height(0.dp)),
    )
}

/** One full-screen ad per two minutes at most, shared by interstitial and app-open. */
object FullScreenAdThrottle {
    private const val MIN_INTERVAL_MS = 120_000L
    private var lastPresentedAt = 0L
    val isCoolingDown: Boolean get() = lastPresentedAt != 0L && System.currentTimeMillis() - lastPresentedAt < MIN_INTERVAL_MS
    fun markPresented() { lastPresentedAt = System.currentTimeMillis() }
}

object InterstitialAdManager {
    private var loadedAd: InterstitialAd? = null
    private var isLoading = false

    val canPresent: Boolean get() = loadedAd != null && !FullScreenAdThrottle.isCoolingDown

    fun preload(context: Context) {
        if (!showsAds || loadedAd != null || isLoading) return
        isLoading = true
        InterstitialAd.load(context.applicationContext, BuildConfig.AD_INTERSTITIAL, AdRequest.Builder().build(),
            object : InterstitialAdLoadCallback() {
                override fun onAdLoaded(ad: InterstitialAd) { loadedAd = ad; isLoading = false }
                override fun onAdFailedToLoad(error: LoadAdError) { isLoading = false }
            })
    }

    /** Shows the interstitial when one is ready, then (or immediately) runs [completion]. */
    fun present(activity: Activity, completion: () -> Unit) {
        val ad = loadedAd
        if (!showsAds || ad == null || FullScreenAdThrottle.isCoolingDown) {
            preload(activity)
            completion()
            return
        }
        loadedAd = null
        FullScreenAdThrottle.markPresented()
        ad.fullScreenContentCallback = object : FullScreenContentCallback() {
            override fun onAdDismissedFullScreenContent() { preload(activity); completion() }
            override fun onAdFailedToShowFullScreenContent(error: AdError) { preload(activity); completion() }
        }
        ad.show(activity)
    }
}

object AppOpenAdManager {
    private const val AD_LIFETIME_MS = 4 * 60 * 60 * 1000L
    private var loadedAd: AppOpenAd? = null
    private var loadedAt = 0L
    private var isLoading = false
    private var isPresenting = false

    private val hasFreshAd: Boolean get() = loadedAd != null && System.currentTimeMillis() - loadedAt < AD_LIFETIME_MS

    fun preload(context: Context) {
        if (!showsAds || hasFreshAd || isLoading) return
        loadedAd = null
        isLoading = true
        AppOpenAd.load(context.applicationContext, BuildConfig.AD_APP_OPEN, AdRequest.Builder().build(),
            object : AppOpenAd.AppOpenAdLoadCallback() {
                override fun onAdLoaded(ad: AppOpenAd) { loadedAd = ad; loadedAt = System.currentTimeMillis(); isLoading = false }
                override fun onAdFailedToLoad(error: LoadAdError) { isLoading = false }
            })
    }

    /** Shown when the app returns to the foreground, if [isAllowed] still holds. */
    fun presentIfReady(activity: Activity, isAllowed: () -> Boolean) {
        if (isPresenting || FullScreenAdThrottle.isCoolingDown || !showsAds || !isAllowed()) return
        val ad = loadedAd
        if (!hasFreshAd || ad == null) { preload(activity); return }
        loadedAd = null
        isPresenting = true
        FullScreenAdThrottle.markPresented()
        ad.fullScreenContentCallback = object : FullScreenContentCallback() {
            override fun onAdDismissedFullScreenContent() { isPresenting = false; preload(activity) }
            override fun onAdFailedToShowFullScreenContent(error: AdError) { isPresenting = false; preload(activity) }
        }
        ad.show(activity)
    }
}
