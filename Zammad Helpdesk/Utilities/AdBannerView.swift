import SwiftUI
import GoogleMobileAds

struct AdBannerView: UIViewControllerRepresentable {
    let adUnitID: String

    func makeUIViewController(context: Context) -> UIViewController {
        let bannerView = BannerView(adSize: AdSizeBanner)
        let viewController = UIViewController()
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = viewController
        viewController.view.addSubview(bannerView)
        viewController.view.frame = CGRect(origin: .zero, size: AdSizeBanner.size)
        bannerView.load(Request())
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
