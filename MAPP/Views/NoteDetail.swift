import SwiftUI
import UniformTypeIdentifiers

struct NoteDetail: View {
    @CurrentLibrary private var library
    let browser: Browser
    let editor: EditorController
    let details: DetailsPresentation

    var body: some View {
        if browser.selection.count > 1 {
            ContentUnavailableView {
                Label("^[\(browser.selection.count) item](inflect: true) selected", systemImage: PlaceSymbol.name(of: browser.item, in: library.catalogue))
            } description: {
                Text("Choose a single item to read or edit it.")
            }
            .background(.windowBackground)
            .accessibilityIdentifier("MultipleSelectionPrompt")
            .onAppear { editor.close() }
        } else if let id = browser.selection.first, let item = library.item(id) {
            if item.isFile {
                ItemFileView(id: id) { browser.fileFetched(id, at: $0) }
                    .onAppear { editor.close() }
            } else {
                NotePage(item: item, editor: editor, headerDrafts: details)
                    .onAppear(perform: grantFocusRequest)
                    .onChange(of: browser.focusRequest, grantFocusRequest)
            }
        } else {
            UnselectedItemContent(symbol: PlaceSymbol.name(of: browser.item, in: library.catalogue), hasItems: !browser.items(in: library).isEmpty)
                // The page no longer shows the note it had, so that note is left.
                .onAppear { editor.close() }
        }
    }

    /// The page takes the keyboard when asked, once it shows; the editor holds the request until its page is ready.
    private func grantFocusRequest() {
        guard let request = browser.focusRequest, request == .page || request == .title else { return }
        browser.focusRequest = nil
        editor.focus(browser.selection.first, onTitle: request == .title)
    }
}

/// The symbol of the place the list shows, for the quiet states of the detail column. Sidebar places and types
/// keep their own symbols; this only names the place a person is in.
private enum PlaceSymbol {
    static func name(of place: SidebarItem, in catalogue: Catalogue) -> String {
        switch place {
        case .inbox: "tray"
        case .recents: "clock"
        case .allNotes: "note.text"
        case .favorites, .favoriteItem: "heart"
        case .sources, .source: "antenna.radiowaves.left.and.right"
        case .collections: "square.stack"
        case .collection: "square.stack"
        case .itemType(let id): TypeSymbol.name(for: TypeID(id), in: catalogue)
        case .files: "doc"
        case .view: SidebarPlace.viewSymbol
        case .recentlyDeleted: "trash"
        }
    }
}

/// What the page says when no item is chosen: quiet, with the place's symbol, and nothing at all while the place
/// holds nothing to choose, since the list says that.
private struct UnselectedItemContent: View {
    let symbol: String
    let hasItems: Bool

    var body: some View {
        VStack {
            if hasItems {
                ContentUnavailableView {
                    Label {
                        Text("No Item Selected").accessibilityIdentifier("SelectItemPrompt")
                    } icon: {
                        Image(systemName: symbol)
                    }
                } description: {
                    Text("Choose an item from the list to read or edit it.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}

#Preview("Items with no selection") {
    UnselectedItemContent(symbol: "checkmark.circle", hasItems: true)
        .frame(width: 600, height: 500)
}

#Preview("Empty item collection") {
    UnselectedItemContent(symbol: "tray", hasItems: false)
        .frame(width: 600, height: 500)
}

/// One note as a formatted page, with the item's header drawn by the page above the text. The same editor shows
/// each note in turn, so moving between notes loads text into a page that is already running.
struct NotePage: View {
    @CurrentLibrary private var library
    let item: Item
    @Bindable var editor: EditorController
    @StoredPageStyle private var style
    let headerDrafts: DetailsPresentation
    @State private var bannerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // The page runs under the toolbar and any banner, so it starts below them and scrolls beneath.
                NoteEditor(controller: editor, topInset: proxy.safeAreaInsets.top + bannerHeight)
                    .ignoresSafeArea(.container, edges: .top)
                    .modifier(ItemPageHeader(item: item, editor: editor, drafts: headerDrafts, containerTop: proxy.safeAreaInsets.top))
                VStack(spacing: 0) {
                    if item.state == .trashed {
                        DeletedNoteBanner(id: item.id)
                    } else if case .conflicted(let copy?, _) = item.sync {
                        SavedAsCopyBanner(copy: copy)
                    } else if let problem = item.problem, problem.withholdsText {
                        UnreadableNoteBanner(message: problem.message)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bannerHeight = $0 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editor.linkRequest, onDismiss: {
            // Escape closes the sheet without answering, so the page's command is answered here as declined.
            editor.cancelLinkRequest()
            editor.focus(item.id)
        }) { request in
            NoteLinkPicker(editor: editor, note: request.note)
        }
        .fileImporter(isPresented: $editor.isChoosingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            editor.focus(item.id)
            editor.insertImages(urls.map(PastedImages.Source.file))
        }
        .onChange(of: style, initial: true) { _, style in editor.setStyle(style) }
        .onChange(of: item.id, initial: true) { _, id in
            guard let item = library.item(id) else { return }
            // Returning from Settings reattaches the same editor without resetting its scroll position or undo.
            editor.select(item)
        }
        // The editor takes in only a change to the note's text or to whether it can be written in. A change the
        // server has taken takes a new version, but the copy shows a delete, a recovery or a problem before then,
        // and a server that keeps its own text over the person's changes the text without one. The action may run
        // on an earlier copy of this view, so the note is read as it is now.
        .onChange(of: item.version) { noteChanged() }
        .onChange(of: item.isWritable) { noteChanged() }
        .onChange(of: library.body(of: item.id)) { noteChanged() }
    }

    private func noteChanged() {
        if let item = library.item(item.id) { editor.noteChanged(item) }
    }
}

/// The server kept another device's text over the person's and saved theirs as a copy, which the page now shows
/// beside the text the server kept. It stays above the page while the note scrolls.
private struct SavedAsCopyBanner: View {
    @Environment(\.openWindow) private var openWindow
    let copy: ItemID

    var body: some View {
        HStack {
            Text("This item changed elsewhere, so your changes were saved as a copy.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Copy") { openWindow(value: copy) }
        }
        .interfaceFont(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// The library could not read this note, so the page is empty and read-only. This says why, so an empty page is not
/// taken for text the person lost.
private struct UnreadableNoteBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .interfaceFont(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
    }
}

/// Deleted notes cannot be edited; this says so and offers the way back, as Notes does.
private struct DeletedNoteBanner: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let id: ItemID

    var body: some View {
        HStack {
            Text("Recently deleted notes can’t be edited.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Recover") { library.recover([id], undoManager: undoManager) }
        }
        .interfaceFont(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
