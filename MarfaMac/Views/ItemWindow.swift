import SwiftUI

/// One item in a window of its own, opened by double-clicking it in the list. The window remembers its item's
/// identifier, which outlasts a rename or a move, so it finds the item again at the next launch. A link followed in it
/// shows the linked item in the window, and Back and Forward in its toolbar return along the window's own history.
struct ItemWindow: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var editorSlot = EditorSlot()
    @State private var details = DetailsPresentation()
    @State private var history = ItemWindowHistory()
    @SceneStorage("detailsPresented") private var storedDetailsPresented = false
    @Binding var id: ItemID?
    /// Where the item's file is, once known, for sharing.
    @State private var fileURL: URL?

    init(id: Binding<ItemID?>) {
        _id = id
    }

    /// The window's editor, holding the window's title drafts. Made when an item is shown, never for a file, which
    /// the editor's web view would never show.
    private var editor: EditorController? {
        guard let item else { return nil }
        return Self.pageEditor(for: library.pageLayout(of: item), in: editorSlot) {
            Self.makeEditor(library: library, details: details, showing: $id, history: history)
        }
    }

    /// The editor for an item of this page layout, or nil where the item is not shown in the editor, in which case
    /// none is made.
    static func pageEditor(for layout: ItemPageLayout, in slot: EditorSlot, make: () -> EditorController) -> EditorController? {
        layout == .text ? slot.editor(make) : nil
    }

    /// An editor for a window of its own: a link followed in the page shows the item it names in this window, by
    /// handing the window's item over (`go`), and the window remembers that item for the next launch. The item it
    /// leaves is where Back returns to, in `history`.
    static func makeEditor(
        library: any ItemLibrary, details: DetailsPresentation, showing id: Binding<ItemID?>, history: ItemWindowHistory? = nil
    ) -> EditorController {
        let editor = EditorController(library: library)
        editor.titleDrafts = details
        editor.onEscape = { [details] in details.escapeFromPage() }
        editor.onChange = { [library] id, markdown, read in library.updateBody(of: id, to: markdown, readAt: read) }
        // The keyboard follows the link to the item it opened, as it does in a main window.
        editor.onOpenItem = { [weak editor, library] linked in
            guard let current = id.wrappedValue else { return }
            go(to: linked, in: library, editor: editor, showing: id) {
                history?.followed(from: current, to: linked)
                editor?.focus(linked)
            }
        }
        return editor
    }

    /// Shows `target` in the window once the editor holds it (`EditorController.open`): a text item once the page
    /// holds it, a file once the text is in, since a file's page has no editor to hand it over later. Only then do the
    /// window's item and history change (`arrived` runs first). A hand-over that fails leaves the window on the item
    /// the editor holds, and the editor has told the person.
    static func go(
        to target: ItemID, in library: any ItemLibrary, editor: EditorController?, showing id: Binding<ItemID?>,
        arrived: @escaping () -> Void = {}
    ) {
        guard let item = library.item(target) else { return }
        let arrive = { (shown: Bool) in
            guard shown else { return }
            arrived()
            id.wrappedValue = target
        }
        guard let editor else { return arrive(true) }
        editor.open(item, then: arrive)
    }

    private var item: Item? { id.flatMap { library.item($0) } }

    /// A link followed from a file's page, which shows the item in this window as the editor's links do.
    private func follow(_ linked: ItemID) {
        guard let current = id else { return }
        Self.go(to: linked, in: library, editor: editorSlot.made, showing: $id) { [history] in
            history.followed(from: current, to: linked)
        }
    }

    /// Back or Forward, along the links followed in this window.
    private func step(_ step: ItemWindowHistory.Step) {
        guard let current = id, let target = history.target(step, isAvailable: { library.item($0) != nil }) else { return }
        Self.go(to: target, in: library, editor: editorSlot.made, showing: $id) { [history] in
            history.went(step, from: current, to: target)
        }
    }

    var body: some View {
        Group {
            if let history = details.history {
                VersionHistoryWorkspace(mode: history, details: details)
            } else {
                page
            }
        }
        .focusedSceneValue(\.detailsPresentation, details)
        .toastOverlay()
        .environment(details)
        .modifier(CommandValuePanels(details: details))
        .modifier(FieldEditSheets(details: details))
        .sheet(item: Binding { details.typeValues } set: { details.typeValues = $0 }) { TypeValuesSheet(request: $0) }
        .onChange(of: details.isPresentedByPerson) { storedDetailsPresented = details.isPresentedByPerson }
        .onAppear {
            details.isPresented = storedDetailsPresented
        }
        .onChange(of: library.isGone(id), initial: true) {
            if library.isGone(id) { dismiss() }
        }
        // Another server is another library, which does not hold this window's item.
        .onChange(of: ObjectIdentifier(library)) { dismiss() }
        // The item followed from a link is another item, which Version History is not of.
        .onChange(of: id) { details.leaveHistory() }
        // The page goes when its library does, as when the window waits while the server's copy opens again, and
        // the window's undo would act on the library left.
        .onDisappear {
            // A window that never showed an item made no editor.
            editorSlot.made?.flush()
            editorSlot.made?.windowWent()
            undoManager?.removeAllActions()
        }
        .libraryDialogs()
        .archiveQuestion(for: details)
        .feedLimitQuestion(for: details)
    }

    /// The item's page with its inspector, which Version History takes the place of.
    private var page: some View {
        Group {
            if let item, let editor {
                ItemPage(item: item, editor: editor, headerDrafts: details, backsToolbar: false)
                    .itemCorner(item, editor: editor, details: details)
                    .escapesFromPage(details)
                    .navigationTitle(item.displayTitle)
                    .hidesWindowTitle()
                    .focusedSceneValue(\.editor, editor)
                    .focusedSceneValue(\.focusedItems, FocusedItems(ids: [item.id], undoManager: undoManager))
                    .toolbar {
                        ItemWindowToolbar(
                            tools: ItemToolbarActions(library: library, browser: nil, items: [item], editor: editor, details: details),
                            history: history, go: step)
                    }
            } else if let item {
                FileItemPage(item: item, drafts: details, open: follow, onResolved: { fileURL = $0 }, backsToolbar: false)
                    // An editor made for a text item shown before holds nothing a file's page shows, so it is left.
                    .onAppear { editorSlot.made?.close() }
                    .itemCorner(item, editor: nil, details: details)
                    .escapesFromPage(details)
                    .navigationTitle(item.displayTitle)
                    .focusedSceneValue(\.focusedItems, FocusedItems(ids: [item.id], undoManager: undoManager))
                    .toolbar {
                        ItemWindowToolbar(
                            tools: ItemToolbarActions(library: library, browser: nil, items: [item], editor: nil, details: details, fileURL: fileURL),
                            history: history, go: step)
                    }
            }
        }
        .inspector(isPresented: Binding { details.isPresented } set: { details.isPresented = $0 }) {
            if let id {
                ItemInspectorHost(itemID: id, details: details, editor: editor)
                    .toolbar { InspectorToolbar(details: details, editor: editor) }
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
