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
                if let url = library.fileURL(for: id) {
                    FileItemContent(url: url)
                        .onAppear { editor.close() }
                } else {
                    ContentUnavailableView("File Unavailable", systemImage: "doc.badge.ellipsis")
                        .onAppear { editor.close() }
                }
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
        editor.focus()
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
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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

/// One note as a formatted page. The same editor shows each note in turn, so moving between notes loads
/// text into a page that is already running.
struct NotePage: View {
    @CurrentLibrary private var library
    let item: Item
    @Bindable var editor: EditorController
    @StoredPageStyle private var style
    let headerDrafts: DetailsPresentation

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                NoteEditor(controller: editor, topInset: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(.container, edges: .top)
                if item.state == .trashed {
                    ScrollingPageHeader(editor: editor) {
                        DeletedNoteBanner(id: item.id)
                    }
                } else {
                    ScrollingPageHeader(editor: editor) {
                        VStack(spacing: 0) {
                            if case .conflicted(let copy?, _) = item.sync {
                                SavedAsCopyBanner(copy: copy)
                            }
                            ItemPageHeader(item: item, drafts: headerDrafts, onStartWriting: { editor.focus() })
                                .id(item.id)
                                .padding(.horizontal, style.horizontalInset(for: proxy.size.width))
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileImporter(isPresented: $editor.isChoosingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            editor.focus()
            editor.insertImages(urls.map(PastedImages.Source.file))
        }
        .onChange(of: style, initial: true) { editor.setStyle(style) }
        .onChange(of: item.id, initial: true) { editor.load(item) }
        // Every change to the note takes a new version; the editor takes in only one to its text or its state. A
        // Marfa server that keeps its own text over the person's changes the text without a new version.
        .onChange(of: item.version) { editor.noteChanged(item) }
        .onChange(of: library.body(of: item.id)) { editor.noteChanged(item) }
    }
}

/// WebKit owns scrolling. Its public script bridge supplies the offset for the native controls, while the
/// page reserves their measured height. No second scroll view or copy of the item's data is involved.
private struct ScrollingPageHeader<Content: View>: View {
    let editor: EditorController
    @ViewBuilder let content: () -> Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollingHeader(webView: editor.webView, content: content)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                height = $0
                editor.setHeaderHeight($0)
            }
            .offset(y: -editor.scrollOffset)
            .frame(height: max(0, height - editor.scrollOffset), alignment: .top)
            .clipped()
            .padding(.top, editor.findBarHeight)
            .accessibilityHidden(editor.isHeaderScrolledAway)
            .allowsHitTesting(!editor.isHeaderScrolledAway)
    }
}

/// The server kept another device's text over the person's and saved theirs as a copy, which the page now shows
/// beside the text the server kept.
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
        .font(.callout)
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
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
