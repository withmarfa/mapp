import SwiftUI

/// What an item command reads to decide whether it applies: the items it would act on and the page in front. The
/// toolbar's More menu and the menu bar build one each from what they can see, so the same command answers the same way
/// in both.
struct ItemCommandContext {
    /// Nil while no library is open.
    let library: (any ItemLibrary)?
    /// Everything selected, files too.
    let ids: Set<ItemID>
    /// Whether a main window's browser is in front; an item's own window has none, and opens no more windows from here.
    let hasBrowser: Bool
    /// The item whose page the editor shows and has ready: nil while a collection, an index or Settings is showing
    /// (`Browser.showsPage`), and while no page is loaded.
    let pageItem: ItemID?
    let pageIsEditable: Bool
    let showsSource: Bool
    /// Where the single selected item's file is, once known.
    let fileURL: URL?
    /// The window's browser, which Quick Look acts through.
    let browser: Browser?
    /// The Reader and Original switch of the page in front, when it has an article.
    let pageLook: PageLookSwitch?
    /// Whether an item's page is what the window shows, which Focus and the formats bar belong to.
    let showsPage: Bool
    /// The window's presentation, which holds Focus and the formats bar.
    let details: DetailsPresentation?

    init(
        library: (any ItemLibrary)?, ids: Set<ItemID>, hasBrowser: Bool, pageItem: ItemID?, pageIsEditable: Bool = true,
        showsSource: Bool = false, fileURL: URL? = nil, browser: Browser? = nil, pageLook: PageLookSwitch? = nil,
        showsPage: Bool = true, details: DetailsPresentation? = nil
    ) {
        self.library = library
        self.ids = ids
        self.hasBrowser = hasBrowser
        self.pageItem = pageItem
        self.pageIsEditable = pageIsEditable
        self.showsSource = showsSource
        self.fileURL = fileURL
        self.browser = browser
        self.pageLook = pageLook
        self.showsPage = showsPage
        self.details = details
    }

    /// The context of a window: its selection, its browser if it has one, and the editor it hands to its menus.
    /// `fileURL` is the file known to the window when the browser has none for the item.
    init(
        library: (any ItemLibrary)?, ids: Set<ItemID>, browser: Browser?, editor: EditorController?, details: DetailsPresentation?,
        fileURL: URL? = nil
    ) {
        let single = ids.count == 1 ? ids.first : nil
        self.init(
            library: library, ids: ids, hasBrowser: browser != nil,
            pageItem: Self.pageItem(showsPage: browser?.showsPage ?? true, editorHasItem: editor?.hasItem == true, pageItemID: editor?.pageItemID),
            pageIsEditable: editor?.isEditable ?? false,
            fileURL: single.flatMap { browser?.fileURL(of: $0) } ?? fileURL, browser: browser,
            pageLook: browser?.showsPage != false ? details?.pageLook : nil,
            showsPage: browser?.showsPage ?? true, details: details)
    }

    /// The item whose page is in front: the editor's, only while the page is what the window shows and the editor
    /// has it ready. The editor stays mounted behind a collection, an index and Settings, and still holds its item.
    static func pageItem(showsPage: Bool, editorHasItem: Bool, pageItemID: ItemID?) -> ItemID? {
        showsPage && editorHasItem ? pageItemID : nil
    }

    /// The one selected item, as a header shows it. A command follows that, not the item's version or its text.
    var item: Item? { ids.count == 1 ? ids.first.flatMap { library?.headerItem($0) } : nil }

    /// The item on the page, which Print, Export, the source view and Add Attachment act on.
    var visibleItem: Item? {
        guard let item, !item.isFile, item.id == pageItem else { return nil }
        return item
    }

    /// The visible item when it can be written to.
    var editableItem: Item? { visibleItem.flatMap { $0.allows(.text) && pageIsEditable ? $0 : nil } }

    /// The one item whose page the window shows, which Focus is on: any kind of item, a file included.
    var focusItem: Item? { showsPage ? item : nil }

    /// Whether the page is in a modal, which has no corner, so no Focus and no formats.
    var hidesCorner: Bool { browser?.isModalPresented == true }

    var originalAddress: URL? { item.flatMap { library?.originalAddress(of: $0) } }

    var browserTarget: BrowserTarget? { item.flatMap { item in library?.browserTarget(of: item, fetchedFile: fileURL) } }
}

/// The commands on one item or selection that the toolbar's More menu and the menu bar both offer. Each is defined
/// once here: its title, symbol, shortcut, when it applies and what it does. A menu shows every one of them and
/// dims the ones that do not apply, so the two menus never differ in what they offer or when.
enum ItemCommand: CaseIterable {
    case open, openAsModal, openAsFullPage, quickLook, openInNewWindow, openOriginal, openInBrowser, copyLink, addAttachment, toggleSource, toggleReader, toggleFormats, toggleFocus, print, exportPDF

    /// The menu bar group also determines where ⌘K lists the command.
    var paletteGroup: PaletteSections.CommandGroup {
        switch self {
        case .copyLink, .addAttachment: .edit
        case .toggleSource, .toggleReader, .toggleFormats, .toggleFocus: .view
        case .open, .openAsModal, .openAsFullPage, .quickLook, .openInNewWindow, .openOriginal, .openInBrowser, .print, .exportPDF: .file
        }
    }

    /// `sourceMode` is the page's, read by the button that shows it. Nil uses `context.showsSource`, so building a
    /// context for a menu does not follow the caret.
    func title(in context: ItemCommandContext, sourceMode: Bool? = nil) -> LocalizedStringResource {
        switch self {
        case .open: "Open"
        case .openAsModal: ItemOpening.modal.commandTitle
        case .openAsFullPage: ItemOpening.fullPage.commandTitle
        case .quickLook: "Quick Look"
        case .openInNewWindow: "Open in New Window"
        case .openOriginal: "Open Original"
        case .openInBrowser: "Open in Browser"
        case .copyLink: "Copy Link"
        case .addAttachment: "Add Attachment…"
        case .toggleSource: (sourceMode ?? context.showsSource) ? "Show Formatted Text" : "Show Markdown Source"
        case .toggleReader: context.pageLook?.mode == .original ? "Show Reader" : "Show Original"
        case .toggleFormats: context.details?.isFormatsOpen(on: context.visibleItem?.id) == true ? "Hide Formats" : "Show Formats"
        case .toggleFocus: context.details?.isFocused(on: context.focusItem?.id) == true ? "Leave Focus" : "Focus"
        case .print: "Print…"
        case .exportPDF: "Export as PDF…"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "arrow.up.right"
        case .openAsModal: ItemOpening.modal.symbol
        case .openAsFullPage: ItemOpening.fullPage.symbol
        case .quickLook: "eye"
        case .openInNewWindow: "macwindow"
        case .openOriginal, .openInBrowser: "safari"
        case .copyLink: "link"
        case .addAttachment: "paperclip"
        case .toggleSource: "doc.plaintext"
        case .toggleReader: "text.page"
        case .toggleFormats: "textformat"
        case .toggleFocus: "arrow.up.left.and.arrow.down.right"
        case .print: "printer"
        case .exportPDF: "doc.richtext"
        }
    }

    /// The command whose key the menu bar binds, which the person can change in Settings. The toolbar's menu binds none, so a
    /// key is never registered twice. Focus is not on ⌃⌘F, which is the system's Full Screen.
    var shortcutCommand: ShortcutCommand {
        switch self {
        case .open: .open
        case .openAsModal: .openAsModal
        case .openAsFullPage: .openAsFullPage
        case .quickLook: .quickLook
        case .openInNewWindow: .openInNewWindow
        case .openOriginal: .openOriginal
        case .openInBrowser: .openInBrowser
        case .copyLink: .copyLink
        case .addAttachment: .addAttachment
        case .toggleSource: .toggleSource
        case .toggleReader: .toggleReader
        case .toggleFormats: .toggleFormats
        case .toggleFocus: .focus
        case .print: .print
        case .exportPDF: .exportPDF
        }
    }

    func isEnabled(in context: ItemCommandContext) -> Bool {
        guard context.library != nil else { return false }
        return switch self {
        case .open: context.hasBrowser && ItemOpening.stored().canOpen(context.ids.count)
        case .openAsModal: context.hasBrowser && ItemOpening.modal.canOpen(context.ids.count)
        case .openAsFullPage: context.hasBrowser && ItemOpening.fullPage.canOpen(context.ids.count)
        case .quickLook, .openInNewWindow: context.hasBrowser && !context.ids.isEmpty
        case .openOriginal: context.originalAddress != nil
        case .openInBrowser: context.browserTarget != nil
        case .copyLink: context.item != nil
        case .addAttachment: context.editableItem != nil
        case .toggleSource, .print, .exportPDF: context.visibleItem != nil
        case .toggleReader: context.pageLook != nil
        case .toggleFormats: context.editableItem != nil && context.details != nil && !context.hidesCorner
        case .toggleFocus: context.focusItem != nil && context.details?.isCustomizingLayout == false && !context.hidesCorner
        }
    }

    /// Does the command. `editor` is the page's, for the commands that act on it; `openWindow` opens an item's window.
    func perform(in context: ItemCommandContext, editor: EditorController?, openWindow: @escaping (ItemID) -> Void) {
        guard isEnabled(in: context), let library = context.library else { return }
        switch self {
        case .open: context.browser?.open(context.ids)
        case .openAsModal: context.browser?.open(context.ids, as: .modal)
        case .openAsFullPage: context.browser?.open(context.ids, as: .fullPage)
        case .quickLook: if let browser = context.browser { Task { await browser.quickLookSelection(in: library) } }
        case .openInNewWindow: ItemWindows.open(library.idsForWindows(context.ids), opening: openWindow)
        case .openOriginal: context.originalAddress.map { _ = NSWorkspace.shared.open($0) }
        case .openInBrowser:
            if let item = context.item, let target = context.browserTarget { BrowserOpening.open(target, for: item) }
        case .copyLink: if let id = context.item?.id { Task { await library.copyLink(of: id) } }
        case .addAttachment: editor?.isChoosingImages = true
        case .toggleSource: editor.map { $0.setSourceMode(!$0.caret.sourceMode) }
        case .toggleReader: context.pageLook.map { $0.choose($0.mode == .reader ? .original : .reader) }
        case .toggleFormats: context.visibleItem.map { context.details?.toggleFormats(on: $0.id) }
        case .toggleFocus: context.focusItem.map { context.details?.toggleFocus(on: $0.id) }
        case .print: editor?.printItem()
        case .exportPDF: editor?.exportPDF()
        }
    }
}

/// A button for an `ItemCommand`. The menu bar binds the command's shortcut (`bindsShortcut`); the toolbar's menu
/// shows the same button without one.
struct ItemCommandButton: View {
    @Environment(\.openWindow) private var openWindow
    let command: ItemCommand
    let context: ItemCommandContext
    let editor: EditorController?
    /// The keys the menu bar binds; the toolbar's menu leaves them to it.
    var shortcuts: ShortcutBindings?

    var body: some View {
        // Only Show Markdown Source reads the caret, and only this button does, so the rest of a menu stays as it was.
        let sourceMode = command == .toggleSource ? editor?.caret.sourceMode : nil
        Button(command.title(in: context, sourceMode: sourceMode), systemImage: command.systemImage) {
            command.perform(in: context, editor: editor) { openWindow(value: $0) }
        }
        .shortcut(command.shortcutCommand, shortcuts)
        .disabled(!command.isEnabled(in: context))
    }
}
