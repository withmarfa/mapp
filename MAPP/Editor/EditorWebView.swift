import AppKit
import WebKit

/// The web view behaving as a Mac text view: Undo and Redo in the Edit menu drive the page's own history, the
/// context menu offers only what applies to a note, and the page scrolls under the toolbar.
final class EditorWebView: WKWebView {
    weak var controller: EditorController?

    /// How far the window's toolbar and anything else above the note overlap the page.
    var topInset: CGFloat = 0 {
        didSet { if topInset != oldValue { needsLayout = true } }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { controller?.isFocused = true }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { controller?.isFocused = false }
        return resigned
    }

    override func layout() {
        super.layout()
        let insets = NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        if obscuredContentInsets.top != insets.top { obscuredContentInsets = insets }
    }

    // MARK: Undo

    // The page keeps its own history, which WebKit's undo manager never sees, so the menu asks the page.
    @objc func undo(_ sender: Any?) {
        controller?.undo()
    }

    @objc func redo(_ sender: Any?) {
        controller?.redo()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): controller?.caret.canUndo ?? false
        case #selector(redo(_:)): controller?.caret.canRedo ?? false
        default: super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Context menu

    /// WebKit's own items that mean nothing in a note: page navigation, and opening or saving what links and
    /// images point at.
    private static let unwantedItems: Set<String> = [
        "WKMenuItemIdentifierReload",
        "WKMenuItemIdentifierGoBack",
        "WKMenuItemIdentifierGoForward",
        "WKMenuItemIdentifierOpenLinkInNewWindow",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierOpenImageInNewWindow",
        "WKMenuItemIdentifierDownloadImage",
        "WKMenuItemIdentifierOpenFrameInNewWindow",
        "WKMenuItemIdentifierOpenMediaInNewWindow",
        "WKMenuItemIdentifierDownloadMedia",
    ]

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items where Self.unwantedItems.contains(item.identifier?.rawValue ?? "") {
            menu.removeItem(item)
        }
        // Removing items can leave two separators together, or one at an end.
        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.numberOfItems - 1) }
        var index = 1
        while index < menu.numberOfItems {
            if menu.items[index].isSeparatorItem, menu.items[index - 1].isSeparatorItem {
                menu.removeItem(at: index)
            } else {
                index += 1
            }
        }
    }
}
