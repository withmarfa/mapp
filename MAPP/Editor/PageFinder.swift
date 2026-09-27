import AppKit
import WebKit

/// What the page tells the find bar: its text as the find bar searches it, the selection and the visible
/// stretch as offsets into that text, and each visible character's box in page coordinates.
nonisolated struct FindState: Sendable {
    var text = ""
    var selection = NSRange(location: 0, length: 0)
    var visible = NSRange(location: 0, length: 0)
    /// Four numbers per character of `visible`: x, y, width and height, with the page's scroll added.
    var boxes: [Double] = []
    var scrollY: Double = 0
    /// The height of the page's window, which starts below whatever covers the web view's top.
    var viewportHeight: Double = 0
}

/// The system find bar over the page. The find bar asks its questions synchronously and the page answers
/// asynchronously, so the page keeps a copy of what the find bar needs here while the bar is open.
final class PageFinder: NSObject, NSTextFinderClient {
    let finder = NSTextFinder()
    private weak var controller: EditorController?
    private var state = FindState()

    init(controller: EditorController) {
        self.controller = controller
        super.init()
        finder.client = self
        finder.isIncrementalSearchingEnabled = true
        finder.incrementalSearchingShouldDimContentView = true
    }

    func update(_ state: FindState) {
        if state.text != self.state.text { finder.noteClientStringWillChange() }
        self.state = state
        finder.findIndicatorNeedsUpdate = true
    }

    private var webView: EditorWebView? { controller?.webView }

    // MARK: NSTextFinderClient

    var string: String { state.text }

    var isSelectable: Bool { true }
    var isEditable: Bool { controller?.isEditable ?? false }
    var allowsMultipleSelection: Bool { false }

    func shouldReplaceCharacters(inRanges ranges: [NSValue], with strings: [String]) -> Bool {
        isEditable
    }

    /// Replaces a match on the page, and in the copy here at once, since Replace All goes on to the next match
    /// before the page has answered.
    func replaceCharacters(in range: NSRange, with string: String) {
        controller?.findReplace(range, with: string)
        state.text = (state.text as NSString).replacingCharacters(in: range, with: string)
    }

    var firstSelectedRange: NSRange { state.selection }

    var selectedRanges: [NSValue] {
        get { [NSValue(range: state.selection)] }
        set {
            guard let range = newValue.first?.rangeValue else { return }
            state.selection = range
            controller?.findSelect(range)
        }
    }

    var visibleCharacterRanges: [NSValue] { [NSValue(range: state.visible)] }

    func scrollRangeToVisible(_ range: NSRange) {
        controller?.findScroll(range)
    }

    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        outRange.pointee = NSRange(location: 0, length: (state.text as NSString).length)
        return webView ?? NSView()
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        lineRects(for: range).map { NSValue(rect: $0) }
    }

    /// The characters as the find indicator shows them, in the page's body type.
    func drawCharacters(in range: NSRange, forContentView view: NSView) {
        let text = (state.text as NSString).substring(with: range)
        guard let first = lineRects(for: range).first else { return }
        let font = NSFont.systemFont(ofSize: max(10, min(first.height * 0.8, 28)))
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(x: first.minX, y: first.midY - size.height / 2))
    }

    /// The boxes of the characters in the range, joined into one rect per line, in the web view's coordinates.
    private func lineRects(for range: NSRange) -> [NSRect] {
        guard let webView else { return [] }
        let visible = state.visible
        let start = max(range.location, visible.location)
        let end = min(NSMaxRange(range), NSMaxRange(visible))
        guard start < end else { return [] }
        var lines: [NSRect] = []
        for index in start..<end {
            let base = (index - visible.location) * 4
            guard base + 3 < state.boxes.count else { break }
            let width = state.boxes[base + 2]
            guard width > 0 else { continue }
            let covered = max(0, webView.bounds.height - state.viewportHeight)
            let y = state.boxes[base + 1] - state.scrollY + covered
            let height = state.boxes[base + 3]
            let pageRect = NSRect(x: state.boxes[base], y: y, width: width, height: height)
            let rect = webView.isFlipped
                ? pageRect
                : NSRect(x: pageRect.minX, y: webView.bounds.height - pageRect.maxY, width: width, height: height)
            if let last = lines.last, abs(last.minY - rect.minY) < 1, abs(last.height - rect.height) < 1 {
                lines[lines.count - 1] = last.union(rect)
            } else {
                lines.append(rect)
            }
        }
        return lines
    }
}

/// The page with the system find bar above it while the bar shows, both under the toolbar.
final class EditorContainer: WebViewContainer, NSTextFinderBarContainer {
    var onFindBarVisibilityChange: (Bool) -> Void = { _ in }

    var findBarView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            needsLayout = true
        }
    }

    var isFindBarVisible = false {
        didSet {
            guard isFindBarVisible != oldValue else { return }
            if let findBarView {
                if isFindBarVisible { addSubview(findBarView) } else { findBarView.removeFromSuperview() }
            }
            needsLayout = true
            onFindBarVisibilityChange(isFindBarVisible)
        }
    }

    func contentView() -> NSView? { webView }

    func findBarViewDidChangeHeight() {
        needsLayout = true
    }

    /// The finder gives the bar its height; until it has, the bar's own fitting height.
    private var findBarHeight: CGFloat {
        guard isFindBarVisible, let findBarView else { return 0 }
        return findBarView.frame.height > 0 ? findBarView.frame.height : findBarView.fittingSize.height
    }

    override var coveredTop: CGFloat { topInset + findBarHeight }

    override func layout() {
        if isFindBarVisible, let findBarView {
            findBarView.frame = NSRect(x: 0, y: topInset, width: bounds.width, height: findBarHeight)
        }
        super.layout()
    }
}
