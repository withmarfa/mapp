import SwiftUI
import UniformTypeIdentifiers

struct NoteDetail: View {
    @Environment(NoteLibrary.self) private var library
    let browser: Browser
    let editor: EditorController

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
            NotePage(note: note, editor: editor)
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

    var body: some View {
        GeometryReader { proxy in
            NoteEditor(controller: editor, topInset: proxy.safeAreaInsets.top)
                .ignoresSafeArea(.container, edges: .top)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if note.isDeleted {
                DeletedNoteBanner(id: note.id)
            } else if let item = library.item(note.id), item.type?.id != "core.note" {
                ItemSummary(item: item, parent: library.relationships(for: note.id).first { $0.field == "child-of" }?.targets.first?.title)
            }
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

/// Only useful at-a-glance information occupies the document header; full details stay in the inspector.
struct ItemSummary: View {
    let item: AppItem
    let parent: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title).font(.title2.weight(.semibold)).textSelection(.enabled)
            HStack(spacing: 12) {
                if let type = item.type { Text(type.label) }
                if let status = item.fields["status"]?.string { Text(ItemPropertyRow.choiceLabel(status)) }
                if let parent { Label(parent, systemImage: "square.stack").lineLimit(1) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(.bar)
    }
}
