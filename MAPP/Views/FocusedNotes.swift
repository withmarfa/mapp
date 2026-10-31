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
    /// The items the window's Change Type sheet is open for.
    var typeChange: TypeChangeRequest?
    /// The item the window's Version History sheet is open for.
    var history: VersionHistoryRequest?
    /// The item whose type the window's Customize Page sheet is open for.
    var pageCustomization: PageCustomizationRequest?
    /// The items the window's Add to Collection sheet is open for.
    var collectionPick: CollectionPickRequest?
    /// The items the window's Add Tag sheet is open for.
    var tagRequest: TagRequest?
    /// The items the window asks the person to confirm moving to Recently Deleted.
    var deletion: DeleteRequest?
    /// The groups of links the person has shown in full. They stay shown while the window lives, whichever item it
    /// shows meanwhile.
    private(set) var expandedLinks: Set<LinkGroup> = []
    @ObservationIgnored private var drafts: [ItemID: [String: ItemPropertyDraft]] = [:]

    init() { Self.open.add(self) }

    /// Every window's presentation, so a quit can reach the drafts each holds.
    private static let open = NSHashTable<DetailsPresentation>.weakObjects()

    /// Hands every window's unsaved property drafts to `library`, as the app quits.
    static func handOffAllProperties(in library: (any ItemLibrary)?) {
        guard let library else { return }
        for presentation in open.allObjects { presentation.handOffProperties(in: library, undoManager: nil) }
    }

    func expandLinks(_ group: LinkGroup) { expandedLinks.insert(group) }

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

    /// The property drafts the person typed and has not saved, for `itemID` or for every item, in a steady order. The
    /// title and the new tag have homes of their own.
    func unsavedProperties(of itemID: ItemID? = nil) -> [(item: ItemID, key: String, draft: ItemPropertyDraft)] {
        drafts.filter { itemID == nil || $0.key == itemID }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .flatMap { item, keyed in
                keyed.filter { ($0.value.isDirty || $0.value.holdsUnsavedList) && $0.value.field != nil }
                    .sorted { $0.key < $1.key }
                    .map { (item, $0.key, $0.value) }
            }
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

/// What the Change Type sheet changes, with the undo manager of the window it was asked for in, since the sheet
/// has its own.
struct TypeChangeRequest: Identifiable {
    let id = UUID()
    let ids: Set<ItemID>
    let undoManager: UndoManager?
}

/// The items the Add to Collection sheet files, with the undo manager of the window it was asked for in, since the
/// sheet has its own.
struct CollectionPickRequest: Identifiable {
    let id = UUID()
    let ids: Set<ItemID>
    let undoManager: UndoManager?
}

/// Several items waiting for the person to confirm moving them to Recently Deleted, with the undo manager of the
/// window they were asked for in.
struct DeleteRequest: Identifiable {
    let id = UUID()
    let ids: Set<ItemID>
    let undoManager: UndoManager?
}

/// A rejected input belongs to its window and item, rather than to the lifetime of a row.
@Observable
final class ItemPropertyDraft {
    var text = ""
    var isDirty = false
    var rejected = false
    /// The stored text the draft started from, to tell whether the item changed under it.
    var base: String?
    /// The property the draft is for, set by its row, so a draft left behind can be written or handed back without
    /// the row.
    var field: ItemTypeInfo.Field?
    @ObservationIgnored private var listStorage: ListEditing?

    /// The work on a list of entries, for a list property; made on first use.
    var list: ListEditing {
        if let listStorage { return listStorage }
        let list = ListEditing()
        listStorage = list
        return list
    }

    /// Whether the draft is for a list that holds text not yet written.
    var holdsUnsavedList: Bool { listStorage?.holdsUnsavedWork == true }
}
