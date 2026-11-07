import Foundation
import Observation

/// The right sidebar's panel that edits a view, or a place that can become one. It holds what only the panel knows:
/// the name being typed, whether a save is under way, why one failed, and how to put a place back if the person
/// cancels. What the person changes lives in the window (`Browser.tableOptions`, `viewWorking`), where it shows at once.
@Observable
final class ViewPanel {
    enum Purpose: Equatable {
        /// A saved view: Cancel puts it back as saved, and Save keeps the changes.
        case edit(ItemID)
        /// A view that does not exist yet, made of what the window shows: Cancel puts the place back as it was.
        case new
        /// A place that is not a view, such as a type's list: it has no name and keeps nothing, and offers Save as View.
        case place
    }

    /// What Save asks the person to confirm first.
    struct Confirmation: Equatable {
        /// What of the window the view will not keep.
        var unkept: [ViewDraft.Unkept]
        /// The conditions of the view's filter the window cannot show, which a save leaves as they are.
        var unchanged: [String]
    }

    /// A place as it was when a new view began, so cancelling or saving leaves it as it was.
    struct Snapshot {
        let place: SidebarItem
        let options: ItemTableOptions?
        let timelineDate: String?
        let viewMode: ItemViewMode
        /// The columns the place keeps for itself (`ItemTableColumnLayouts`), as stored.
        let columns: Data?
        /// The settings held for the view, where the place is one.
        let working: ViewMacSettings?
        /// What the window drew on each card for the place, where it is not a view.
        let cards: ViewCards?
    }

    private(set) var purpose: Purpose
    @ObservationIgnored private var notices: Notices?
    /// The name already given back, so a quit after a close does not give it twice.
    @ObservationIgnored private var handedOffName: String?
    /// Why the panel was left while a save was under way, to be settled when the save ends.
    @ObservationIgnored private var departure: ViewTitleForm.Departure?
    /// The name of a view being edited. A new view's name is the form's, which keeps it until the server takes it.
    var name: String
    /// The view's name as the panel last read it, so a rename elsewhere shows unless the person is typing their own.
    var knownTitle: String
    private(set) var form: ViewTitleForm?
    private(set) var snapshot: Snapshot?
    var isSaving = false
    /// Why the last save did not happen, in words for the person.
    var failure: String?
    var confirmation: Confirmation?

    init(editing view: LibraryView, notices: Notices) {
        purpose = .edit(view.id)
        name = view.title
        knownTitle = view.title
        self.notices = notices
        Self.open.add(self)
    }

    init(newFrom snapshot: Snapshot, library: any ItemLibrary) {
        purpose = .new
        name = ""
        knownTitle = ""
        form = ViewTitleForm(library: library)
        self.snapshot = snapshot
        notices = library.notices
        Self.open.add(self)
    }

    init() {
        purpose = .place
        name = ""
        knownTitle = ""
        Self.open.add(self)
    }

    var viewID: ItemID? {
        if case .edit(let id) = purpose { id } else { nil }
    }

    var isNew: Bool { purpose == .new }

    /// A place's panel turns into a new view's, made of what the window shows now.
    func becomeNew(from snapshot: Snapshot, library: any ItemLibrary) {
        guard purpose == .place else { return }
        purpose = .new
        form = ViewTitleForm(library: library)
        self.snapshot = snapshot
        notices = library.notices
    }

    /// The name as the panel shows it for what it edits.
    var shownName: String {
        get { form?.title ?? name }
        set { if let form { form.title = newValue } else { name = newValue } }
    }

    var trimmedName: String { shownName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The name the person typed over a view's own, which nothing else holds until a save keeps it.
    var typedRename: String? {
        guard case .edit = purpose, trimmedName != knownTitle.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty else { return nil }
        return trimmedName
    }

    /// Gives what the person typed and no save has kept to the clipboard, through the library's notices, as the panel
    /// ends in any way but their own Cancel. A name on its way to the server is given back only if the save fails.
    func handOff(because departure: ViewTitleForm.Departure) {
        switch purpose {
        case .new:
            form?.handOff(because: departure)
        case .edit:
            guard typedRename != nil else { return }
            guard !isSaving else {
                self.departure = self.departure ?? departure
                return
            }
            let reason = switch departure {
            case .closed: String(localized: "The window closed before the view was renamed.")
            case .libraryChanged: String(localized: "The window changed to another library before the view was renamed.")
            case .left: String(localized: "The panel closed before the view was renamed.")
            }
            giveBackRename(reason: reason)
        case .place:
            break
        }
    }

    /// The view is gone, so the name typed for it has nowhere to go. Whether there was one to give back.
    @discardableResult
    func handOffBecauseGone() -> Bool {
        guard typedRename != nil else { return false }
        giveBackRename(reason: String(localized: "The view was deleted before it was renamed."))
        return true
    }

    /// A save has ended without keeping the name: a panel left while it ran gives the name back now.
    func settleAfterUnsavedEnd() {
        guard let departure else { return }
        self.departure = nil
        handOff(because: departure)
    }

    private func giveBackRename(reason: String) {
        guard let name = typedRename, name != handedOffName else { return }
        handedOffName = name
        notices?.notKept(String(localized: "View Not Renamed"), text: name, reason: reason)
    }

    /// Every panel still open, so a quit can give back each name.
    private static let open = NSHashTable<ViewPanel>.weakObjects()

    /// Gives back every name typed and not kept, as the app quits.
    static func handOffAll() {
        for panel in open.allObjects { panel.handOff(because: .closed) }
    }
}
