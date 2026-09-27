import AppKit
import SwiftUI
import WebKit

/// Marfa's types as Marfa's own browser for them shows them: one self-contained page, with its own navigation and
/// search, that fetches nothing. Each window makes its page the first time Marfa Types is shown and keeps it, so
/// the page is where it was left when the window comes back to it.
final class MarfaTypesPage: NSObject, WKNavigationDelegate {
    private(set) lazy var webView = makeWebView()
    private let pageURL: URL = {
        guard let url = Bundle.main.url(forResource: "marfa-types", withExtension: "html") else {
            preconditionFailure("marfa-types.html missing from the bundle")
        }
        return url
    }()

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The page keeps only which of its groups are closed, and only for as long as the window is open.
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setAccessibilityIdentifier("MarfaTypes")
        // Hidden until drawn, so a dark window does not flash white while the page loads.
        webView.isHidden = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL)
        return webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.isHidden = false
    }

    /// The page moves between its own sections by fragment. A web link opens in the browser, since this page
    /// never leaves itself, and anything else is refused.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if url.isFileURL, url.path == pageURL.path { return .allow }
        if action.navigationType == .linkActivated, url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }
}

/// The page across the list and the note, beside the sidebar.
struct MarfaTypesView: NSViewRepresentable {
    let page: MarfaTypesPage

    func makeNSView(context: Context) -> WKWebView {
        page.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    // WebKit lays out badly at fractional sizes, so the proposal is rounded down to whole points.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width.rounded(.down), height: height.rounded(.down))
    }
}
