import AppKit
import UniformTypeIdentifiers
import WebKit

/// The web view behaving as a Mac text view: Undo and Redo in the Edit menu drive the page's own history, the
/// context menu offers only what applies to a note.
final class EditorWebView: WKWebView {
    weak var controller: EditorController?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.pageDidMoveToWindow()
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

    // MARK: Images

    // Images dropped become files of the notes folder, linked from the note; everything else is the page's to
    // take. Pasted images reach the app from the page, which hears the paste.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        carriesImages(sender) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        carriesImages(sender) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let location = convert(sender.draggingLocation, from: nil)
        let point = CGPoint(x: location.x, y: isFlipped ? location.y : bounds.height - location.y)
        if carriesImages(sender), controller?.insertImages(PastedImages.sources(on: sender.draggingPasteboard), at: point) == true { return true }
        return super.performDragOperation(sender)
    }

    private func carriesImages(_ sender: any NSDraggingInfo) -> Bool {
        controller?.isEditable == true && sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ])
    }

    // MARK: Undo

    /// WebKit records its own steps for what is typed on the undo manager it is given. The page keeps its own
    /// history instead, so WebKit gets one of its own, and the window's stays for the app's actions.
    private let pageUndoManager = UndoManager()

    override var undoManager: UndoManager? { pageUndoManager }

    /// The window's undo manager, which holds the app's actions such as New Note and Delete.
    private var windowUndoManager: UndoManager? { window?.undoManager }

    // The page's history comes first, as a text view's does; once it is spent, Undo reaches the window's.
    @objc func undo(_ sender: Any?) {
        if controller?.caret.canUndo == true {
            controller?.undo()
        } else {
            windowUndoManager?.undo()
        }
    }

    @objc func redo(_ sender: Any?) {
        if controller?.caret.canRedo == true {
            controller?.redo()
        } else {
            windowUndoManager?.redo()
        }
    }

    // WebKit answers Command-Z itself, from its own undo manager, before the Edit menu sees the key, so the key
    // comes here, where the page's history and then the window's are asked in turn.
    // AppKit offers a key equivalent to every view in the window, so only a page with the keyboard takes it; a
    // search field or a folder's name being edited undoes its own typing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard window?.firstResponder === self, event.charactersIgnoringModifiers?.lowercased() == "z" else {
            return super.performKeyEquivalent(with: event)
        }
        switch modifiers {
        case .command:
            undo(nil)
            return true
        case [.command, .shift]:
            redo(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let caret = controller?.caret ?? CaretState()
        switch item.action {
        case #selector(undo(_:)):
            let title = caret.canUndo ? String(localized: "Undo") : windowUndoManager?.undoMenuItemTitle
            (item as? NSMenuItem)?.title = title ?? String(localized: "Undo")
            return caret.canUndo || windowUndoManager?.canUndo == true
        case #selector(redo(_:)):
            let title = caret.canRedo ? String(localized: "Redo") : windowUndoManager?.redoMenuItemTitle
            (item as? NSMenuItem)?.title = title ?? String(localized: "Redo")
            return caret.canRedo || windowUndoManager?.canRedo == true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Context menu

    /// WebKit's own items that mean nothing in a note: page navigation, and opening or saving what links and
    /// images point at, which the page never does (a link opens with Command-click). WebKit names them only in
    /// a private header, so were it to rename one, that item would simply stay.
    private static let unwantedItems: Set<String> = [
        "WKMenuItemIdentifierOpenLink",
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

    /// Submenus for rich text, identified by what their items do: a note is markdown, which has no fonts,
    /// colours or vertical layout.
    private static let richTextActions: Set<Selector> = [
        #selector(NSFontManager.orderFrontFontPanel(_:)),
        #selector(NSTextView.changeLayoutOrientation(_:)),
    ]

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items {
            let isUnwanted = Self.unwantedItems.contains(item.identifier?.rawValue ?? "")
            let isRichText = item.submenu?.items.contains { $0.action.map(Self.richTextActions.contains) ?? false } ?? false
            if isUnwanted || isRichText { menu.removeItem(item) }
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
