import AppKit
import Observation
import SwiftUI
import WebKit

/// Marfa's types as Marfa's own browser for them shows them: one self-contained page, with its own navigation,
/// that fetches nothing. The window shows it in its usual three columns: the page's list of types where the note
/// list goes, and the chosen type where the note goes. They are the same page loaded twice, one showing only its
/// list and the other only its content, kept on the same type by the fragment each moves to. So the window never
/// changes its columns, which it could not do reliably: AppKit crashed laying out the toolbar as the columns
/// changed with the sidebar hidden or resized.
///
/// The window's toolbar gives the page its title and search, so the page's heading and search box are hidden and
/// the toolbar's field drives the page's search. All of that is done here, as the page loads, so the page stays as
/// generated and is refreshed by replacing it whole. Each window makes its pages the first time Marfa Types is
/// shown and keeps them, so they are where they were left when the window comes back.
@Observable
final class MarfaTypesPage: NSObject, WKNavigationDelegate {
    /// The page's list of types, for the list's column.
    @ObservationIgnored private(set) lazy var list = makePart(.list)
    /// The chosen type, for the note's column.
    @ObservationIgnored private(set) lazy var content = makePart(.content)
    /// The page asks for the toolbar's search, when / is typed as it would have focused its own.
    @ObservationIgnored var onFind: () -> Void = {}
    /// Whether Back and Forward have somewhere to go among the types shown.
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    @ObservationIgnored private var loaded: Set<ObjectIdentifier> = []
    @ObservationIgnored private var query = ""
    /// The type both parts show, for a part that finishes loading after the other has moved.
    @ObservationIgnored private var fragment = ""
    @ObservationIgnored private var historyObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private let pageURL: URL = {
        guard let url = Bundle.main.url(forResource: "marfa-types", withExtension: "html") else {
            preconditionFailure("marfa-types.html missing from the bundle")
        }
        return url
    }()

    enum Part {
        case list, content

        /// What of the page this part hides, on top of the heading and search box the toolbar stands in for.
        var style: String {
            switch self {
            case .list:
                """
                .main { display: none; }
                .sidebar { position: static; width: auto; height: 100vh; background: var(--bg); border: 0; }
                /* The column is as narrow as the page's phone layout, which would cap the list's height. */
                .nav { max-height: none; }
                html.window-background .sidebar { background: transparent; }
                """
            case .content:
                """
                .sidebar { display: none; }
                .main { margin-left: 0; }
                """
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .list: "MarfaTypesList"
            case .content: "MarfaTypes"
            }
        }
    }

    /// Hides what the window stands in for; tells the app each type the page moves to, so the other part follows;
    /// and passes / and ⌘K to the app: / to the toolbar's search, and ⌘K to the menu bar's command palette, which
    /// the page would otherwise take.
    private static func adaptation(_ part: Part) -> String {
        """
        const style = document.createElement('style');
        style.textContent = `
          .side-head { display: none; }
          .nav { padding-top: 14px; }
          html.window-background, html.window-background body { background: transparent; }
          \(part.style)
        `;
        document.head.append(style);
        window.addEventListener('hashchange', () => webkit.messageHandlers.types.postMessage({ moved: location.hash }));
        window.addEventListener('keydown', (event) => {
          const typing = /^(INPUT|TEXTAREA)$/.test(document.activeElement?.tagName ?? '');
          if (event.key === '/' && !typing) {
            event.preventDefault();
            event.stopImmediatePropagation();
            webkit.messageHandlers.types.postMessage({ find: true });
          } else if (event.key === 'k' && (event.metaKey || event.ctrlKey)) {
            event.stopImmediatePropagation();
          }
        }, true);
        """
    }

    private func makePart(_ part: Part) -> WebViewContainer {
        let configuration = WKWebViewConfiguration()
        // The page keeps only which of its groups are closed, and only for as long as the window is open.
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.adaptation(part), injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        // The content controller retains its handlers, so a proxy keeps the cycle out.
        configuration.userContentController.add(MessageProxy(page: self), name: "types")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.showsWindowBackground()
        webView.setAccessibilityIdentifier(part.accessibilityIdentifier)
        // Hidden until drawn, so a dark window does not flash white while the page loads.
        webView.isHidden = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        if part == .content {
            webView.allowsBackForwardNavigationGestures = true
            historyObservations = [
                webView.observe(\.canGoBack) { [weak self] webView, _ in
                    MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
                },
                webView.observe(\.canGoForward) { [weak self] webView, _ in
                    MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
                },
            ]
        }
        let container = WebViewContainer(webView: webView)
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL)
        return container
    }

    private var webViews: [WKWebView] { [list.webView, content.webView] }

    // History is the content's, since that is where the types are read; the list follows it.
    func goBack() { content.webView.goBack() }
    func goForward() { content.webView.goForward() }

    /// Searches the page as its own search box would, types, fields and guides alike: the list narrows to the
    /// matches and the content lists them.
    func search(_ text: String) {
        query = text
        for webView in webViews where loaded.contains(ObjectIdentifier(webView)) {
            search(text, in: webView)
        }
    }

    private func search(_ text: String, in webView: WKWebView) {
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
        content.webView.evaluateJavaScript("""
            document.getElementById('search').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
            """)
    }

    fileprivate func receive(_ body: Any, from webView: WKWebView?) {
        guard let message = body as? [String: Any] else { return }
        if message["find"] != nil { return onFind() }
        guard let fragment = message["moved"] as? String, let webView else { return }
        self.fragment = fragment
        // The other part moves to the same type; its own report of the move then finds this one already there.
        for other in webViews where other !== webView && loaded.contains(ObjectIdentifier(other)) {
            move(other, to: fragment)
        }
    }

    private func move(_ webView: WKWebView, to fragment: String) {
        webView.evaluateJavaScript("if (location.hash !== \(Self.json(fragment))) location.hash = \(Self.json(fragment))")
    }

    private static func json(_ text: String) -> String {
        (try? String(decoding: JSONEncoder().encode(text), as: UTF8.self)) ?? "\"\""
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard loaded.insert(ObjectIdentifier(webView)).inserted else { return }
        webView.isHidden = false
        if !query.isEmpty { search(query, in: webView) }
        if !fragment.isEmpty { move(webView, to: fragment) }
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

private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var page: MarfaTypesPage?

    init(page: MarfaTypesPage) {
        self.page = page
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        page?.receive(message.body, from: message.webView)
    }
}

/// One part of the page in its column, reaching up under the toolbar as a note does.
struct MarfaTypesView: View {
    let part: WebViewContainer

    var body: some View {
        GeometryReader { proxy in
            MarfaTypesWebView(part: part, topInset: proxy.safeAreaInsets.top)
                .ignoresSafeArea(.container, edges: .top)
        }
    }
}

private struct MarfaTypesWebView: NSViewRepresentable {
    let part: WebViewContainer
    let topInset: CGFloat

    func makeNSView(context: Context) -> WebViewContainer {
        part
    }

    func updateNSView(_ container: WebViewContainer, context: Context) {
        container.topInset = topInset
    }

    // WebKit lays out badly at fractional sizes, so the proposal is rounded down to whole points.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WebViewContainer, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width.rounded(.down), height: height.rounded(.down))
    }
}
