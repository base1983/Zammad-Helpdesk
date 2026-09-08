import Foundation
import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform

/// Consent gate in front of the ad SDK, built on Google's User Messaging
/// Platform. Google's EU user consent policy requires a certified CMP before
/// ads are served to users in the EEA and the UK, so nothing is requested until
/// UMP says we may: we ask for the consent status, present the form when one is
/// required, and only then start the Mobile Ads SDK.
///
/// Outside the EEA no form appears and `canShowAds` flips to true immediately.
/// Premium users never get here — the banner is gone before consent matters.
@MainActor
final class AdConsentManager: ObservableObject {
    static let shared = AdConsentManager()

    /// True once the SDK is started and consent (where required) is settled.
    @Published private(set) var canShowAds = false

    /// Whether Google requires us to offer a way to change consent later. When
    /// this is true the entry point in Settings is not optional.
    @Published private(set) var isPrivacyOptionsRequired = false

    private var didStartMobileAds = false

    private init() {}

    /// Asks UMP for the current consent status, shows the form if needed, and
    /// starts the ad SDK afterwards. Safe to call more than once.
    func start() {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    // A failed lookup must not take the ads down with it: UMP
                    // keeps the last known consent, and canRequestAds still
                    // reflects it.
                    print("DEBUG: [Ads] Consent-info ophalen mislukt: \(error.localizedDescription)")
                    self.startMobileAdsIfAllowed()
                    return
                }
                await self.presentFormIfRequired()
                self.startMobileAdsIfAllowed()
            }
        }
    }

    /// Lets the user change their choice later, as Google's policy requires.
    func presentPrivacyOptions() {
        guard let controller = Self.topViewController() else { return }
        ConsentForm.presentPrivacyOptionsForm(from: controller) { [weak self] error in
            Task { @MainActor in
                if let error {
                    print("DEBUG: [Ads] Privacy-opties tonen mislukt: \(error.localizedDescription)")
                }
                self?.startMobileAdsIfAllowed()
            }
        }
    }

    private func presentFormIfRequired() async {
        guard let controller = Self.topViewController() else { return }
        await withCheckedContinuation { continuation in
            ConsentForm.loadAndPresentIfRequired(from: controller) { error in
                if let error {
                    print("DEBUG: [Ads] Consentformulier mislukt: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    private func startMobileAdsIfAllowed() {
        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds else {
            canShowAds = false
            return
        }
        if !didStartMobileAds {
            didStartMobileAds = true
            MobileAds.shared.start(completionHandler: { _ in })
        }
        canShowAds = true
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
