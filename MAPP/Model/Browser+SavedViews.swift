import Foundation

/// Following the saved view a window shows: its order, grouping, filters and timeline date, and saving the window's changes to it.
extension Browser {
    /// A saved view the window is about to save, rename, update or delete, which asks the person first.
    nonisolated enum ViewEditing: Hashable, Identifiable {
        case new
        case rename(ItemID)
        case update(ItemID)
        case delete(ItemID)
        var id: Self { self }
    }

    /// The order, grouping and filters a view opened with, the date its timeline showed, the types it showed as a
    /// Type filter, and the version of the view they came from, which a save of them is based on.
    struct ViewSeed: Hashable {
        let version: Int64
        let options: ItemTableOptions
        let timelineDate: String?
        let types: [String]?
        /// What to read the view's items with while the window's filters differ from these (`previewQuery`); nil where
        /// the view's own list stands for them.
        let preview: LibraryViewQuery?
    }

    /// Shows a view's own order, grouping and filters the first time the window opens it, and again when the view
    /// changes, unless the person has changed them since: those stay, and a save of them is based on what they
    /// changed. Every layout shows them.
    func followView(in library: any ItemLibrary) {
        guard case .view(let id) = item, let view = library.views.first(where: { $0.id == id }) else { return }
        if let seed = viewSeeds[id] {
            guard seed.version != view.version, !differs(from: seed) else { return }
        }
        seed(view, catalogue: library.catalogue)
    }

    private func seed(_ view: LibraryView, catalogue: Catalogue) {
        let place = SidebarItem.view(view.id)
        var options = ViewDraft.options(for: view, catalogue: catalogue)
        let timelineDate = ViewDraft.timelineDate(of: view)
        let collapsed = tableOptions[place]?.collapsed
        let types = ViewDraft.seededTypes(of: view.query, catalogue: catalogue)
        viewSeeds[view.id] = ViewSeed(
            version: view.version, options: options, timelineDate: timelineDate, types: types,
            preview: ViewDraft.previewQuery(of: view.query, seededTypes: types, catalogue: catalogue))
        options.collapsed = collapsed
        tableOptions[place] = options
        timelineFields[place] = timelineDate
    }

    private func differs(from seed: ViewSeed) -> Bool {
        ViewDraft.differs(tableOptions[item], timelineDate: timelineFields[item], from: seed.options, seedTimelineDate: seed.timelineDate)
    }

    /// Whether the window's filters, order, grouping or timeline date differ from those of the view it shows, in
    /// whichever layout it shows them.
    var hasViewChanges: Bool {
        guard case .view(let id) = item, let seed = viewSeeds[id] else { return false }
        return differs(from: seed)
    }

    /// The query the window reads the view's items with while its filters differ from the view's own, and nil while
    /// they do not: the view's list is then the library's own reading of the saved view. A window that opened the
    /// view keeps the query of that version, whatever the view has since become elsewhere, as it keeps its filters.
    var viewPreview: (view: ItemID, query: LibraryViewQuery)? {
        guard case .view(let id) = item, let seed = viewSeeds[id], let query = seed.preview,
              (tableOptions[item] ?? ItemTableOptions()).filterChoices != seed.options.filterChoices else { return nil }
        return (id, query)
    }

    /// Puts the window back to the view as the library holds it, dropping what the person changed.
    func revertView(in library: any ItemLibrary) {
        guard case .view(let id) = item else { return }
        viewRefused(id, in: library)
    }

    /// The change that saves the window's choices to the view it shows, the version it is based on, and what of
    /// the window it leaves out.
    func viewUpdate(_ window: ViewDraft.Window, in library: any ItemLibrary) -> ViewUpdate? {
        guard case .view(let id) = item, let seed = viewSeeds[id], let view = library.views.first(where: { $0.id == id }) else {
            return nil
        }
        let update = ViewDraft.change(
            window, options: tableOptions[item], seed: seed.options, seedTimelineDate: seed.timelineDate, seededTypes: seed.types,
            view: view, catalogue: library.catalogue)
        return ViewUpdate(view: view, change: update.change, baseVersion: seed.version, unkept: update.unkept, unchanged: update.unchanged)
    }

    struct ViewUpdate {
        let view: LibraryView
        let change: LibraryViewChange
        let baseVersion: Int64
        /// What of the window the view will not keep.
        let unkept: [ViewDraft.Unkept]
        /// The conditions of the view's filter the window cannot show, which the update leaves as they are.
        let unchanged: [String]
    }

    /// After a save the view holds the window's choices, so its filters are the view's own.
    func viewUpdated(_ view: LibraryView, in library: any ItemLibrary) {
        seed(view, catalogue: library.catalogue)
    }

    /// A save refused because the view changed elsewhere puts the window back to the view as the library holds
    /// it, and to its next version when that arrives.
    func viewRefused(_ id: ItemID, in library: any ItemLibrary) {
        viewSeeds[id] = nil
        followView(in: library)
    }
}
