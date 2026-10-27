import Foundation
import SwiftUI
import WebKit

/// A web page that can show one HTML document and nothing else. The document is untrusted: it may run its own scripts,
/// but it reaches no network, loads nothing from outside itself, submits no form and leaves no trace.
///
/// The seal has three parts, each of which holds without the others:
/// - A content rule list blocks every load but `data:`, `blob:` and `about:`, which cover only what the document holds
///   itself. It applies to images, scripts, styles, `fetch`, XHR, WebSockets and frames alike.
/// - A navigation decider cancels every navigation of the main frame but the one this type starts, so a link, a form
///   submission, `location` and a redirect go nowhere. Frames the document builds for itself (`about:`, `data:`, `blob:`)
///   are allowed, and nothing else.
/// - The page keeps its data in memory (`WKWebsiteDataStore.nonPersistent()`), has no script message handler or other
///   bridge to the app, and loads no subresource a rule would let through.
///
/// Links do nothing. A document from a file in someone's library is not a page to browse from; a link that opened the
/// browser would be the document choosing where the person goes.
@MainActor @Observable final class SealedWebPage {
    let page: WebPage
    private let gate: NavigationGate

    private init(page: WebPage, gate: NavigationGate) {
        self.page = page
        self.gate = gate
    }

    /// Compiles the rules the first time and reuses them after.
    static func make() async throws -> SealedWebPage {
        let rules = try await ruleList()
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        configuration.userContentController.add(rules)
        configuration.userContentController.addUserScript(WKUserScript(source: Self.linkStopper, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let gate = NavigationGate()
        return SealedWebPage(page: WebPage(configuration: configuration, navigationDecider: gate), gate: gate)
    }

    /// Shows `html`, replacing what the page held, and returns once the document has loaded. Its relative links
    /// resolve against nothing.
    func show(_ html: Data) async throws {
        let text = String(data: html, encoding: .utf8)
        let data = text.map { Data($0.utf8) } ?? html
        gate.allowNext()
        for try await _ in page.load(data, mimeType: "text/html", characterEncoding: text == nil ? .windowsCP1252 : .utf8, baseURL: Self.base) {}
    }

    static let base = URL(string: "about:blank")!

    /// WebKit opens a connection to the address of a clicked link or a submitted form before it judges the navigation,
    /// so the rules cannot stop that. This ends the click and the submission first. The rules and the navigation gate
    /// stay the seal.
    nonisolated static let linkStopper = """
        addEventListener('click', e => { if (e.target instanceof Element && e.target.closest('a[href], area[href]')) e.preventDefault(); }, true);
        addEventListener('submit', e => e.preventDefault(), true);
        for (const name of ['submit', 'requestSubmit']) Object.defineProperty(HTMLFormElement.prototype, name, { value() {}, writable: false, configurable: false });
        """

    /// What the rules say, as the JSON WebKit compiles.
    nonisolated static let rules = """
        [
          {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}
        ]
        """

    private static var compiled: WKContentRuleList?

    private static func ruleList() async throws -> WKContentRuleList {
        if let compiled { return compiled }
        let store = WKContentRuleListStore.default()
        let list = try await store?.compileContentRuleList(forIdentifier: "MAPPSealedWebPage", encodedContentRuleList: rules)
        guard let list else { throw SealFailure.rulesNotCompiled }
        compiled = list
        return list
    }

    enum SealFailure: Error { case rulesNotCompiled }

    /// Decides every navigation: only the load `show` starts passes.
    private final class NavigationGate: WebPage.NavigationDeciding {
        private var allowed = false

        func allowNext() { allowed = true }

        func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
            if action.target?.isMainFrame == false {
                let scheme = action.request.url?.scheme?.lowercased()
                return ["about", "data", "blob"].contains(scheme) ? .allow : .cancel
            }
            guard allowed else { return .cancel }
            allowed = false
            return .allow
        }
    }
}
