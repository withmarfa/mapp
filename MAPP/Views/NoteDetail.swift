import SwiftUI
import UniformTypeIdentifiers

struct NoteDetail: View {
    @Environment(NoteLibrary.self) private var library
    let browser: Browser
    let editor: EditorController
    let details: DetailsPresentation

    var body: some View {
        let notes = browser.selection.compactMap { library.note($0) }
        if browser.selection.count > 1 {
            ContentUnavailableView("^[\(browser.selection.count) item](inflect: true) selected", systemImage: "note.text")
                .onAppear { editor.close() }
        } else if let id = browser.selection.first, let item = library.item(id), let file = item.file {
            if let url = library.fileURL(for: file.id) {
                FileItemContent(url: url)
                    .onAppear { editor.close() }
            } else {
                ContentUnavailableView("File Unavailable", systemImage: "doc.badge.ellipsis")
                    .onAppear { editor.close() }
            }
        } else if let note = notes.first {
            NotePage(note: note, editor: editor, headerDrafts: details)
                .onAppear(perform: grantFocusRequest)
                .onChange(of: browser.focusRequest, grantFocusRequest)
        } else {
            ContentUnavailableView("No Note Selected", systemImage: "note.text")
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

/// One note as a formatted page. The same editor shows each note in turn, so moving between notes loads
/// text into a page that is already running.
struct NotePage: View {
    @Environment(NoteLibrary.self) private var library
    let note: Note
    @Bindable var editor: EditorController
    @StoredPageStyle private var style
    let headerDrafts: DetailsPresentation

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                NoteEditor(controller: editor, topInset: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(.container, edges: .top)
                if note.isDeleted {
                    ScrollingPageHeader(editor: editor) {
                        DeletedNoteBanner(id: note.id)
                    }
                } else if let item = library.item(note.id) {
                    ScrollingPageHeader(editor: editor) {
                        ItemPageHeader(item: item, drafts: headerDrafts, onStartWriting: { editor.focus() })
                            .id(note.id)
                            .padding(.horizontal, style.horizontalInset(for: proxy.size.width))
                            .padding(.top, 16)
                            .padding(.bottom, 8)
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
        .onChange(of: note.id, initial: true) { editor.load(note) }
        .onChange(of: note.body) { editor.noteChanged(note) }
        .onChange(of: note.isDeleted) { editor.noteChanged(note) }
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

/// Deleted notes cannot be edited; this says so and offers the way back, as Notes does.
private struct DeletedNoteBanner: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let id: Note.ID

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
