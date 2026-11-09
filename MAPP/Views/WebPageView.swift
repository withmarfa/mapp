import SwiftUI
import WebKit

/// An HTML document shown in a page that can reach nothing outside it (`SealedWebPage`), as it was written or, with a
/// `look`, restyled. It draws no header, border or other chrome; the place that shows it decides what goes around, and
/// can leave a space at the top for it. A look that asks for it (`SourceLook.isOnSurface`) is placed on the surface
/// behind pages, as Mail places a message, and one that leaves the background unpainted lets the window's show through.
/// Its pictures come from `pictures`, once `SealedPictureRewrite` has pointed them there; the page it was first shown
/// with keeps answering, so a place that shows another item's document gives it a view of its own.
struct WebPageView: View {
    private let html: Data
    private let encoding: String.Encoding?
    private let pictures: SealedPictures?
    private let runsScripts: Bool
    private let look: SourceLook?
    private let topInset: CGFloat
    private let givesBack: CGFloat
    private let scrolled: (CGFloat) -> Void
    @State private var sealed: SealedWebPage?
    @State private var failure: String?
    /// How much of the inset the page has given back, and the scroll that goes with it (`InsetCollapse`).
    @State private var givenBack: CGFloat = 0
    @State private var position = ScrollPosition()
    @State private var collapse = CollapseHolder()

    /// An HTML document already in hand, which runs its own scripts only where `runsScripts` says so. It is read in
    /// `encoding`, or where none is given, in the one its bytes declare (`SealedWebPage.show`).
    ///
    /// The page starts `topInset` below the top of the view, a space the caller fills (the toolbar and the item's header)
    /// and the page scrolls under. `givesBack` of it, the part the caller's header takes, shrinks as the page scrolls, so
    /// that a header the page draws itself meets what is above the page once the caller's has gone. `scrolled` hears how
    /// far the person has scrolled the page from its start.
    init(
        html: Data, encoding: String.Encoding? = nil, pictures: SealedPictures? = nil, runsScripts: Bool, look: SourceLook? = nil,
        topInset: CGFloat = 0, givesBack: CGFloat = 0, scrolled: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.html = html
        self.encoding = encoding
        self.pictures = pictures
        self.runsScripts = runsScripts
        self.look = look
        self.topInset = topInset
        self.givesBack = givesBack
        self.scrolled = scrolled
    }

    var body: some View {
        Group {
            // The failure comes first, since the page that is still held is the last document's, not this one's.
            if let failure {
                ContentUnavailableView {
                    Label("Can’t Show This Page", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                }
            } else if let sealed {
                WebView(sealed.page)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .webViewMagnificationGestures(.disabled)
                    .webViewLinkPreviews(.disabled)
                    .webViewContentBackground(look?.leavesBackground == true ? .hidden : .automatic)
                    .webViewScrollPosition($position)
                    .background(ContentInset(top: topInset - givenBack))
                    // The offset is the page's own, `scrollY`: zero at rest, whatever the inset.
                    .webViewOnScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in
                        pageScrolled(to: new)
                    }
                    // Each document has a page of its own, so a new one gets a new web view, which lets go of the
                    // page that held the last document and stops its scripts.
                    .id(ObjectIdentifier(sealed.page))
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(look?.isOnSurface == true ? Color(nsColor: .underPageBackgroundColor) : .clear)
        .accessibilityIdentifier("WebPageView")
        // A new web view starts at the top and reports nothing while it stays there.
        .onChange(of: sealed.map { ObjectIdentifier($0.page) }) {
            collapse.value.reset()
            givenBack = 0
            scrolled(0)
        }
        .task(id: Reload(html: html, look: look)) { await load() }
        .onChange(of: pictures?.version) { _, version in
            guard let version, let sealed else { return }
            Task { await sealed.redrawPictures(version: version) }
        }
    }

    private func pageScrolled(to scrollY: CGFloat) {
        if let adjustment = collapse.value.scrolled(to: scrollY, space: givesBack) {
            givenBack = adjustment.consumed
            position.scrollTo(y: adjustment.scrollY)
        }
        scrolled(collapse.value.distance)
    }

    /// A document is shown again when its bytes or its look change; a look cannot be taken off a loaded document.
    private struct Reload: Equatable {
        let html: Data
        let look: SourceLook?
    }

    private func load() async {
        failure = nil
        do {
            let page: SealedWebPage
            if let sealed { page = sealed } else { page = try await SealedWebPage.make(pictures: pictures, runsScripts: runsScripts) }
            try await page.show(html, encoding: encoding, look: look)
            sealed = page
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Holds the collapse where a scroll can change it without redrawing the page.
private final class CollapseHolder {
    var value = InsetCollapse()
}

/// Gives the web view behind it an inset at its top, which the page starts below and scrolls under. SwiftUI's
/// `contentMargins` does not reach a web view, and a safe-area inset would clip the page where the header is instead of
/// letting it scroll under. The page's own layout viewport is the space below the inset. The same view hands the wheel
/// over the inset to the page, which the header drawn there would otherwise keep.
private struct ContentInset: NSViewRepresentable {
    let top: CGFloat

    final class Probe: NSView {
        var top: CGFloat = 0
        private weak var webView: WKWebView?
        private var monitor: Any?
        private var gesture = WheelGesture()

        /// The web view this view is drawn behind: the nearest one found in an ancestor's subviews. A new document
        /// replaces it, so one that has left the window is looked for again.
        func apply() {
            if webView?.window == nil { webView = findWebView() }
            guard let webView, webView.obscuredContentInsets.top != top else { return }
            webView.obscuredContentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
            // A new inset alone leaves the page's fixed and sticky layers where they were, and the web view fills the gap
            // with their colour; laying it out at once moves them to the new edge.
            webView.layoutSubtreeIfNeeded()
        }

        private func findWebView() -> WKWebView? {
            var ancestor = superview
            while let current = ancestor {
                if let found = Self.webView(in: current) { return found }
                ancestor = current.superview
            }
            return nil
        }

        private static func webView(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            for subview in view.subviews { if let found = webView(in: subview) { return found } }
            return nil
        }

        // The web view joins the hierarchy beside this view only after it is placed, and a new document replaces it.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopForwarding()
            if window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self else { return event }
                    return forwarded(event)
                }
            }
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        override func layout() {
            super.layout()
            apply()
        }

        func stopForwarding() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            gesture = WheelGesture()
        }

        /// The header is drawn over the top of the web view and takes the wheel there, so a scroll that starts over it
        /// would not reach the page. It goes to the page instead, and nothing else gets it; nil says it was handed
        /// over. Every other event is left to the window.
        func forwarded(_ event: NSEvent) -> NSEvent? {
            guard let webView, let window, event.window === window else { return event }
            guard gesture.forwards(phase: event.phase, momentumPhase: event.momentumPhase, overHeader: isOverHeader(event, of: webView)) else {
                return event
            }
            webView.scrollWheel(with: event)
            return nil
        }

        /// Whether a mostly vertical scroll is at a point of the web view that something drawn over it, the header, takes.
        private func isOverHeader(_ event: NSEvent, of webView: WKWebView) -> Bool {
            guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
                webView.bounds.contains(webView.convert(event.locationInWindow, from: nil)),
                let frame = window?.contentView?.superview,
                let hit = window?.contentView?.hitTest(frame.convert(event.locationInWindow, from: nil))
            else { return false }
            return !hit.isDescendant(of: webView)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.top = top
        view.apply()
    }

    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stopForwarding() }
}

/// Which wheel events the header's inset hands to the page. A mouse wheel sends one event per notch, so the position
/// decides each. A trackpad sends a gesture: its fingers' events, then the momentum that follows. The page has all of a
/// gesture that began over the header, wherever the pointer goes next, and the window keeps the rest of the events,
/// so each event reaches the page once.
nonisolated struct WheelGesture {
    private var ownedByPage = false

    /// Whether the page is to be handed the event.
    mutating func forwards(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, overHeader: Bool) -> Bool {
        // A mouse wheel has neither phase.
        if phase.isEmpty && momentumPhase.isEmpty { return overHeader }
        // Fingers resting on the trackpad have not started a scroll yet.
        if phase.contains(.mayBegin) { return overHeader }
        if phase.contains(.began) {
            ownedByPage = overHeader
            return overHeader
        }
        let forwards = ownedByPage || overHeader
        if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) { ownedByPage = false }
        return forwards
    }
}

/// How much of the space a web page leaves for the item's header it has given back. The page scrolls under that space, so
/// a header the page draws itself (fixed or sticky) sits below it, and once the item's own header has scrolled away
/// that leaves a gap under the toolbar. As the person scrolls, the space shrinks by the distance scrolled, up to all of
/// it, and the page's scroll is lowered by the same distance, so what is drawn does not move. The distance the person
/// has scrolled is then what the page gave back plus the page's own offset.
nonisolated struct InsetCollapse {
    /// What the space and the page's scroll are to be set to.
    struct Adjustment: Equatable {
        let consumed: CGFloat
        let scrollY: CGFloat
    }

    private(set) var consumed: CGFloat = 0
    /// How far the person has scrolled, as of the last report that counted.
    private(set) var distance: CGFloat = 0
    /// The offset a page reported just before it was moved, which a late report of it must not count twice.
    private var replaced: CGFloat?

    /// How far the person has scrolled, which the item's header follows.
    func offset(scrollY: CGFloat) -> CGFloat { consumed + scrollY }

    /// The page reports it is at `scrollY`, with `space` of the inset there to give back. Nil where nothing is to change.
    mutating func scrolled(to scrollY: CGFloat, space: CGFloat) -> Adjustment? {
        if let stale = replaced {
            replaced = nil
            if stale == scrollY { return nil }
        }
        let total = offset(scrollY: scrollY)
        distance = total
        let next = min(max(total, 0), max(space, 0))
        guard next != consumed else { return nil }
        consumed = next
        if total - next != scrollY { replaced = scrollY }
        return Adjustment(consumed: next, scrollY: total - next)
    }

    mutating func reset() {
        consumed = 0
        distance = 0
        replaced = nil
    }
}
