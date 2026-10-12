import SwiftUI
import UniformTypeIdentifiers

struct NoteDetail: View {
    @CurrentLibrary private var library
    let browser: Browser
    let editor: EditorController
    let details: DetailsPresentation

    var body: some View {
        if browser.selection.count > 1 {
            ContentUnavailableView("^[\(browser.selection.count) item](inflect: true) selected", systemImage: "note.text")
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
            UnselectedItemContent(hasItems: !browser.items(in: library).isEmpty)
                // The page no longer shows the note it had, so that note is left.
                .onAppear { editor.close() }
        }
    }

    /// The page takes the keyboard when asked, once it shows; the editor holds the request until its page is ready.
    private func grantFocusRequest() {
        guard browser.focusRequest == .page else { return }
        browser.focusRequest = nil
        editor.focus(browser.selection.first)
    }
}

private struct UnselectedItemContent: View {
    let hasItems: Bool

    var body: some View {
        VStack {
            if hasItems {
                Text("Select an item")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("SelectItemPrompt")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}

#Preview("Items with no selection") {
    UnselectedItemContent(hasItems: true)
        .frame(width: 600, height: 500)
}

#Preview("Empty item collection") {
    UnselectedItemContent(hasItems: false)
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
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bannerHeight = $0 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileImporter(isPresented: $editor.isChoosingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            editor.focus(item.id)
            editor.insertImages(urls.map(PastedImages.Source.file))
        }
        .onChange(of: style, initial: true) { editor.setStyle(style) }
        .onChange(of: item.id, initial: true) {
            // Returning from Settings reattaches the same editor without resetting its scroll position or undo.
            if editor.noteID == item.id { editor.noteChanged(item) }
            else { editor.load(item) }
        }
        // Every change to the note takes a new version; the editor takes in only one to its text or its state. A
        // Marfa server that keeps its own text over the person's changes the text without a new version.
        .onChange(of: item.version) { editor.noteChanged(item) }
        .onChange(of: library.body(of: item.id)) { editor.noteChanged(item) }
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
