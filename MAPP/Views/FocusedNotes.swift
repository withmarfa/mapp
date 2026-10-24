import SwiftUI
import Observation

/// The notes the frontmost window is showing, and that window's undo manager, so the menu bar acts on them.
struct FocusedNotes {
    let ids: Set<ItemID>
    let undoManager: UndoManager?
}

extension FocusedValues {
    /// The main window in front, for commands that change what it shows.
    @Entry var browser: Browser?
    @Entry var detailsPresentation: DetailsPresentation?
    @Entry var focusedNotes: FocusedNotes?
    /// The editor of the window in front, for the Format menu. Held weakly: SwiftUI keeps the last focused
    /// values after their window closes, which would otherwise keep that window's editor, page and library.
    var editor: EditorController? {
        get { self[FocusedEditorKey.self]?.editor }
        set { self[FocusedEditorKey.self] = newValue.map(FocusedEditor.init) }
    }
}

private struct FocusedEditor {
    weak var editor: EditorController?
}

private struct FocusedEditorKey: FocusedValueKey {
    typealias Value = FocusedEditor
}

/// Presentation belongs to a window, so menu and toolbar actions share it without changing other windows.
@Observable
final class DetailsPresentation {
    var isPresented = false
    @ObservationIgnored private var drafts: [ItemID: [String: ItemPropertyDraft]] = [:]

    func draft(for itemID: ItemID, key: String) -> ItemPropertyDraft {
        if let draft = drafts[itemID]?[key] { return draft }
        let draft = ItemPropertyDraft()
        drafts[itemID, default: [:]][key] = draft
        return draft
    }

    /// The items whose title the person typed and has not saved, in a steady order.
    var unsavedTitles: [ItemID] {
        drafts.filter { $0.value["title"]?.isDirty == true }.map(\.key).sorted { $0.rawValue < $1.rawValue }
    }

    /// Saves the title typed for the item, if there is one; whether the title the page shows is saved.
    @discardableResult
    func saveTitle(of id: ItemID, in library: any ItemLibrary, undoManager: UndoManager?) -> Bool {
        let draft = draft(for: id, key: "title")
        guard draft.isDirty, let item = library.item(id), library.canSetTitle(of: item) else { return !draft.rejected }
        let title = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.rejected = !library.setItemProperty(id, key: "title", value: .string(title), undoManager: undoManager)
        if !draft.rejected { draft.isDirty = false }
        return !draft.rejected
    }
}

/// A rejected input belongs to its window and item, rather than to the lifetime of a row.
@Observable
final class ItemPropertyDraft {
    var text = ""
    var isDirty = false
    var rejected = false
}
