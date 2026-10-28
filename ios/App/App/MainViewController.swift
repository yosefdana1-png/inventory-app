import UIKit
import Capacitor

/// Root view controller. Registers the app's local (non-npm) Capacitor plugins.
/// Lives in the app target, so `npx cap sync ios` never overwrites it.
class MainViewController: CAPBridgeViewController, UIScrollViewDelegate {
    /// iOS's own "tap the status bar to scroll to top" does nothing here because
    /// the page never scrolls (each screen scrolls inside its own element), so
    /// status-bar taps are forwarded to the web app as a `statusTap` event.
    ///
    /// Two parts, because iOS delivers taps on the status bar itself (clock,
    /// icons, Dynamic Island) to the system, never to app views:
    /// - `statusBarTapView`: a clear strip over the top safe area; catches taps
    ///   in the part of the strip below the status bar.
    /// - `scrollToTopProxy`: the only `scrollsToTop` scroll view in the window,
    ///   so the system's status-bar tap lands in its delegate.
    private let statusBarTapView = UIView()
    private let scrollToTopProxy = UIScrollView()

    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(WatchLinkPlugin())
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        statusBarTapView.backgroundColor = .clear
        statusBarTapView.isUserInteractionEnabled = true
        statusBarTapView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(statusBarTapped))
        )

        scrollToTopProxy.backgroundColor = .clear
        scrollToTopProxy.scrollsToTop = true
        scrollToTopProxy.showsVerticalScrollIndicator = false
        scrollToTopProxy.showsHorizontalScrollIndicator = false
        scrollToTopProxy.delegate = self
        statusBarTapView.addSubview(scrollToTopProxy)

        // iOS only scrolls-to-top when exactly one scroll view opts in.
        bridge?.webView?.scrollView.scrollsToTop = false

        view.addSubview(statusBarTapView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutStatusBarTapView()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        layoutStatusBarTapView()
    }

    /// Only the top safe-area strip; 0 high (and so inert) when there is none, e.g. in landscape.
    private func layoutStatusBarTapView() {
        statusBarTapView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.safeAreaInsets.top)
        // Keep the proxy slightly "scrolled" so the system always offers it the tap.
        scrollToTopProxy.frame = statusBarTapView.bounds
        scrollToTopProxy.contentSize = CGSize(width: statusBarTapView.bounds.width, height: statusBarTapView.bounds.height + 2)
        scrollToTopProxy.contentOffset = CGPoint(x: 0, y: 1)
        view.bringSubviewToFront(statusBarTapView)
    }

    @objc private func statusBarTapped() {
        sendStatusTap()
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        guard scrollView === scrollToTopProxy else { return true }
        sendStatusTap()
        return false
    }

    private func sendStatusTap() {
        bridge?.webView?.evaluateJavaScript("window.dispatchEvent(new Event('statusTap'))")
    }
}
