import SwiftUI
import Observation

/// The items the frontmost window is showing, and that window's undo manager, so the menu bar acts on them.
struct FocusedItems {
    let ids: Set<ItemID>
    let undoManager: UndoManager?
}

extension FocusedValues {
    /// The main window in front, for commands that change what it shows.
    @Entry var browser: Browser?
    @Entry var detailsPresentation: DetailsPresentation?
    @Entry var focusedItems: FocusedItems?
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
    /// The Reader and Original switch of the page showing, while it has an article. The toolbar and the menus hold it.
    private(set) var pageLook: PageLookSwitch?
    /// The head of the page that has scrolled it out of sight, which the toolbar then names: the item, its title and its
    /// type's icon. Nil while the head shows. Both kinds of page feed it: the item's page from the editor, a web page
    /// from its web view. It names the item, so a page still reporting for the item before cannot show that item's
    /// title for the next.
    private(set) var scrolledHead: ScrolledHead?
    /// The item the window has in Focus: its title is in the toolbar and its properties are hidden. It names the item,
    /// so another item's page is never in Focus, and `pageShows(_:)` forgets it when the page moves on.
    private(set) var focusedItem: ItemID?
    /// The item whose formats bar (Aa) is open, named for the same reason.
    private(set) var formatsItem: ItemID?
    /// The size and page of the image or PDF the window's page has ready, which the corner and the menus act on. It names
    /// its item, so another item's page never takes it, and the page withdraws it when it goes.
    private(set) var offeredFile: (item: ItemID, viewing: FileViewing)?
    /// Where the file of the item on the page is, once the window has fetched it, which the corner's Open hands to the
    /// app that opens it.
    private(set) var resolvedFile: (item: ItemID, url: URL)?
    /// The items the window's Change Type panel is asked for.
    var typeChange: TypeChangeRequest?
    /// The items and type the window asks the values for that the type needs.
    var typeValues: TypeValuesRequest?
    /// The change to a field of a type the window's sheet asks the person's words for.
    var fieldEdit: FieldEditRequest?
    /// Version History, while the window shows it in place of its page.
    private(set) var history: VersionHistoryMode?
    /// Whether the window's right sidebar is editing a view (`ViewPanel`), in place of the item's panel. The panel itself
    /// is the browser's; this holds the sidebar for it and gives it back.
    private(set) var isEditingView = false
    /// Whether closing the view panel closes the sidebar, because opening it opened the sidebar.
    @ObservationIgnored private var closesSidebarAtViewEnd = false
    /// The items the window's Add to Collection panel is asked for.
    var collectionPick: CollectionPickRequest?
    /// The items the window's Add Tag panel is asked for.
    var tagRequest: TagRequest?
    /// The items the window asks the person to confirm moving to Recently Deleted.
    var deletion: DeleteRequest?
    /// The items the window asks whether to archive with what is under them.
    var archiving: ArchiveRequest?
    /// The items the window asks to confirm moving to the Feed, which would let them go.
    var feedLimit: FeedLimitRequest?
    /// How long the question before moving several items waits for the server's preview before it is asked without one.
    static let previewDeadline: Duration = .milliseconds(1500)
    /// The latest question asked for; an answer for an earlier one is dropped.
    @ObservationIgnored private var latestAsk = 0

    /// Asks to move `moving` to Recently Deleted, naming what the server says may also move where `selection` (all that
    /// the person chose) is small enough to read. The read gets `deadline`, then the question is asked without a count
    /// and a late answer is ignored. A started core call can't be cancelled, so the read is raced against a timer. An
    /// answer for a question that is no longer the latest is dropped, so a slow one never reopens an earlier Delete.
    func askToMove(
        _ moving: Set<ItemID>, of selection: Set<ItemID>, in library: any ItemLibrary, undoManager: UndoManager?,
        within deadline: Duration = DetailsPresentation.previewDeadline
    ) async {
        latestAsk += 1
        let mine = latestAsk
        let alsoTaking = selection.count <= DeletionWords.previewLimit
            ? await Self.firstAnswer(within: deadline) { await library.moreItemsTaken(with: moving) } : nil
        guard mine == latestAsk else { return }
        deletion = DeleteRequest(ids: moving, alsoTaking: alsoTaking, undoManager: undoManager)
    }

    /// `read`'s answer, or nil once `deadline` passes, whichever comes first. A read that never answers is left behind.
    private static func firstAnswer(within deadline: Duration, of read: @escaping @MainActor () async -> Int?) async -> Int? {
        let race = FirstAnswerRace()
        return await withCheckedContinuation { continuation in
            race.start(continuation, deadline: deadline, read: read)
        }
    }

    /// The window's toast, which lives here with the rest of what the window presents, above its split view.
    let toasts = ToastPresenter()
    @ObservationIgnored private var drafts: [ItemID: [String: ItemPropertyDraft]] = [:]

    /// Gives the window `item`'s switch, or takes `item`'s away. Another item's is left alone, since a page going away
    /// can be told after the next one has arrived.
    func offerPageLook(_ look: PageLookSwitch?, for item: ItemID) {
        if look != nil || pageLook?.item == item { pageLook = look }
    }

    /// Says that `item`'s page has scrolled its head away, as `head`, or shows it again, with nil. Saying so for one
    /// item never changes another's.
    func headerScrolled(_ head: ScrolledHead?, for item: ItemID) {
        if let head, head.item == item {
            if scrolledHead != head { scrolledHead = head }
        } else if scrolledHead?.item == item {
            scrolledHead = nil
        }
    }

    /// `item`'s file is at `url`, or is not yet anywhere, as while it is fetched.
    func fileResolved(_ url: URL?, for item: ItemID) {
        resolvedFile = url.map { (item, $0) }
    }

    /// The file of `item`'s page, once the window has it.
    func fileURL(of item: ItemID?) -> URL? {
        guard let item, resolvedFile?.item == item else { return nil }
        return resolvedFile?.url
    }

    /// Gives the window the controls of `item`'s file, which its page has ready.
    func offerFileView(_ viewing: FileViewing, for item: ItemID) {
        offeredFile = (item, viewing)
    }

    /// Takes `viewing` away as its page goes. Another file's controls are left alone, since a page going away can be
    /// told after the next has arrived.
    func withdrawFileView(_ viewing: FileViewing) {
        if offeredFile?.viewing === viewing { offeredFile = nil }
    }

    /// The controls of `item`'s file, while its page has them.
    func fileViewing(of item: ItemID?) -> FileViewing? {
        guard let item, offeredFile?.item == item else { return nil }
        return offeredFile?.viewing
    }

    func isHeaderAway(of item: ItemID) -> Bool { scrolledHead?.item == item }

    func isFocused(on item: ItemID?) -> Bool { item != nil && focusedItem == item }

    func isFormatsOpen(on item: ItemID?) -> Bool { item != nil && formatsItem == item }

    /// Turns Focus on for `item`, or off if it is on.
    func toggleFocus(on item: ItemID) {
        focusedItem = focusedItem == item ? nil : item
    }

    func toggleFormats(on item: ItemID) {
        formatsItem = formatsItem == item ? nil : item
    }

    func closeFormats() { formatsItem = nil }

    /// How many pages `item`'s PDF has, once its page has read the file. Focus puts it under the title in the toolbar.
    func pages(of item: ItemID) -> Int? { fileViewing(of: item)?.pages?.count }

    /// The page now shows `item`, or nothing. Focus and the formats bar belong to the item they were chosen on, so
    /// moving to another item, or leaving the page, puts both away.
    func pageShows(_ item: ItemID?) {
        if focusedItem != item { focusedItem = nil }
        if formatsItem != item { formatsItem = nil }
        if offeredFile?.item != item { offeredFile = nil }
        if resolvedFile?.item != item { resolvedFile = nil }
    }

    /// `item`'s page has gone, as when the item was deleted or the window turned to something else. Another item's
    /// Focus is left alone, since a page going away can be told after the next one has arrived.
    func pageLeft(_ item: ItemID) {
        if focusedItem == item { focusedItem = nil }
        if formatsItem == item { formatsItem = nil }
        if offeredFile?.item == item { offeredFile = nil }
        if resolvedFile?.item == item { resolvedFile = nil }
    }

    /// Escape on the page: an open size field closes first, then the formats bar, then Focus on a second press. False
    /// when none was showing, so the key is the caller's. The field closes here whether or not it holds the keyboard,
    /// so Escape never stays stuck behind a field that never took focus.
    @discardableResult
    func escapeFromPage() -> Bool {
        if let viewing = offeredFile?.viewing, viewing.isEditingSize {
            viewing.isEditingSize = false
            return true
        }
        if formatsItem != nil {
            formatsItem = nil
            return true
        }
        if focusedItem != nil {
            focusedItem = nil
            return true
        }
        return false
    }

    /// Shows the item's versions in place of the window's page, once every open page has handed over what was just
    /// typed, so the version shown as current is the text the person sees. Nothing happens while one is shown.
    func showHistory(of id: ItemID, in library: any ItemLibrary) {
        guard history == nil else { return }
        EditorController.flushAll(leaving: false) { [weak self] kept in
            guard let self, history == nil else { return }
            guard kept else {
                library.notices.tell(String(localized: "Can’t Open Version History"), String(localized: "Finish editing the current item, then try again."))
                return
            }
            let mode = VersionHistoryMode(item: id, source: library.history)
            history = mode
            mode.start()
        }
    }

    /// Restores the chosen version, and goes back to the item once the library has taken it. A restore the library
    /// refuses leaves Version History open, with the notice that says why.
    func restoreFromHistory(in library: any ItemLibrary, undoManager: UndoManager?) {
        history?.restore(in: library, undoManager: undoManager) { [weak self] restored in
            if restored { self?.leaveHistory() }
        }
    }

    /// Goes back to the window's page.
    func leaveHistory() {
        history?.stop()
        history = nil
    }

    /// Shows the sidebar, which takes the view panel, and remembers to close it again if it was closed.
    func beginViewPanel() {
        guard !isEditingView else { return }
        closesSidebarAtViewEnd = !isPresented
        isEditingView = true
        isPresented = true
    }

    func endViewPanel() {
        guard isEditingView else { return }
        isEditingView = false
        if closesSidebarAtViewEnd { isPresented = false }
        closesSidebarAtViewEnd = false
    }

    /// Whether the person has the sidebar open, for the next launch: a sidebar only the view panel opened is not.
    var isPresentedByPerson: Bool {
        isPresented && !(isEditingView && closesSidebarAtViewEnd)
    }

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

/// What the Change Type panel changes, with the undo manager of the window it was asked for in, since the panel
/// has its own.
struct TypeChangeRequest: Identifiable {
    let id = UUID()
    let ids: Set<ItemID>
    let undoManager: UndoManager?
}

/// The values a chosen type needs that the items lack (`TypeValuesSheet`), with the undo manager of the window.
struct TypeValuesRequest: Identifiable {
    let id = UUID()
    let ids: Set<ItemID>
    let type: TypeID
    let undoManager: UndoManager?
}

/// The items the Add to Collection panel files, with the undo manager of the window it was asked for in.
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
    /// At least how many more items the server says moving them takes, where it could be read; nil otherwise.
    let alsoTaking: Int?
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

/// One answer from two racers: the read and the timer. The first to finish resumes the caller; the other is ignored.
@MainActor
private final class FirstAnswerRace {
    private var continuation: CheckedContinuation<Int?, Never>?
    private var timer: Task<Void, Never>?

    func start(_ continuation: CheckedContinuation<Int?, Never>, deadline: Duration, read: @escaping @MainActor () async -> Int?) {
        self.continuation = continuation
        timer = Task {
            try? await Task.sleep(for: deadline)
            finish(nil)
        }
        Task { finish(await read()) }
    }

    private func finish(_ answer: Int?) {
        continuation?.resume(returning: answer)
        continuation = nil
        timer?.cancel()
    }
}

/// What the toolbar shows of an item whose page has scrolled its head out of sight: its title as the head shows it, and
/// its type's mark.
struct ScrolledHead: Equatable, Sendable {
    let item: ItemID
    let title: String
    /// The type's icon, an Iconify ID.
    let typeIcon: String?
}
