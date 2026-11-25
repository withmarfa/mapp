import Foundation
import Observation

/// The View panel, the popover under the top row's View button that edits a view, or a place that can become one. It
/// holds what only the panel knows: the page it shows, the name being typed, and how to put a place back if the person
/// escapes a new view. What the person changes lives in the window (`Browser.tableOptions`, `viewSeeds`), where it shows
/// at once and, in a saved view, is written as made.
@Observable
final class ViewPanel {
    enum Purpose: Equatable {
        /// A saved view: each change is written as it is made.
        case edit(ItemID)
        /// A view that does not exist yet, made of what the window shows: Create View makes it, and Escape makes nothing.
        case new
        /// A place that is not a view, such as a type's list: it has no name, keeps its choices in its default view (`PlaceDefaults`), and offers New View….
        case place
    }

    /// A place as it was when a new view began, so cancelling or saving leaves it as it was.
    struct Snapshot {
        let place: PlaceView
        let options: ItemTableOptions?
        let timelineDate: String?
        let viewMode: ItemViewMode
        /// The columns the place keeps for itself (`ItemTableColumnLayouts`), as stored.
        let columns: Data?
        /// What this Mac held for the view, where the place is one, which a new view starts from.
        let mac: ViewMacSettings?
        /// What the window drew on each card for the place, where it is not a view.
        let cards: ViewCards?
        /// The density this Mac kept for the place, where it is not a view.
        let density: Density?
        /// What the place's default view kept, where the place is not a view.
        let placeDefault: PlaceDefault?
        /// What Marfa held for the view as the window last read it, where the place is one.
        var seed: Browser.ViewSeed?
    }

    /// What the popover shows: the view's settings, or one of them opened in place, with a way back.
    enum Page: Hashable {
        case main, filter, sort, group, properties, types
    }

    private(set) var purpose: Purpose
    var page = Page.main
    /// Whether the head shows the view's name as a field, as Rename… asks. A new view's always does.
    var isRenaming = false
    @ObservationIgnored private var notices: Notices?
    /// The name being written to the server, which is neither kept nor lost until the write answers.
    @ObservationIgnored var renaming: String?
    /// Whether the panel ended while a name was being written, so a name the server then refuses is given back.
    @ObservationIgnored private var leftWhileRenaming: String?
    /// The name already given back, so a quit after a close does not give it twice.
    @ObservationIgnored private var handedOffName: String?
    /// The name of a view being edited. A new view's name is the form's, which keeps it until the server takes it.
    var name: String {
        didSet {
            if typedRename == nil {
                renameBase = nil
            } else if renameBase == nil {
                renameBase = RenameBase(title: knownTitle, version: knownVersion)
            }
        }
    }
    /// The view's name and version as the panel last read them, so a rename elsewhere shows unless the person is typing
    /// their own.
    var knownTitle: String
    @ObservationIgnored var knownVersion: Int64 = 0
    /// The view's name and version when the person began to type over its name: the rename is written against these,
    /// so a rename made in another app meanwhile is never written over (`Browser.commitViewName`).
    @ObservationIgnored private(set) var renameBase: RenameBase?

    struct RenameBase: Equatable {
        let title: String
        let version: Int64
    }
    private(set) var form: ViewTitleForm?
    private(set) var snapshot: Snapshot?

    // MARK: A new view

    /// Why Create View made nothing yet. Everything the person chose stays in the panel and the window.
    enum Problem: Equatable {
        /// The server can't be reached; a view is never queued, so Create View is chosen again once it is back.
        case offline
        /// Another view has this name.
        case clash(String)
        /// The server refused the view and has told the person why.
        case refused
    }

    /// The starting point the person chose, which the window shows.
    var start: NewViewStart?
    /// The layout the new view will open in after Create View.
    var draftLayout: ItemViewMode?
    /// Whether the new view is kept in the sidebar. Off until the person turns it on.
    var addsToSidebar = false
    /// The new view's Quick Actions on this Mac; nil follows the place.
    var quickActions: Bool?
    /// This Mac's settings for a new view made from a saved view: the window shows and changes these until Create View
    /// gives them to the new view, so the saved view's own stay as they are.
    var mac: ViewMacSettings?
    var problem: Problem?
    /// The name the panel last suggested, which follows the view's settings until the person types their own.
    private(set) var suggestedName = ""

    /// Puts `name` in the field unless the person typed a name of their own.
    func suggest(_ name: String) {
        guard let form, name != suggestedName else { return }
        if form.trimmedTitle.isEmpty || form.title == suggestedName { form.title = name }
        suggestedName = name
    }

    /// Whether the person unticked every source of an inbox, which Create View won't make.
    var choosesNoSource = false

    /// What the new view's values were when the panel opened or the person last chose a starting point: a draft that
    /// differs, or holds a typed name, is the person's work (`Browser.isNewViewTouched`).
    struct Values: Equatable {
        var options: ItemTableOptions
        var layout: ItemViewMode
        var timelineDate: String?
        var quickActions: Bool?
        var addsToSidebar: Bool
        var choosesNoSource: Bool
    }

    var startingValues: Values?

    /// Whether the person typed a name of their own rather than taking the one suggested.
    var hasTypedName: Bool {
        guard let form else { return false }
        return !form.trimmedTitle.isEmpty && form.title != suggestedName
    }

    /// The search set aside while a starting point other than This Search shows its own list, put back when the panel
    /// closes on the place it began on.
    struct SetAsideSearch {
        var text: String
        var tokens: [FilterClause]
        var relevanceChoice: Bool?
    }

    var setAsideSearch: SetAsideSearch?
    /// The search's tokens This Search says with its From rather than its filter.
    var tokensInFrom: [FilterClause] = []

    /// The new view in words, or nil while the person has made nothing of it, given back when the panel ends any way
    /// but Cancel (`Browser.newViewHandOff`).
    @ObservationIgnored var handOffText: (() -> String?)?

    /// Works the words out now, while the window still shows the place the new view began on.
    func settleHandOffText() {
        guard let handOffText else { return }
        let text = handOffText()
        self.handOffText = { text }
    }

    init(editing view: LibraryView, notices: Notices) {
        purpose = .edit(view.id)
        name = view.title
        knownTitle = view.title
        knownVersion = view.version
        self.notices = notices
        Self.open.add(self)
    }

    init(newFrom snapshot: Snapshot, library: any ItemLibrary) {
        purpose = .new
        name = ""
        knownTitle = ""
        form = ViewTitleForm(library: library)
        self.snapshot = snapshot
        draftLayout = snapshot.viewMode
        mac = snapshot.mac
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
        draftLayout = snapshot.viewMode
        mac = snapshot.mac
        notices = library.notices
    }

    /// The name as the panel shows it for what it edits.
    var shownName: String {
        get { form?.title ?? name }
        set { if let form { form.title = newValue } else { name = newValue } }
    }

    var trimmedName: String { shownName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The name the person typed over a view's own, which nothing else holds until it is committed.
    var typedRename: String? {
        guard case .edit = purpose, trimmedName != knownTitle.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty else { return nil }
        return trimmedName
    }

    /// Gives what the person typed and nothing has kept to the clipboard, through the library's notices, as the panel
    /// ends in any way but their own Escape.
    func handOff(because departure: ViewTitleForm.Departure) {
        switch purpose {
        case .new:
            if let handOffText, let text = handOffText() {
                form?.handOff(because: departure, text: text)
            } else if handOffText != nil {
                // Nothing of the person's is in it.
                form?.discard()
            } else {
                form?.handOff(because: departure)
            }
        case .edit:
            guard typedRename != nil else { return }
            if renaming != nil {
                leftWhileRenaming = leaveReason(departure)
                return
            }
            giveBackRename(reason: leaveReason(departure))
        case .place:
            break
        }
    }

    /// The panel ends with the name typed still to be written (`Browser.commitViewName`): a write that fails or is
    /// refused, or a view gone meanwhile, gives the name back, as a panel that ended mid-rename does.
    func leave(because departure: ViewTitleForm.Departure) {
        guard case .edit = purpose, typedRename != nil else { return }
        leftWhileRenaming = leaveReason(departure)
    }

    /// Whether the panel has ended with a name the view does not yet hold.
    var hasLeftWithRename: Bool { leftWhileRenaming != nil }

    private func leaveReason(_ departure: ViewTitleForm.Departure) -> String {
        switch departure {
        case .closed: String(localized: "The window closed before the view was renamed.")
        case .libraryChanged: String(localized: "The window changed to another library before the view was renamed.")
        case .left: String(localized: "The panel closed before the view was renamed.")
        }
    }

    /// The write of `name` answered. From a panel that ended meanwhile, whatever the person typed last and the view does
    /// not hold is given back, once no later write of a name is still under way.
    func finishRename(name: String, kept: Bool, reason: String? = nil) {
        if renaming == name { renaming = nil }
        if kept {
            knownTitle = name
            // A name typed since starts from the one just written.
            if renaming == nil { renameBase = typedRename.map { _ in RenameBase(title: name, version: knownVersion) } }
        }
        guard let left = leftWhileRenaming, renaming == nil else { return }
        leftWhileRenaming = nil
        giveBackRename(reason: reason ?? left)
    }

    /// A rename refused because the view was renamed elsewhere starts again from the view as it is now.
    func restartRename(from view: LibraryView) {
        guard renaming == nil, typedRename != nil else { return }
        renameBase = RenameBase(title: view.title, version: view.version)
    }

    /// The panel read the view again: a name the person has not typed over follows it.
    func follow(_ view: LibraryView) {
        let following = name == knownTitle
        knownTitle = view.title
        knownVersion = view.version
        if following { name = view.title }
    }

    /// The view is gone, so the name typed for it has nowhere to go. Whether there was one to give back.
    @discardableResult
    func handOffBecauseGone() -> Bool {
        leftWhileRenaming = nil
        guard typedRename != nil else { return false }
        giveBackRename(reason: String(localized: "The view was deleted before it was renamed."))
        return true
    }

    private func giveBackRename(reason: String) {
        guard let name = typedRename else { return }
        giveBackRename(name: name, reason: reason)
    }

    private func giveBackRename(name: String, reason: String) {
        guard name != handedOffName else { return }
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
