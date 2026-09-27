import AppKit
import Observation
import SwiftUI
import WebKit

/// Marfa's types as Marfa's own browser for them shows them: one self-contained page, with its own navigation,
/// that fetches nothing. The window's toolbar gives it its title and its search, so the page's own heading and
/// search box are hidden and the toolbar's field drives the page's search. That is done here, as the page loads,
/// so the page stays as generated and is refreshed by replacing it whole. Each window makes its page the first
/// time Marfa Types is shown and keeps it, so the page is where it was left when the window comes back to it.
///
/// The page stops below the toolbar, since WebKit draws a hard edge under the toolbar whenever a page reaches
/// beneath it. Its list of types is given the page's own background and no divider, so the page reads as one
/// surface under the toolbar rather than a column that stops short of it.
@Observable
final class MarfaTypesPage: NSObject, WKNavigationDelegate {
    @ObservationIgnored private(set) lazy var webView = makeWebView()
    /// The page asks for the toolbar's search, when / is typed as it would have focused its own.
    @ObservationIgnored var onFind: () -> Void = {}
    /// Whether Back and Forward have somewhere to go among the types the page has shown.
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var historyObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private let pageURL: URL = {
        guard let url = Bundle.main.url(forResource: "marfa-types", withExtension: "html") else {
            preconditionFailure("marfa-types.html missing from the bundle")
        }
        return url
    }()

    /// Hides the page's heading and search box, which the toolbar stands in for; gives its list of types the
    /// page's background and no divider; and passes / and ⌘K to the app: / to the toolbar's search, and ⌘K to the
    /// menu bar's command palette, which the page would otherwise take.
    private static let adaptation = """
        const style = document.createElement('style');
        style.textContent = `
          .side-head { display: none; }
          .sidebar { background: var(--bg); border-right: 0; }
          .nav { padding-top: 14px; }
        `;
        document.head.append(style);
        window.addEventListener('keydown', (event) => {
          const typing = /^(INPUT|TEXTAREA)$/.test(document.activeElement?.tagName ?? '');
          if (event.key === '/' && !typing) {
            event.preventDefault();
            event.stopImmediatePropagation();
            webkit.messageHandlers.find.postMessage(null);
          } else if (event.key === 'k' && (event.metaKey || event.ctrlKey)) {
            event.stopImmediatePropagation();
          }
        }, true);
        """

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The page keeps only which of its groups are closed, and only for as long as the window is open.
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.adaptation, injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        // The content controller retains its handlers, so a proxy keeps the cycle out.
        configuration.userContentController.add(FindProxy(page: self), name: "find")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setAccessibilityIdentifier("MarfaTypes")
        // Hidden until drawn, so a dark window does not flash white while the page loads.
        webView.isHidden = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        historyObservations = [
            webView.observe(\.canGoBack) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
            },
        ]
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL)
        return webView
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }


    /// Searches the page as its own search box would, types, fields and guides alike.
    func search(_ text: String) {
        query = text
        guard isLoaded else { return }
        // In a block of its own, since each evaluation shares the page's global scope.
        webView.evaluateJavaScript("""
            {
              const search = document.getElementById('search');
              search.value = \(Self.json(text));
              search.dispatchEvent(new Event('input'));
            }
            """)
    }

    /// Opens the first match, as Return in the page's own search box does.
    func openFirstMatch() {
        webView.evaluateJavaScript("""
            document.getElementById('search').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
            """)
    }

    private static func json(_ text: String) -> String {
        (try? String(decoding: JSONEncoder().encode(text), as: UTF8.self)) ?? "\"\""
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isLoaded else { return }
        isLoaded = true
        webView.isHidden = false
        if !query.isEmpty { search(query) }
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

private final class FindProxy: NSObject, WKScriptMessageHandler {
    weak var page: MarfaTypesPage?

    init(page: MarfaTypesPage) {
        self.page = page
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        page?.onFind()
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
