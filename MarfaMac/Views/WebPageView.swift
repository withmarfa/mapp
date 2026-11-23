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
    private let toolbarInset: CGFloat
    private let topSpace: CGFloat
    private let scrolled: (CGFloat) -> Void
    @State private var sealed: SealedWebPage?
    @State private var failure: String?

    /// An HTML document already in hand, which runs its own scripts only where `runsScripts` says so. It is read in
    /// `encoding`, or where none is given, in the one its bytes declare (`SealedWebPage.show`).
    ///
    /// The page's layout viewport starts `toolbarInset` below the top of the view, where the toolbar ends, so a fixed or
    /// sticky header of its own meets the toolbar. The document itself starts `topSpace` lower, inside the page's own
    /// scroll, a space the caller fills with the item's header, which scrolls away with it. `scrolled` hears how far the
    /// page has moved from its start.
    init(
        html: Data, encoding: String.Encoding? = nil, pictures: SealedPictures? = nil, runsScripts: Bool, look: SourceLook? = nil,
        toolbarInset: CGFloat = 0, topSpace: CGFloat = 0, scrolled: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.html = html
        self.encoding = encoding
        self.pictures = pictures
        self.runsScripts = runsScripts
        self.look = look
        self.toolbarInset = toolbarInset
        self.topSpace = topSpace
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
                    .background(ContentInset(top: toolbarInset))
                    // The offset is the page's own, `scrollY`: zero at rest, whatever the inset.
                    .webViewOnScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in
                        scrolled(new)
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
        .onChange(of: sealed.map { ObjectIdentifier($0.page) }) { scrolled(0) }
        .task(id: Reload(html: html, look: look)) { await load() }
        // Again for each document, since the space is the header's height, which can change while one loads.
        .task(id: Room(points: topSpace, page: sealed.map { ObjectIdentifier($0.page) })) { await sealed?.leaveRoom(above: topSpace) }
        .onChange(of: pictures?.version) { _, version in
            guard let version, let sealed else { return }
            Task { await sealed.redrawPictures(version: version) }
        }
    }

    private struct Room: Equatable {
        let points: CGFloat
        let page: ObjectIdentifier?
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

/// Gives the web view behind it an inset at its top, where the toolbar ends: the page's layout viewport is the space
/// below it, so a fixed or sticky header of the page's own meets the toolbar, and the page scrolls under the toolbar.
/// SwiftUI's `contentMargins` does not reach a web view, and a safe-area inset would clip the page. The inset never
/// changes with the scroll. The same view hands the wheel over the item's header, drawn over the top of the page, to
/// the page, which the header would otherwise keep.
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
