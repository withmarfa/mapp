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

    init(
        library: (any ItemLibrary)?, ids: Set<ItemID>, hasBrowser: Bool, pageItem: ItemID?, pageIsEditable: Bool = true,
        showsSource: Bool = false, fileURL: URL? = nil
    ) {
        self.library = library
        self.ids = ids
        self.hasBrowser = hasBrowser
        self.pageItem = pageItem
        self.pageIsEditable = pageIsEditable
        self.showsSource = showsSource
        self.fileURL = fileURL
    }

    /// The context of a window: its selection, its browser if it has one, and the editor it hands to its menus.
    /// `fileURL` is the file known to the window when the browser has none for the item.
    init(library: (any ItemLibrary)?, ids: Set<ItemID>, browser: Browser?, editor: EditorController?, fileURL: URL? = nil) {
        let single = ids.count == 1 ? ids.first : nil
        self.init(
            library: library, ids: ids, hasBrowser: browser != nil,
            pageItem: Self.pageItem(showsPage: browser?.showsPage ?? true, editorHasNote: editor?.hasNote == true, noteID: editor?.noteID),
            pageIsEditable: editor?.isEditable ?? false, showsSource: editor?.caret.sourceMode ?? false,
            fileURL: single.flatMap { browser?.fileURL(of: $0) } ?? fileURL)
    }

    /// The item whose page is in front: the editor's, only while the page is what the window shows and the editor
    /// has it ready. The editor stays mounted behind a collection, an index and Settings, and still holds its note.
    static func pageItem(showsPage: Bool, editorHasNote: Bool, noteID: ItemID?) -> ItemID? {
        showsPage && editorHasNote ? noteID : nil
    }

    /// The one selected item.
    var item: Item? { ids.count == 1 ? ids.first.flatMap { library?.item($0) } : nil }

    /// The note on the page, which Print, Export, the source view and Add Attachment act on.
    var visibleNote: Item? {
        guard let item, !item.isFile, item.id == pageItem else { return nil }
        return item
    }

    /// The visible note when it can be written to.
    var editableNote: Item? { visibleNote.flatMap { $0.isWritable && pageIsEditable ? $0 : nil } }

    var originalAddress: URL? { item.flatMap { library?.originalAddress(of: $0) } }

    var browserTarget: BrowserTarget? { item.flatMap { item in library?.browserTarget(of: item, fetchedFile: fileURL) } }
}

/// The commands on one item or selection that the toolbar's More menu and the menu bar both offer. Each is defined
/// once here: its title, symbol, shortcut, when it applies and what it does. A menu shows every one of them and
/// dims the ones that do not apply, so the two menus never differ in what they offer or when.
enum ItemCommand: CaseIterable {
    case openInNewWindow, openOriginal, openInBrowser, addAttachment, toggleSource, print, exportPDF

    func title(in context: ItemCommandContext) -> LocalizedStringResource {
        switch self {
        case .openInNewWindow: "Open in New Window"
        case .openOriginal: "Open Original"
        case .openInBrowser: "Open in Browser"
        case .addAttachment: "Add Attachment…"
        case .toggleSource: context.showsSource ? "Show Formatted Text" : "Show Markdown Source"
        case .print: "Print…"
        case .exportPDF: "Export as PDF…"
        }
    }

    var systemImage: String {
        switch self {
        case .openInNewWindow: "macwindow"
        case .openOriginal, .openInBrowser: "safari"
        case .addAttachment: "paperclip"
        case .toggleSource: "doc.plaintext"
        case .print: "printer"
        case .exportPDF: "doc.richtext"
        }
    }

    /// The key the menu bar binds. The toolbar's menu binds none, so a key is never registered twice.
    var shortcut: KeyboardShortcut? {
        switch self {
        case .openInNewWindow: KeyboardShortcut("o")
        case .addAttachment: KeyboardShortcut("a", modifiers: [.command, .shift])
        case .print: KeyboardShortcut("p")
        case .openOriginal, .openInBrowser, .toggleSource, .exportPDF: nil
        }
    }

    func isEnabled(in context: ItemCommandContext) -> Bool {
        guard context.library != nil else { return false }
        return switch self {
        case .openInNewWindow: context.hasBrowser && !context.ids.isEmpty
        case .openOriginal: context.originalAddress != nil
        case .openInBrowser: context.browserTarget != nil
        case .addAttachment: context.editableNote != nil
        case .toggleSource, .print, .exportPDF: context.visibleNote != nil
        }
    }

    /// Does the command. `editor` is the page's, for the commands that act on it; `openWindow` opens an item's window.
    func perform(in context: ItemCommandContext, editor: EditorController?, openWindow: @escaping (ItemID) -> Void) {
        guard isEnabled(in: context), let library = context.library else { return }
        switch self {
        case .openInNewWindow: ItemWindows.open(library.idsForWindows(context.ids), opening: openWindow)
        case .openOriginal: context.originalAddress.map { _ = NSWorkspace.shared.open($0) }
        case .openInBrowser:
            if let item = context.item, let target = context.browserTarget { BrowserOpening.open(target, for: item) }
        case .addAttachment: editor?.isChoosingImages = true
        case .toggleSource: editor.map { $0.setSourceMode(!$0.caret.sourceMode) }
        case .print: editor?.printNote()
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
    var bindsShortcut = false

    var body: some View {
        Button(command.title(in: context), systemImage: command.systemImage) {
            command.perform(in: context, editor: editor) { openWindow(value: $0) }
        }
        .keyboardShortcut(bindsShortcut ? command.shortcut : nil)
        .disabled(!command.isEnabled(in: context))
    }
}
