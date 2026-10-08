import Foundation
import SwiftUI
import GoogleMobileAds

/// Shared cooldown for every full-screen ad format (app open, interstitial).
/// Two full-screen ads back to back is what AdMob's placement policy calls
/// out as disruptive, so each format consults this before presenting.
@MainActor
enum FullScreenAdThrottle {
    static let minimumInterval: TimeInterval = 120
    private(set) static var lastPresentedAt: Date?

    static var isCoolingDown: Bool {
        guard let lastPresentedAt else { return false }
        return Date().timeIntervalSince(lastPresentedAt) < minimumInterval
    }

    static func markPresented() {
        lastPresentedAt = Date()
    }
}

/// Google's "App open" format: a full-screen ad shown when the app is opened
/// or brought back to the foreground. AdMob forbids interstitials at launch,
/// which is why this is a separate format with its own ad unit.
///
/// Callers must not call `present` for Premium users or before
/// `AdConsentManager.canShowAds` is true — the same consent rule as the banner.
@MainActor
final class AppOpenAdManager: NSObject, ObservableObject {
    static let shared = AppOpenAdManager()

    #if DEBUG
    private static let adUnitID = "ca-app-pub-3940256099942544/5575463023"
    #else
    // TODO: create an "App open" ad unit in AdMob and paste its id here. An
    // unknown id never loads, so the app simply opens without an ad.
    private static let adUnitID = "ca-app-pub-7428603098298858/0000000000"
    #endif

    /// Google documents app open ads as valid for four hours after loading.
    private static let adLifetime: TimeInterval = 4 * 60 * 60

    /// A cold start counts as "opening the app" for this long after launch:
    /// if the ad lands within the window it is shown right away, after that
    /// we wait for the next foreground instead of interrupting the user.
    private static let coldStartWindow: TimeInterval = 15

    private let launchedAt = Date()
    private var loadedAd: AppOpenAd?
    private var loadedAt: Date?
    private var isLoading = false
    private var isPresenting = false
    private var pendingPresentationCheck: (() -> Bool)?

    private override init() {}

    private var hasFreshAd: Bool {
        guard loadedAd != nil, let loadedAt else { return false }
        return Date().timeIntervalSince(loadedAt) < Self.adLifetime
    }

    /// Fetches the next app open ad if none is loaded or in flight.
    func preload() {
        guard !hasFreshAd, !isLoading else { return }
        loadedAd = nil
        isLoading = true
        Task {
            do {
                let ad = try await AppOpenAd.load(with: Self.adUnitID, request: Request())
                ad.fullScreenContentDelegate = self
                loadedAd = ad
                loadedAt = Date()
                print("DEBUG: [Ads] App-open advertentie geladen")
            } catch {
                print("DEBUG: [Ads] App-open advertentie niet geladen: \(error.localizedDescription)")
            }
            isLoading = false
            // Cold start: the ad arrived while the user is still "opening"
            // the app, so show it now if the caller's conditions still hold.
            if let check = pendingPresentationCheck {
                pendingPresentationCheck = nil
                if Date().timeIntervalSince(launchedAt) < Self.coldStartWindow, check() {
                    presentIfReady(isAllowed: check)
                }
            }
        }
    }

    /// Shows the ad when one is ready, the cooldown has passed and `isAllowed`
    /// (the caller's own guard: unlocked, setup complete, …) holds. On a cold
    /// start without a loaded ad the request is kept and honoured as soon as
    /// the load finishes, provided that happens within `coldStartWindow`.
    func presentIfReady(isAllowed: @escaping () -> Bool) {
        guard !isPresenting, !FullScreenAdThrottle.isCoolingDown, isAllowed() else { return }
        guard hasFreshAd, let ad = loadedAd else {
            if Date().timeIntervalSince(launchedAt) < Self.coldStartWindow {
                pendingPresentationCheck = isAllowed
            }
            preload()
            return
        }
        guard let controller = AdConsentManager.topViewController() else { return }
        loadedAd = nil
        isPresenting = true
        FullScreenAdThrottle.markPresented()
        ad.present(from: controller)
    }

    private func finish() {
        isPresenting = false
        preload()
    }
}

extension AppOpenAdManager: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("DEBUG: [Ads] App-open advertentie tonen mislukt: \(error.localizedDescription)")
        Task { @MainActor in self.finish() }
    }
}
