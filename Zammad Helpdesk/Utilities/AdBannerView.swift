import SwiftUI
import GoogleMobileAds
import UIKit

struct AdBannerView: UIViewControllerRepresentable {
    let adUnitID: String
    let width: CGFloat

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        
        // Determine adaptive banner size with backward compatibility.
        let adSize: AdSize
        if #available(iOS 11.0, *) {
            // Prefer the legacy C-style helper if the modern API isn't available in this SDK
            adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        } else {
            adSize = AdSizeBanner
        }
        
        let bannerView = BannerView(adSize: adSize)
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = viewController
        
        viewController.view.addSubview(bannerView)
        
        // Add constraints to center the banner.
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
        ])
        
        bannerView.load(Request())
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
