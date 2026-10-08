import Foundation
import SwiftUI
import GoogleMobileAds

/// Full-screen interstitial shown at natural transition points (currently:
/// opening Settings). The SDK renders the countdown and the close button
/// itself; our job is to keep one ad preloaded, present it when asked, and
/// hand control back to the caller as soon as the user has dismissed it.
///
/// Callers must not call `present` for Premium users or before
/// `AdConsentManager.canShowAds` is true — the same consent rule as the banner.
@MainActor
final class InterstitialAdManager: NSObject, ObservableObject {
    static let shared = InterstitialAdManager()

    // Debug builds use Google's test interstitial, Release the live unit — the
    // same split as the banner in TicketListView, for the same policy reason.
    #if DEBUG
    private static let adUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    // AdMob unit "SettingsPage" (interstitial). A freshly created unit returns
    // "No ad to show" for up to an hour or so until it has propagated.
    private static let adUnitID = "ca-app-pub-7428603098298858/4942575103"
    #endif

    private var loadedAd: InterstitialAd?
    private var isLoading = false
    private var onDismiss: (() -> Void)?

    private override init() {}

    /// True when an ad is ready and no full-screen ad (of any format) was
    /// shown within the shared cooldown. Showing one on every single tap is
    /// both annoying and against AdMob's placement guidance.
    var canPresent: Bool {
        loadedAd != nil && !FullScreenAdThrottle.isCoolingDown
    }

    /// Fetches the next interstitial if none is loaded or in flight.
    func preload() {
        guard loadedAd == nil, !isLoading else { return }
        isLoading = true
        Task {
            do {
                let ad = try await InterstitialAd.load(with: Self.adUnitID, request: Request())
                ad.fullScreenContentDelegate = self
                loadedAd = ad
                print("DEBUG: [Ads] Interstitial geladen")
            } catch {
                // Same vocabulary as the banner: "No ad to show" for no fill,
                // "Invalid ad unit" for a wrong or not yet propagated id.
                print("DEBUG: [Ads] Interstitial niet geladen: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    /// Presents the preloaded interstitial and calls `completion` once it is
    /// gone. When nothing is ready (no fill, still loading, cooldown, no view
    /// controller to present from) `completion` runs immediately, so the
    /// caller never waits on an ad that is not coming.
    func present(completion: @escaping () -> Void) {
        guard canPresent, let ad = loadedAd,
              let controller = AdConsentManager.topViewController() else {
            preload()
            completion()
            return
        }
        loadedAd = nil
        onDismiss = completion
        FullScreenAdThrottle.markPresented()
        ad.present(from: controller)
    }

    private func finish() {
        let callback = onDismiss
        onDismiss = nil
        // Start fetching the next one right away so it is ready for the next
        // visit instead of being requested when the user is already waiting.
        preload()
        callback?()
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("DEBUG: [Ads] Interstitial tonen mislukt: \(error.localizedDescription)")
        Task { @MainActor in self.finish() }
    }
}
