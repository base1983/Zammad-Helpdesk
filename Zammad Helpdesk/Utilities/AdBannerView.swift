import SwiftUI
import GoogleMobileAds
import UIKit

/// Adaptive AdMob banner. Reports whether an ad is actually on screen through
/// `isLoaded`, so the container can collapse to zero height instead of showing
/// an empty strip while Google has nothing to fill it with — which is the
/// normal state for a freshly created ad unit, and the permanent state when a
/// request fails.
struct AdBannerView: UIViewControllerRepresentable {
    let adUnitID: String
    let width: CGFloat
    @Binding var isLoaded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoaded: $isLoaded)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let bannerView = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = viewController
        bannerView.delegate = context.coordinator

        viewController.view.addSubview(bannerView)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
        ])

        bannerView.load(Request())
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var isLoaded: Bool

        init(isLoaded: Binding<Bool>) {
            _isLoaded = isLoaded
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("DEBUG: [Ads] Banner geladen (\(bannerView.adUnitID ?? "?"))")
            isLoaded = true
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // The SDK's error text says exactly why: "No ad to show" (no fill,
            // typical for a new unit or an app not yet live), "Request Error:
            // Invalid ad unit" (wrong id / not yet propagated), consent-related
            // refusals, or a network problem. The SDK retries on its own.
            print("DEBUG: [Ads] Banner niet geladen: \(error.localizedDescription)")
            isLoaded = false
        }
    }
}
