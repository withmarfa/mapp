import Foundation
import SwiftUI
import WebKit

/// A web page that can show one HTML document and nothing else. The document is untrusted: it may run its own scripts,
/// but it reaches no network, loads nothing from outside itself, submits no form and leaves no trace.
///
/// Each document gets a page of its own, sealed the same way, and `page` changes to it once it has loaded. A document
/// can start a navigation at any moment, and one it starts while a load into its own page still waits for that load's
/// policy decision replaces the load: WebKit then drops the replaced load without finishing or failing it, so the new
/// document would never appear. A page that has held no document has no script that could start one.
///
/// The seal has four parts, each of which holds in every page without the others:
/// - A content rule list blocks every load but `data:`, `blob:` and `about:`, which cover only what the document holds
///   itself. It applies to images, scripts, styles, `fetch`, XHR, WebSockets and frames alike.
/// - A navigation decider cancels every navigation of the main frame but the one this type starts, so a link, a form
///   submission, `location` and a redirect go nowhere. Frames the document builds for itself (`about:`, `data:`, `blob:`)
///   are allowed, and nothing else.
/// - A script that runs before the document's own, in every frame, removes WebRTC and media devices. A content rule
///   governs resource loads and never sees a STUN or ICE datagram, and WebKit has no public setting that turns WebRTC
///   off, so the interfaces that could send one are not there.
/// - The page keeps its data in memory (`WKWebsiteDataStore.nonPersistent()`), has no script message handler or other
///   bridge to the app, and loads no subresource a rule would let through.
///
/// Links do nothing. A document from a file in someone's library is not a page to browse from; a link that opened the
/// browser would be the document choosing where the person goes.
@MainActor @Observable final class SealedWebPage {
    /// The page that holds the document shown last.
    private(set) var page: WebPage
    /// The decider of the first page until a `show` takes that page for its document, so the first document loads
    /// into it; every later document gets a page and decider of its own.
    @ObservationIgnored private var unused: NavigationGate?
    /// Counts the calls to `show`, so a load that finishes after a later one started is not shown over it.
    @ObservationIgnored private var shows = 0

    private init(page: WebPage, gate: NavigationGate) {
        self.page = page
        unused = gate
    }

    static func make() async throws -> SealedWebPage {
        let (page, gate) = try await blank()
        return SealedWebPage(page: page, gate: gate)
    }

    /// A sealed page that has held no document. Compiles the rules the first time and reuses them after.
    private static func blank() async throws -> (WebPage, NavigationGate) {
        let rules = try await ruleList()
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        configuration.userContentController.add(rules)
        configuration.userContentController.addUserScript(WKUserScript(source: Self.lockdown, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let gate = NavigationGate()
        return (WebPage(configuration: configuration, navigationDecider: gate), gate)
    }

    /// Shows `html` in place of what was shown, once the document has loaded. Until then, and if the load fails, `page`
    /// keeps the page it had, which for the first document is the page that document loads into. Throws
    /// `CancellationError` when the task is cancelled or a later call starts before this one's document has loaded,
    /// since a document shown over a newer one would be out of date. Its relative links resolve against nothing.
    func show(_ html: Data) async throws {
        shows += 1
        let call = shows
        let text = String(data: html, encoding: .utf8)
        let data = text.map { Data($0.utf8) } ?? html
        let next: WebPage
        let nextGate: NavigationGate
        if let gate = unused {
            unused = nil
            (next, nextGate) = (page, gate)
        } else {
            (next, nextGate) = try await Self.blank()
            guard call == shows else { throw CancellationError() }
        }
        nextGate.allow(Self.base)
        defer { nextGate.disallow() }
        for try await _ in next.load(data, mimeType: "text/html", characterEncoding: text == nil ? .windowsCP1252 : .utf8, baseURL: Self.base) {}
        // A cancelled load ends its sequence without an error.
        try Task.checkCancellation()
        guard call == shows else { throw CancellationError() }
        page = next
    }

    static let base = URL(string: "about:blank")!

    /// Runs at the start of every document in every frame, `about:blank` and `srcdoc` frames included, each of which has
    /// a realm of its own and gets the script before any page script runs.
    ///
    /// WebKit opens a connection to the address of a clicked link or a submitted form before it judges the navigation,
    /// so the rules cannot stop that; the first part ends the click and the submission first. The second part removes
    /// the interfaces through which a page could send UDP to a host it picks, which would show the Mac's address.
    nonisolated static let lockdown = """
        addEventListener('click', e => { if (e.target instanceof Element && e.target.closest('a[href], area[href]')) e.preventDefault(); }, true);
        addEventListener('submit', e => e.preventDefault(), true);
        for (const name of ['submit', 'requestSubmit']) Object.defineProperty(HTMLFormElement.prototype, name, { value() {}, writable: false, configurable: false });
        for (const name of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel', 'RTCSessionDescription', 'RTCIceCandidate', 'RTCPeerConnectionIceEvent', 'RTCDataChannelEvent', 'RTCRtpSender', 'RTCRtpReceiver', 'RTCRtpTransceiver', 'RTCSctpTransport', 'RTCDtlsTransport', 'RTCIceTransport', 'RTCCertificate']) delete window[name];
        delete Navigator.prototype.mediaDevices;
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

    /// Decides every navigation: only the load `show` starts passes, once, and only for the request it makes, so a
    /// navigation the document starts, while it loads or after, can neither take the allowance nor outlive the load.
    final class NavigationGate: WebPage.NavigationDeciding {
        private var allowed: URL?

        func allow(_ url: URL) { allowed = url }
        func disallow() { allowed = nil }

        func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
            decide(url: action.request.url, inMainFrame: action.target?.isMainFrame != false)
        }

        func decide(url: URL?, inMainFrame: Bool) -> WKNavigationActionPolicy {
            if !inMainFrame {
                return ["about", "data", "blob"].contains(url?.scheme?.lowercased()) ? .allow : .cancel
            }
            guard let allowed, url == allowed else { return .cancel }
            self.allowed = nil
            return .allow
        }
    }
}
