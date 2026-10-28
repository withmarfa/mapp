#if DEBUG
import Foundation

/// The sidebar design experiment's switch: the sidebar and landing page as they are, or the Claude-app-style mock.
/// Delete this file, its knob in `Tuning.shared`, and every `#if DEBUG` branch that reads it once August has chosen,
/// or promote the experiment into the real sidebar.
enum SidebarStyle: String, CaseIterable {
    case current
    case experiment

    static let knob = Knob.picker("sidebar", "style", SidebarStyle.current)

    /// The style the tuning panel has set, read in a view's `body` so the view follows a change at once.
    static var selected: SidebarStyle {
        Tuning.shared.choice(knob, as: SidebarStyle.self) ?? .current
    }
}

/// What the experiment sidebar shows, block by block, from the same plan the real sidebar and Settings > Sidebar read.
/// Every block follows the switches in Settings > Sidebar, so the experiment keeps no list of its own.
@MainActor
struct ExperimentBlocks: Equatable {
    /// The block above the rest, after New and Search: the Browse places that are switched on.
    let top: [SidebarPlace]
    /// The Views block's built-in views, Inbox, Recents and Favorites, each when switched on.
    let builtInViews: [SidebarPlace]
    /// The Views block's saved views below them, in the person's order, when Show Views is on and these are not hidden.
    let savedViews: [LibraryView]
    /// The Types block, where the library has types and Show Types is on.
    let showsTypes: Bool

    /// The one Views block shows while some built-in view or saved view is switched on.
    var showsViews: Bool { !builtInViews.isEmpty || !savedViews.isEmpty }

    init(_ plan: SidebarPlan) {
        top = plan.shownBrowse
        builtInViews = plan.shownTop
        savedViews = plan.shownLibrary.contains(.views) ? plan.shownViews : []
        showsTypes = plan.shownLibrary.contains(.types)
    }
}

/// The Types block shows this many types, with their subtypes, until Show More.
enum ExperimentTypeLimit {
    static let shownCount = 6

    /// The rows of the first `limit` types, each with the subtype rows folded open under it, and whether more types
    /// follow. With `showsAll` every row stays. A type's subtypes are never cut off from it.
    static func rows(
        _ rows: [SidebarPlan.TypeRow], showsAll: Bool, limit: Int = shownCount
    ) -> (rows: [SidebarPlan.TypeRow], hasMore: Bool) {
        let topLevel = rows.filter { $0.depth == 0 }.count
        guard topLevel > limit else { return (rows, false) }
        guard !showsAll else { return (rows, true) }
        var seen = 0
        let kept = rows.prefix { row in
            if row.depth == 0 { seen += 1 }
            return seen <= limit
        }
        return (Array(kept), true)
    }
}

extension Browser {
    /// Whether the experiment's "Make something new" row stands above the page: on the Sources and Collections indexes,
    /// and on Items while it shows in a layout that spans the window (the gallery, table, board or timeline), not once
    /// an item is open.
    var offersExperimentLanding: Bool {
        if showsSettings { return false }
        return showsSidebarIndex || (item == .allNotes && showsCollection)
    }

    /// Choosing Items in the experiment sidebar. The landing is Items in a layout that spans the window, so a window
    /// on the list moves to the gallery; the person's own choice of another layout stands.
    func showItemsLanding(in library: any ItemLibrary, order: NoteOrder) {
        if viewMode == .list { viewMode = .gallery }
        show(.allNotes, in: library, order: order)
    }
}

/// Which types the landing page offers as chips, and which wait under its More chip.
enum ExperimentChips {
    static let shownCount = 4

    /// The types people hold most items of come first, then the rest in the order given. A type with no items still
    /// fills the row, so a new library has chips too.
    static func split(_ options: [ItemTypeOption], usedMost: [TypeID], limit: Int = shownCount) -> (shown: [ItemTypeOption], more: [ItemTypeOption]) {
        var ordered = usedMost.compactMap { id in options.first { $0.id == id } }
        ordered += options.filter { option in !ordered.contains(option) }
        let shown = Array(ordered.prefix(limit))
        return (shown, Array(ordered.dropFirst(limit)))
    }
}
#endif
