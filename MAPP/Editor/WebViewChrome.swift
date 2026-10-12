import WebKit

/// How the app's web views sit in a window with a Liquid Glass toolbar. Apple's own SwiftUI `WebView` does both
/// of these through WebKit settings that are not public API; they are set here the same way, only while WebKit
/// answers to them, and each reports whether it took, so a web view without them keeps its own background and
/// stops below the toolbar.
extension WKWebView {
    /// Leaves the web view clear, so the window's own background shows through a page whose background is
    /// transparent, and the page and the toolbar above it read as one surface, as in Mail. The page is marked with
    /// `window-background` only then. Call before loading.
    @discardableResult
    func showsWindowBackground() -> Bool {
        guard responds(to: NSSelectorFromString("_setDrawsBackground:")) else { return false }
        setValue(false, forKey: "drawsBackground")
        configuration.userContentController.addUserScript(WKUserScript(
            source: "document.documentElement.classList.add('window-background')",
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        return true
    }

    /// Lets the page run under the toolbar with the soft edge the system draws over scrolling content, rather
    /// than the hard line WebKit draws otherwise. The part of the page the toolbar covers is then given as
    /// `obscuredContentInsets`, so the page starts below the toolbar and scrolls beneath it.
    @discardableResult
    func fadesUnderToolbar() -> Bool {
        guard responds(to: NSSelectorFromString("_setUsesAutomaticContentInsetBackgroundFill:")) else { return false }
        setValue(true, forKey: "usesAutomaticContentInsetBackgroundFill")
        return true
    }
}

/// Holds a web view that reaches up under the toolbar. Where WebKit can soften the toolbar's edge, the page runs
/// under the toolbar and scrolls beneath it, told how much of it is covered; otherwise it stops below, since
/// WebKit would draw a hard line over it. Which of the two is decided once, and the page never moves while it
/// scrolls: moving it changed where the text sat, and the page jumped.
class WebViewContainer: NSView {
    let webView: WKWebView
    private let runsUnderToolbar: Bool

    /// How far the toolbar, and anything the window shows above the page, overlaps the container.
    var topInset: CGFloat = 0 {
        didSet { if topInset != oldValue { needsLayout = true } }
    }

    /// How much of the container's top the page lies beneath; subclasses add what they show there.
    var coveredTop: CGFloat { topInset }

    init(webView: WKWebView) {
        self.webView = webView
        runsUnderToolbar = webView.fadesUnderToolbar()
        super.init(frame: .zero)
        clipsToBounds = true
        // AppKit resizes the child with the container during live resizing, before the next layout pass.
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
    }

    // WebKit's printing thread queries these constant view properties.
    nonisolated override var isOpaque: Bool { true }
    nonisolated override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // The transparent page needs backing in its own column, including the region below the toolbar.
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let top = coveredTop
        if runsUnderToolbar {
            webView.frame = bounds
            if webView.obscuredContentInsets.top != top {
                webView.obscuredContentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
            }
        } else {
            webView.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        }
    }
}
