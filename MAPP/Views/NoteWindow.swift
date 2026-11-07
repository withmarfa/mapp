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
    /// Version History waits for Customize Toolbar's tray to close, as replacing a toolbar under its tray crashes.
    @State private var isToolbarTrayOpen = false

    init(id: Binding<ItemID?>) {
        _id = id
    }

    /// The window's editor, holding the window's title drafts. Made when a note is shown, never for a file, which
    /// the editor's web view would never show.
    private var editor: EditorController? {
        guard let item else { return nil }
        return Self.pageEditor(for: library.pageLayout(of: item), in: editorSlot) {
            Self.makeEditor(library: library, details: details, showing: $id)
        }
    }

    /// The editor for an item of this page layout, or nil where the item is not shown in the editor, in which case
    /// none is made.
    static func pageEditor(for layout: ItemPageLayout, in slot: EditorSlot, make: () -> EditorController) -> EditorController? {
        layout == .text ? slot.editor(make) : nil
    }

    /// An editor for a window of its own: a link followed in the page shows the note it names in this window, by
    /// handing the window's item over, and the window remembers that item for the next launch.
    static func makeEditor(library: any ItemLibrary, details: DetailsPresentation, showing id: Binding<ItemID?>) -> EditorController {
        let editor = EditorController(library: library)
        editor.titleDrafts = details
        editor.onEscape = { [details] in details.endLayout() }
        editor.onChange = { [library] id, markdown, read in library.updateBody(of: id, to: markdown, readAt: read) }
        // The keyboard follows the link to the note it opened, as it does in a main window.
        editor.onOpenNote = { [weak editor] linked in
            id.wrappedValue = linked
            editor?.focus(linked)
        }
        return editor
    }

    private var item: Item? { id.flatMap { library.item($0) } }

    var body: some View {
        Group {
            if let history = details.history, !isToolbarTrayOpen {
                VersionHistoryWorkspace(mode: history, details: details)
            } else {
                page
            }
        }
        .modifier(ToolbarTrayWatch { isToolbarTrayOpen = $0 })
        .focusedSceneValue(\.detailsPresentation, details)
        .environment(details)
        .sheet(item: Binding { details.typeChange } set: { details.typeChange = $0 }) { TypeChangeSheet(request: $0) }
        .sheet(item: Binding { details.collectionPick } set: { details.collectionPick = $0 }) { CollectionPickerSheet(request: $0) }
        .sheet(item: Binding { details.tagRequest } set: { details.tagRequest = $0 }) { TagSheet(request: $0) }
        .onChange(of: details.isPresentedByPerson) { storedDetailsPresented = details.isPresentedByPerson }
        // Closing the sidebar by hand finishes Customize Layout, which has nowhere else to show.
        .onChange(of: details.isPresented) { if !details.isPresented { details.endLayout() } }
        .onAppear {
            details.isPresented = storedDetailsPresented
        }
        .onChange(of: library.isGone(id), initial: true) {
            if library.isGone(id) { dismiss() }
        }
        // Another server is another library, which does not hold this window's note.
        .onChange(of: ObjectIdentifier(library)) { dismiss() }
        // The note followed from a link is another item, which Version History is not of.
        .onChange(of: id) { details.leaveHistory() }
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

    /// The item's page with its inspector, which Version History takes the place of.
    private var page: some View {
        Group {
            if let item, let editor {
                NotePage(item: item, editor: editor, headerDrafts: details, backsToolbar: false)
                    .navigationTitle(item.displayTitle)
                    .toolbar(removing: .title)
                    .focusedSceneValue(\.editor, editor)
                    .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: [item.id], undoManager: undoManager))
                    .toolbar(id: "note") {
                        WindowToolbar(browser: nil, items: [item], editor: editor, details: details)
                    }
            } else if let item {
                FileItemPage(item: item, drafts: details, open: { id = $0 }, onResolved: { fileURL = $0 }, backsToolbar: false)
                    .navigationTitle(item.displayTitle)
                    .focusedSceneValue(\.focusedNotes, FocusedNotes(ids: [item.id], undoManager: undoManager))
                    .toolbar(id: "note") {
                        WindowToolbar(browser: nil, items: [item], editor: nil, details: details, fileURL: fileURL)
                    }
            }
        }
        .inspector(isPresented: Binding { details.isPresented } set: { details.isPresented = $0 }) {
            if let id {
                ItemInspectorHost(itemID: id, details: details)
                    .toolbar(id: "note") { InspectorToolbar(details: details, editor: editor) }
            }
        }
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
