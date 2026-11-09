import Foundation
import SwiftUI
import WebKit

/// A web page that can show one HTML document and nothing else. The document is untrusted: it may run its own scripts
/// where the page allows them, but it reaches no network, loads nothing but what it holds and the pictures the app gives
/// it, submits no form and leaves no trace.
///
/// Each document gets a page of its own, sealed the same way, and `page` changes to it once it has loaded. A document
/// can start a navigation at any moment, and one it starts while a load into its own page still waits for that load's
/// policy decision replaces the load: WebKit then drops the replaced load without finishing or failing it, so the new
/// document would never appear. A page that has held no document has no script that could start one.
///
/// The seal has four parts, and each covers what the others cannot:
/// - A content rule list blocks every load but `data:`, `blob:` and `about:`, which cover only what the document holds
///   itself, and the app's own picture scheme (`SealedPictures`), which the app answers from what it holds or what the
///   Remote Pictures setting lets it fetch. It applies to images, scripts, styles, `fetch`, XHR, WebSockets and frames
///   alike.
/// - A navigation decider cancels every navigation of the main frame but the one this type starts, so a link, a form
///   submission, `location` and a redirect go nowhere. Frames the document builds for itself (`about:`, `data:`, `blob:`)
///   are allowed, and nothing else.
/// - A script that runs before the document's own, in every frame, ends every click and removes WebRTC and media
///   devices. WebKit opens a connection to the address of a link that activates before it asks the decider, and a
///   content rule sees neither that connection nor a STUN or ICE datagram; WebKit has no public setting that turns
///   either off.
/// - The page keeps its data in memory (`WKWebsiteDataStore.nonPersistent()`), has no script message handler, and has
///   no bridge to the app but the picture scheme, which answers only the pictures its document was found to name.
///
/// A page made with `runsScripts` false runs none of the document's scripts; the app's own run in a world of their own
/// that the document cannot reach.
///
/// Links do nothing. A document from a file in someone's library is not a page to browse from; a link that opened the
/// browser would be the document choosing where the person goes.
///
/// No script can see inside a closed shadow root, so the seal ends every click rather than looking for links, and a
/// document loses what clicks do for it:
/// - A click does nothing by default: a button or label does not act, and a checkbox or radio button does not change.
///   The script opens a `<details>` element itself, so a disclosure still works.
/// - The document's own click handlers still run, and find the click canceled.
/// - A scripted click does not happen: `click()` does nothing and a dispatched `click` or `auxclick` is dropped, so a
///   saved page that drives its own buttons that way loses them.
/// - WebKit runs no listener in a frame sandboxed without `allow-scripts`, so the seal makes that frame inert: it
///   shows, but takes no click, focus or selection.
@MainActor @Observable final class SealedWebPage {
    /// The page that holds the document shown last.
    private(set) var page: WebPage
    /// The decider of the first page until a `show` takes that page for its document, so the first document loads
    /// into it; every later document gets a page and decider of its own.
    @ObservationIgnored private var unused: NavigationGate?
    /// Counts the calls to `show`, so a load that finishes after a later one started is not shown over it.
    @ObservationIgnored private var shows = 0

    /// Answers the document's pictures, where it has any to answer.
    @ObservationIgnored private let pictures: SealedPictures?
    @ObservationIgnored private let runsScripts: Bool
    /// The space left above the document's first line, which every document is given before it appears.
    @ObservationIgnored private var topSpace: CGFloat = 0

    private init(page: WebPage, gate: NavigationGate, pictures: SealedPictures?, runsScripts: Bool) {
        self.page = page
        unused = gate
        self.pictures = pictures
        self.runsScripts = runsScripts
    }

    /// A page whose documents draw their pictures from `pictures`, and run their own scripts only where `runsScripts`
    /// says so. Without `pictures`, a picture of the app's scheme is not answered.
    static func make(pictures: SealedPictures? = nil, runsScripts: Bool) async throws -> SealedWebPage {
        let (page, gate) = try await blank(pictures: pictures, runsScripts: runsScripts)
        return SealedWebPage(page: page, gate: gate, pictures: pictures, runsScripts: runsScripts)
    }

    /// A sealed page that has held no document. Compiles the rules the first time and reuses them after.
    private static func blank(pictures: SealedPictures?, runsScripts: Bool) async throws -> (WebPage, NavigationGate) {
        let rules = try await ruleList()
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultNavigationPreferences.allowsContentJavaScript = runsScripts
        if let pictures { configuration.urlSchemeHandlers[URLScheme(SealedPictures.scheme)!] = SealedPictureScheme(pictures: pictures) }
        configuration.userContentController.add(rules)
        configuration.userContentController.addUserScript(WKUserScript(source: Self.lockdown, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let gate = NavigationGate()
        return (WebPage(configuration: configuration, navigationDecider: gate), gate)
    }

    /// Shows `html` in place of what was shown, once the document has loaded. Until then, and if the load fails, `page`
    /// keeps the page it had, which for the first document is the page that document loads into. Throws
    /// `CancellationError` when the task is cancelled or a later call starts before this one's document has loaded,
    /// since a document shown over a newer one would be out of date. A `look` restyles it before it appears. Its relative links resolve against nothing.
    ///
    /// The document is read in `encoding`, or where none is given, in the one `HTMLEncoding` finds for its bytes: the
    /// page has to be told one, which overrides what the document declares.
    ///
    /// Where the pictures' version moved on while the document loaded, as when the setting changed, the page asks
    /// for its pictures again at the version now current, since only those answers count what waits for the person.
    func show(_ html: Data, encoding: String.Encoding? = nil, look: SourceLook? = nil) async throws {
        shows += 1
        let call = shows
        let encoding = encoding ?? HTMLEncoding.of(html)
        let next: WebPage
        let nextGate: NavigationGate
        if let gate = unused {
            unused = nil
            (next, nextGate) = (page, gate)
        } else {
            (next, nextGate) = try await Self.blank(pictures: pictures, runsScripts: runsScripts)
            guard call == shows else { throw CancellationError() }
        }
        nextGate.allow(Self.base)
        defer { nextGate.disallow() }
        for try await _ in next.load(html, mimeType: "text/html", characterEncoding: encoding, baseURL: Self.base) {}
        // A cancelled load ends its sequence without an error.
        try Task.checkCancellation()
        guard call == shows else { throw CancellationError() }
        // Before the page is swapped in, so the person never sees the document unstyled. A look that fails to apply
        // leaves the document as it loaded.
        _ = try? await next.callJavaScript(Self.makeRoom, arguments: ["points": Double(topSpace)], contentWorld: Self.world)
        try Task.checkCancellation()
        guard call == shows else { throw CancellationError() }
        if let look {
            _ = try? await next.callJavaScript(SourceLook.script, arguments: look.arguments, contentWorld: Self.world)
            // The await above is a suspension: a newer call may have started, or this one been cancelled.
            try Task.checkCancellation()
            guard call == shows else { throw CancellationError() }
        }
        page = next
        guard let pictures else { return }
        var drawn = pictures.documentVersion
        while drawn != pictures.version, call == shows {
            drawn = pictures.version
            await redrawPictures(version: drawn)
        }
    }

    static let base = URL(string: "about:blank")!

    /// Leaves `points` above the document's first line, inside the page's own scroll, for what the caller draws over the
    /// top of the page, so the page scrolls it away with the document and its layout viewport starts where the page
    /// does. Applies to the document shown now and to every later one.
    func leaveRoom(above points: CGFloat) async {
        topSpace = points
        _ = try? await page.callJavaScript(Self.makeRoom, arguments: ["points": Double(points)], contentWorld: Self.world)
    }

    /// Pads the root element through its inline style, which a content security policy does not govern and a style sheet
    /// of the document cannot outrank.
    nonisolated static let makeRoom = SafeDOM.script + """

        const root = dom.documentElement(document);
        if (root) Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'style').get.call(root).setProperty('padding-top', points + 'px', 'important');
        """

    /// Has the document ask for its pictures again, from the URLs of `version`, without loading it again, so the place
    /// the person has read to is kept. The script runs in a world of its own, which works whether or not the
    /// document's scripts run.
    func redrawPictures(version: Int) async {
        _ = try? await page.callJavaScript(Self.redraw, arguments: ["version": String(version)], contentWorld: Self.world)
    }

    /// The world the app's own scripts run in: its globals are not the document's, so the document cannot see or change
    /// them, while the DOM is shared.
    static let world = WKContentWorld.world(name: "MAPPSealedPictures")

    nonisolated static let redraw = SafeDOM.script + """

        for (const img of dom.queryAllInDocument(document, 'img[src^="\(SealedPictures.scheme):"]')) {
          dom.setAttribute(img, 'src', dom.getAttribute(img, 'src').replace(/([?&]v=)\\d+/, '$1' + version));
        }
        """

    /// Runs at the start of every document in every frame, `about:blank` and `srcdoc` frames included, each of which has
    /// a realm of its own and gets the script before any page script runs.
    ///
    /// The first part keeps a link from activating, by a person or a script, with or without a document or a window
    /// around it: a click that reaches no window never meets the listeners, so the script also takes away the ways to
    /// start one. The second part removes the interfaces through which a page could send UDP to a host it picks, which
    /// would show the Mac's address.
    nonisolated static let lockdown = """
        (() => {
          // Taken now, before the document's own scripts run, so neither they nor a name in the document can replace them.
          const call = Function.prototype.call;
          const stop = call.bind(Event.prototype.preventDefault);
          const kind = call.bind(Object.getOwnPropertyDescriptor(Event.prototype, 'type').get);
          const path = call.bind(Event.prototype.composedPath);
          const send = call.bind(EventTarget.prototype.dispatchEvent);
          const closest = call.bind(Element.prototype.closest);
          const toggle = call.bind(Element.prototype.toggleAttribute);
          const has = call.bind(Element.prototype.hasAttribute);
          const set = call.bind(Element.prototype.setAttribute);
          const root = call.bind(Object.getOwnPropertyDescriptor(Document.prototype, 'documentElement').get);
          const observe = call.bind(MutationObserver.prototype.observe);
          const Observer = MutationObserver;
          const page = document;
          addEventListener('click', e => {
            stop(e);
            try {
              const summary = closest(path(e)[0], 'details > summary:first-of-type');
              if (summary) toggle(closest(summary, 'details'), 'open');
            } catch (x) {}
          }, true);
          addEventListener('auxclick', e => stop(e), true);
          addEventListener('submit', e => stop(e), true);
          // A sandbox without allow-scripts lets this script run but none of its listeners. The observer does run, and
          // keeps a same-origin parent from undoing the inert state.
          let listens = false;
          const test = new EventTarget();
          test.addEventListener('test', () => { listens = true; });
          send(test, new Event('test'));
          if (!listens) {
            const hold = () => { const element = root(page); if (element && !has(element, 'inert')) set(element, 'inert', ''); };
            hold();
            observe(new Observer(hold), page, { subtree: true, childList: true, attributes: true, attributeFilter: ['inert'] });
          }
          const replace = (type, name, value) => Object.defineProperty(type.prototype, name, { value, writable: false, configurable: false });
          replace(HTMLElement, 'click', function () {});
          replace(EventTarget, 'dispatchEvent', function (e) { const name = kind(e); return name === 'click' || name === 'auxclick' ? true : send(this, e); });
          replace(HTMLFormElement, 'submit', function () {});
          replace(HTMLFormElement, 'requestSubmit', function () {});
        })();
        for (const name of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel', 'RTCSessionDescription', 'RTCIceCandidate', 'RTCPeerConnectionIceEvent', 'RTCDataChannelEvent', 'RTCRtpSender', 'RTCRtpReceiver', 'RTCRtpTransceiver', 'RTCSctpTransport', 'RTCDtlsTransport', 'RTCIceTransport', 'RTCCertificate']) delete window[name];
        delete Navigator.prototype.mediaDevices;
        """

    /// What the rules say, as the JSON WebKit compiles.
    nonisolated static let rules = """
        [
          {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^\(SealedPictures.scheme):"}, "action": {"type": "ignore-previous-rules"}}
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
