import SwiftUI

/// One item in a window of its own, opened by double-clicking it in the list. The window remembers its item's
/// identifier, which outlasts a rename or a move, so it finds the item again at the next launch.
struct NoteWindow: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var editor: EditorController
    @State private var details = DetailsPresentation()
    @SceneStorage("detailsPresented") private var storedDetailsPresented = false
    @Binding var id: ItemID?

    /// The library is given here as well as in the environment, since the editor is made with it.
    init(library: any ItemLibrary, id: Binding<ItemID?>) {
        _editor = State(initialValue: EditorController(library: library))
        _id = id
    }

    private var item: Item? { id.flatMap { library.item($0) } }

    var body: some View {
        Group {
            if let item, !item.isFile {
                NotePage(item: item, editor: editor, headerDrafts: details)
                    .navigationTitle(item.title)
                    .toolbar(removing: .title)
                    .focusedSceneValue(\.editor, editor)
                    .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: [item.id], undoManager: undoManager))
                    .toolbar(id: "note") {
                        NoteToolbar(browser: nil, items: [item], editor: editor, details: details)
                    }
            } else if let item, let url = library.fileURL(for: item.id) {
                FileItemContent(url: url)
                    .navigationTitle(item.title)
                    .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: [item.id], undoManager: undoManager))
                    .toolbar {
                        ToolbarItem {
                            ShareLink(item: url)
                        }
                        ToolbarItem {
                            Button("Details", systemImage: "info.circle") { details.isPresented.toggle() }
                                .accessibilityIdentifier("DetailsToggle")
                        }
                    }
            }
        }
        .inspector(isPresented: Binding { details.isPresented } set: { details.isPresented = $0 }) {
            if let id { ItemInspectorHost(itemID: id, details: details) }
        }
        .focusedSceneValue(\.detailsPresentation, details)
        .onChange(of: details.isPresented) { storedDetailsPresented = details.isPresented }
        .onAppear {
            details.isPresented = storedDetailsPresented
            editor.onChange = { [library] id, markdown in library.updateBody(of: id, to: markdown) }
            editor.onLeave = { [library] id in library.leave(id) }
        }
        .onChange(of: library.isGone(id), initial: true) {
            if library.isGone(id) { dismiss() }
        }
        // Another notes folder is another library, which does not hold this window's note.
        .onChange(of: ObjectIdentifier(library)) { dismiss() }
        .onDisappear { editor.flush() }
        .libraryDialogs()
    }
}

/// A window with nothing to show, which closes.
struct ClosingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .onAppear { dismiss() }
    }
}
