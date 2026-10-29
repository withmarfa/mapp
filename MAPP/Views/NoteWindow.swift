import SwiftUI

/// One item in a window of its own, opened by double-clicking it in the list. The window remembers its item's
/// identifier, which outlasts a rename or a move, so it finds the item again at the next launch.
struct NoteWindow: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var editorSlot = EditorSlot()
    @State private var details = DetailsPresentation()
    @SceneStorage("detailsPresented") private var storedDetailsPresented = false
    @Binding var id: ItemID?
    /// Where the item's file is, once known, for sharing.
    @State private var fileURL: URL?

    init(id: Binding<ItemID?>) {
        _id = id
    }

    /// The window's editor, holding the window's title drafts.
    private var editor: EditorController {
        editorSlot.editor { Self.makeEditor(library: library, details: details, showing: $id) }
    }

    /// An editor for a window of its own: a link followed in the page shows the note it names in this window, by
    /// handing the window's item over, and the window remembers that item for the next launch.
    static func makeEditor(library: any ItemLibrary, details: DetailsPresentation, showing id: Binding<ItemID?>) -> EditorController {
        let editor = EditorController(library: library)
        editor.titleDrafts = details
        editor.onChange = { [library] id, markdown, read in library.updateBody(of: id, to: markdown, readAt: read) }
        // The keyboard follows the link to the note it opened, as it does in a main window.
        editor.onOpenNote = { [weak editor] linked in
            id.wrappedValue = linked
            editor?.focus(linked)
        }
        return editor
    }

    private var item: Item? { id.flatMap { library.item($0) } }

    /// Nothing while the inspector is closed, as the window's own actions are then the only ones.
    @ToolbarContentBuilder private var inspectorToolbar: some ToolbarContent {
        if details.isPresented {
            if let item {
                InspectorToolbar(browser: nil, items: [item], editor: editor, details: details, fileURL: fileURL)
            }
        }
    }

    var body: some View {
        Group {
            if let item, library.pageLayout(of: item) == .text {
                NotePage(item: item, editor: editor, headerDrafts: details, backsToolbar: false)
                    .navigationTitle(item.title)
                    .toolbar(removing: .title)
                    .focusedSceneValue(\.editor, editor)
                    .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: [item.id], undoManager: undoManager))
                    .toolbar(id: "note") {
                        NoteToolbar(browser: nil, items: [item], editor: editor, details: details)
                    }
            } else if let item {
                FileItemPage(item: item) { fileURL = $0 }
                    .navigationTitle(item.title)
                    .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: [item.id], undoManager: undoManager))
                    .toolbar(id: "note") {
                        NoteToolbar(browser: nil, items: [item], editor: editor, details: details, fileURL: fileURL)
                    }
            }
        }
        .inspector(isPresented: Binding { details.isPresented } set: { details.isPresented = $0 }) {
            if let id {
                ItemInspectorHost(itemID: id, details: details)
                    .toolbar { inspectorToolbar }
            }
        }
        .focusedSceneValue(\.detailsPresentation, details)
        .environment(details)
        .sheet(item: Binding { details.typeChange } set: { details.typeChange = $0 }) { TypeChangeSheet(request: $0) }
        .sheet(item: Binding { details.history } set: { details.history = $0 }) { VersionHistorySheet(request: $0) }
        .sheet(item: Binding { details.pageCustomization } set: { details.pageCustomization = $0 }) { CustomizePageSheet(request: $0) }
        .sheet(item: Binding { details.collectionPick } set: { details.collectionPick = $0 }) { CollectionPickerSheet(request: $0) }
        .sheet(item: Binding { details.tagRequest } set: { details.tagRequest = $0 }) { TagSheet(request: $0) }
        .onChange(of: details.isPresented) { storedDetailsPresented = details.isPresented }
        .onAppear {
            details.isPresented = storedDetailsPresented
        }
        .onChange(of: library.isGone(id), initial: true) {
            if library.isGone(id) { dismiss() }
        }
        // Another server is another library, which does not hold this window's note.
        .onChange(of: ObjectIdentifier(library)) { dismiss() }
        // The page goes when its library does, as when the window waits while the server's copy opens again, and
        // the window's undo would act on the library left.
        .onDisappear { [library] in
            // What was typed in the inspector goes to the library it was typed for, or back to the person.
            details.handOffProperties(in: library, undoManager: nil)
            // A window that never showed a note made no editor.
            editorSlot.made?.flush()
            editorSlot.made?.windowWent()
            undoManager?.removeAllActions()
        }
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
