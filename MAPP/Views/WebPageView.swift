import SwiftUI
import WebKit

/// An HTML document shown in a page that can reach nothing outside it (`SealedWebPage`), as it was written or, with a
/// `look`, restyled. It draws no header, border or other chrome; the place that shows it decides what goes around, and
/// can leave a space at the top for it. A look that asks for it (`SourceLook.isOnSurface`) is placed on the surface behind pages, as Mail places a message,
/// and one that leaves the background unpainted lets the window's show through. Its pictures come from
/// `pictures`, once `SealedPictureRewrite` has pointed them there; the page it was first shown with keeps answering, so a
/// place that shows another item's document gives it a view of its own.
struct WebPageView: View {
    private let html: Data
    private let encoding: String.Encoding?
    private let pictures: SealedPictures?
    private let runsScripts: Bool
    private let look: SourceLook?
    private let topInset: CGFloat
    private let scrolled: (CGFloat) -> Void
    @State private var sealed: SealedWebPage?
    @State private var failure: String?

    /// An HTML document already in hand, which runs its own scripts only where `runsScripts` says so. It is read in
    /// `encoding`, or where none is given, in the one its bytes declare (`SealedWebPage.show`).
    ///
    /// The page starts `topInset` below the top of the view, a space the caller fills (the toolbar and the item's header)
    /// and the page scrolls under. `scrolled` hears how far the page has moved from its start.
    init(
        html: Data, encoding: String.Encoding? = nil, pictures: SealedPictures? = nil, runsScripts: Bool, look: SourceLook? = nil,
        topInset: CGFloat = 0, scrolled: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.html = html
        self.encoding = encoding
        self.pictures = pictures
        self.runsScripts = runsScripts
        self.look = look
        self.topInset = topInset
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
                    .background(ContentInset(top: topInset))
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
        .onChange(of: pictures?.version) { _, version in
            guard let version, let sealed else { return }
            Task { await sealed.redrawPictures(version: version) }
        }
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

/// Gives the web view behind it an inset at its top, which the page starts below and scrolls under. SwiftUI's
/// `contentMargins` does not reach a web view, and a safe-area inset would clip the page where the header is instead of
/// letting it scroll under. The page's own layout viewport is the space below the inset. The same view hands the wheel
/// over the inset to the page, which the header drawn there would otherwise keep.
private struct ContentInset: NSViewRepresentable {
    let top: CGFloat

    final class Probe: NSView {
        var top: CGFloat = 0

        /// The web view this view is drawn behind: the nearest one found in an ancestor's subviews.
        private var webView: WKWebView? {
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

        func apply() {
            guard let webView, webView.obscuredContentInsets.top != top else { return }
            webView.obscuredContentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        }

        // The web view joins the hierarchy beside this view only after it is placed, and a new document replaces it.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    self?.forwarded(event) ?? event
                }
            }
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        override func layout() {
            super.layout()
            apply()
        }

        private var monitor: Any?

        /// The header is drawn over the top of the web view and takes the wheel there, so a scroll that starts over it
        /// would not reach the page. It goes to the page instead; nil says the web view has it.
        func forwarded(_ event: NSEvent) -> NSEvent? {
            guard let webView, let window, event.window === window, abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
                webView.bounds.contains(webView.convert(event.locationInWindow, from: nil)),
                let frame = window.contentView?.superview,
                let hit = window.contentView?.hitTest(frame.convert(event.locationInWindow, from: nil)),
                !hit.isDescendant(of: webView)
            else { return event }
            webView.scrollWheel(with: event)
            return nil
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.top = top
        view.apply()
    }
}
