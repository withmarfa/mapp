import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ItemDetail: View {
    @CurrentLibrary private var library
    let browser: Browser
    let editor: EditorController
    let details: DetailsPresentation
    /// Whether the page backs the window's toolbar with glass. The modal draws its own toolbar and has no need.
    var backsToolbar = true
    /// Whether the page has its corner. A modal's page has none.
    var showsCorner = true
    /// The item to show in place of the selection's, which the column beside a layout follows once the selection has
    /// rested (`BesideSettler`). Nil shows the selection's.
    var itemID: ItemID?

    private var shownID: ItemID? { itemID ?? browser.selection.first }

    var body: some View {
        if browser.selection.count > 1 {
            EmptyState(title: Text("^[\(browser.selection.count) item](inflect: true) selected"),
                       detail: Text("Choose one item to read or edit it."), actions: { EmptyView() })
                .accessibilityIdentifier("MultipleSelectionPrompt")
                .onAppear { editor.close() }
        } else if let id = shownID, let item = library.item(id) {
            if library.pageLayout(of: item) != .text {
                FileItemPage(item: item, drafts: details, open: { [editor] in editor.onOpenItem($0) }, onResolved: { browser.fileFetched(id, at: $0) }, backsToolbar: backsToolbar)
                    .itemCorner(item, editor: nil, details: details, isShown: showsCorner)
                    // An editor that holds the file has left its page for it already (`EditorController.open`).
                    .onAppear { if editor.heldItemID != id { editor.close() } }
            } else {
                ItemPage(item: item, editor: editor, headerDrafts: details, backsToolbar: backsToolbar)
                    .itemCorner(item, editor: editor, details: details, isShown: showsCorner)
                    .onAppear(perform: grantFocusRequest)
                    .onChange(of: browser.focusRequest, grantFocusRequest)
                    .onChange(of: itemID, grantFocusRequest)
            }
        } else {
            Group {
                if browser.listDrawsNoItem(in: library) {
                    ListEmptyState(browser: browser)
                } else {
                    EmptyState("No Item Selected")
                }
            }
            // The page no longer shows the item it had, so that item is left.
            .onAppear { editor.close() }
        }
    }

    /// The page takes the keyboard when asked, once it shows; the editor holds the request until its page is ready.
    private func grantFocusRequest() {
        guard let request = browser.focusRequest, request == .page || request == .title else { return }
        // A column still on the item before waits for the one the selection moved to.
        if let itemID, itemID != browser.selection.first { return }
        browser.focusRequest = nil
        let caret = request == .page ? browser.focusCaret : nil
        browser.focusCaret = nil
        editor.focus(shownID, onTitle: request == .title, caret: caret)
    }
}

/// One item as a formatted page, with the item's header drawn by the page above the text. The same editor shows
/// each item in turn, so moving between items loads text into a page that is already running.
struct ItemPage: View {
    @CurrentLibrary private var library
    let item: Item
    @Bindable var editor: EditorController
    @StoredPageStyle private var style
    @Environment(ShortcutBindings.self) private var shortcuts: ShortcutBindings?

    /// The keys the Format commands have now, which the page answers as the menu does.
    private var formatShortcuts: [Format: Shortcut?] {
        guard let shortcuts else { return [:] }
        return Dictionary(uniqueKeysWithValues: Format.allCases.map { ($0, shortcuts.shortcut(for: .format($0))) })
    }
    let headerDrafts: DetailsPresentation
    /// Whether the page backs the toolbar with glass while text is under it. A window whose toolbar draws its own
    /// background has no need.
    var backsToolbar = true
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsToolbarBackground = true
    @Environment(\.topRowSpace) private var topRow
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GeometryReader { proxy in
            // The toolbar's height as the top row knows it, which holds while full screen hides the toolbar.
            let toolbarHeight = max(proxy.safeAreaInsets.top, topRow.lineHeight)
            ZStack(alignment: .top) {
                // The page runs under the toolbar and scrolls beneath it. It starts a little above the toolbar's lower edge
                // (`TopRowMetrics.pageLift`), where the boards put the kicker. Its notice is drawn by the page, above the head.
                ItemEditor(controller: editor, topInset: toolbarHeight - TopRowMetrics.pageLift)
                    .ignoresSafeArea(.container, edges: .top)
                    .modifier(ItemPageHeader(item: item, editor: editor, drafts: headerDrafts))
                ToolbarBand(toolbarHeight: toolbarHeight, isShown: backsToolbar && showsToolbarBackground && editor.isContentUnderToolbar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editor.linkRequest, onDismiss: {
            // Escape closes the sheet without answering, so the page's command is answered here as declined.
            editor.cancelLinkRequest()
            editor.focus(item.id)
        }) { request in
            ItemLinkPicker(editor: editor, itemID: request.itemID)
        }
        .sheet(item: $editor.webLinkRequest, onDismiss: { editor.focus(item.id) }) { request in
            WebLinkSheet(editor: editor, request: request)
        }
        .quickLookPreview(
            Binding {
                editor.quickLook?.current
            } set: { url in
                if url == nil { editor.dismissQuickLook() } else { editor.quickLook?.current = url }
            },
            in: editor.quickLook?.urls ?? []
        )
        // The panel is shared by every window, so another window taking it closes this one's request.
        .onReceive(NotificationCenter.default.publisher(for: .quickLookTaken)) { note in
            if (note.object as? EditorController) !== editor { editor.dismissQuickLook() }
        }
        .fileImporter(isPresented: $editor.isChoosingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            editor.focus(item.id)
            editor.insertImages(urls.map(PastedImages.Source.file))
        }
        .onChange(of: style, initial: true) { _, style in editor.setStyle(style) }
        .onChange(of: formatShortcuts, initial: true) { _, shortcuts in editor.setFormatShortcuts(shortcuts) }
        .onChange(of: item.id, initial: true) { old, id in
            if old != id { headerDrafts.headerScrolled(nil, for: old) }
            editor.onNoticeAction = noticeAction
            guard let item = library.item(id) else { return }
            // Returning from Settings reattaches the same editor without resetting its scroll position or undo.
            editor.select(item)
            feedHeaderScroll()
        }
        .onChange(of: PageNotice.of(item), initial: true) { _, notice in editor.setNotice(notice) }
        .onChange(of: editor.isHeaderScrolledAway) { feedHeaderScroll() }
        .onChange(of: editor.pageItemID) { feedHeaderScroll() }
        .onChange(of: item.title) { feedHeaderScroll() }
        .onDisappear { headerDrafts.headerScrolled(nil, for: item.id) }
        // The editor takes in only a change to the item's text or to whether it can be written in. A change the
        // server has taken takes a new version, but the copy shows a delete, a recovery or a problem before then,
        // and a server that keeps its own text over the person's changes the text without one. The action may run
        // on an earlier copy of this view, so the item is read as it is now.
        .onChange(of: item.version) { itemChanged() }
        .onChange(of: item.allows(.text)) { itemChanged() }
        .onChange(of: library.body(of: item.id)) { itemChanged() }
    }

    /// Tells the window whether this item's head is away. The editor may still hold the item before, whose head it
    /// reports on, so only its own item's counts.
    private func feedHeaderScroll() {
        let away = editor.pageItemID == item.id && editor.isHeaderScrolledAway
        headerDrafts.headerScrolled(
            away ? ScrolledHead(item: item.id, title: item.title, typeIcon: library.catalogue.icon(for: item.type)) : nil, for: item.id)
    }

    /// What the page's notice asks for the item it names, if the item still gives that notice.
    private var noticeAction: (ItemID, String) -> Void {
        let library = library, undoManager = undoManager, openWindow = openWindow
        return { [weak editor] id, kind in
            guard let editor, editor.isShowing(id), let item = library.item(id),
                  let notice = PageNotice.of(item), notice.kind.rawValue == kind, let action = notice.action else { return }
            action.run(for: id, in: library, undoManager: undoManager, openWindow: openWindow)
        }
    }

    private func itemChanged() {
        if let item = library.item(item.id) { editor.itemChanged(item) }
    }
}
