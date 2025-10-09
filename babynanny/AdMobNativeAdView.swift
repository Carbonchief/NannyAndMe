import SwiftUI
import UIKit
import GoogleMobileAds

@MainActor
struct AdMobNativeAdView: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator(adUnitID: adUnitID)
    }

    func makeUIView(context: Context) -> NativeAdContainerView {
        let container = NativeAdContainerView()
        context.coordinator.container = container
        context.coordinator.loadAdIfNeeded()
        return container
    }

    func updateUIView(_ uiView: NativeAdContainerView, context: Context) {
        context.coordinator.adUnitID = adUnitID
        context.coordinator.loadAdIfNeeded()
    }
}

extension AdMobNativeAdView {
    @MainActor
    final class Coordinator: NSObject, GADNativeAdLoaderDelegate, GADNativeAdDelegate {
        var adUnitID: String
        weak var container: NativeAdContainerView?

        private var hasRequestedAd = false
        private var adLoader: GADAdLoader?

        init(adUnitID: String) {
            self.adUnitID = adUnitID
        }

        func loadAdIfNeeded() {
            guard !hasRequestedAd, let container else { return }

            guard let rootViewController = UIApplication.topMostViewController() else {
                hasRequestedAd = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.hasRequestedAd = false
                    self?.loadAdIfNeeded()
                }
                return
            }

            hasRequestedAd = true
            container.showLoading()

            let adViewOptions = GADNativeAdViewAdOptions()
            adViewOptions.preferredAdChoicesPosition = .topRightCorner

            let loader = GADAdLoader(
                adUnitID: adUnitID,
                rootViewController: rootViewController,
                adTypes: [.native],
                options: [adViewOptions]
            )
            loader.delegate = self
            loader.load(GADRequest())
            adLoader = loader
        }

        func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
            nativeAd.delegate = self
            container?.apply(nativeAd: nativeAd)
        }

        func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
            hasRequestedAd = false
            container?.showFailure()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.loadAdIfNeeded()
            }
        }

        func nativeAdDidRecordImpression(_ nativeAd: GADNativeAd) { }

        func nativeAdDidRecordClick(_ nativeAd: GADNativeAd) { }

        func nativeAdDidRecordSwipeGesture(_ nativeAd: GADNativeAd) { }

        func nativeAdWillPresentScreen(_ nativeAd: GADNativeAd) { }

        func nativeAdWillDismissScreen(_ nativeAd: GADNativeAd) { }

        func nativeAdDidDismissScreen(_ nativeAd: GADNativeAd) { }

        func nativeAdIsMuted(_ nativeAd: GADNativeAd) { }
    }
}

// MARK: - NativeAdContainerView

@MainActor
final class NativeAdContainerView: UIView {
    private let nativeAdView = GADNativeAdView()
    private let iconImageView = UIImageView()
    private let headlineLabel = UILabel()
    private let advertiserLabel = UILabel()
    private let callToActionButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViewHierarchy()
    }

    func showLoading() {
        isHidden = false
        activityIndicator.startAnimating()
        activityIndicator.isHidden = false
        iconImageView.isHidden = true
        headlineLabel.text = nil
        advertiserLabel.text = nil
        callToActionButton.isHidden = true
    }

    func apply(nativeAd: GADNativeAd) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        isHidden = false

        nativeAdView.nativeAd = nativeAd

        headlineLabel.text = nativeAd.headline
        headlineLabel.isHidden = nativeAd.headline == nil

        advertiserLabel.text = nativeAd.advertiser
        advertiserLabel.isHidden = nativeAd.advertiser == nil

        if let icon = nativeAd.icon?.image {
            iconImageView.image = icon
            iconImageView.isHidden = false
        } else {
            iconImageView.image = nil
            iconImageView.isHidden = true
        }

        if let callToAction = nativeAd.callToAction {
            callToActionButton.setTitle(callToAction, for: .normal)
            callToActionButton.isHidden = false
        } else {
            callToActionButton.setTitle(nil, for: .normal)
            callToActionButton.isHidden = true
        }

        nativeAdView.callToActionView?.isUserInteractionEnabled = false
        setNeedsLayout()
        layoutIfNeeded()
    }

    func showFailure() {
        activityIndicator.stopAnimating()
        isHidden = true
    }
}

private extension NativeAdContainerView {
    func configureViewHierarchy() {
        backgroundColor = UIColor.secondarySystemBackground
        layer.cornerRadius = 12
        clipsToBounds = true

        nativeAdView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nativeAdView)

        NSLayoutConstraint.activate([
            nativeAdView.leadingAnchor.constraint(equalTo: leadingAnchor),
            nativeAdView.trailingAnchor.constraint(equalTo: trailingAnchor),
            nativeAdView.topAnchor.constraint(equalTo: topAnchor),
            nativeAdView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 10),
            contentView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -10),
            contentView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 8),
            contentView.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -8)
        ])

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 6
        iconImageView.tintColor = UIColor.secondaryLabel
        iconImageView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 32).isActive = true

        headlineLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.numberOfLines = 2

        advertiserLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        advertiserLabel.adjustsFontForContentSizeCategory = true
        advertiserLabel.textColor = .secondaryLabel

        callToActionButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        callToActionButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        callToActionButton.layer.cornerRadius = 8
        callToActionButton.backgroundColor = UIColor.systemBlue
        callToActionButton.setTitleColor(.white, for: .normal)
        callToActionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        callToActionButton.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [headlineLabel, advertiserLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let horizontalStack = UIStackView(arrangedSubviews: [iconImageView, textStack, callToActionButton])
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        horizontalStack.axis = .horizontal
        horizontalStack.alignment = .center
        horizontalStack.spacing = 8
        horizontalStack.setCustomSpacing(6, after: textStack)

        contentView.addSubview(horizontalStack)

        NSLayoutConstraint.activate([
            horizontalStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            horizontalStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            horizontalStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            horizontalStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: nativeAdView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: nativeAdView.centerYAnchor)
        ])

        nativeAdView.headlineView = headlineLabel
        nativeAdView.iconView = iconImageView
        nativeAdView.advertiserView = advertiserLabel
        nativeAdView.callToActionView = callToActionButton

        showLoading()
    }
}

private extension UIApplication {
    static func topMostViewController(base: UIViewController? = UIApplication.shared.firstKeyWindow?.rootViewController) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return topMostViewController(base: navigationController.visibleViewController)
        }

        if let tabController = base as? UITabBarController {
            return topMostViewController(base: tabController.selectedViewController)
        }

        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }

        return base
    }

    var firstWindowScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    var firstKeyWindow: UIWindow? {
        firstWindowScene?.windows.first { $0.isKeyWindow }
    }
}
