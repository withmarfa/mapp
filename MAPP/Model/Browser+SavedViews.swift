import Foundation

/// Following the saved view a window shows: its order, grouping and filters, and saving the window's changes to it.
extension Browser {
    /// A saved view the window is about to save, rename, update or delete, which asks the person first.
    nonisolated enum ViewEditing: Hashable, Identifiable {
        case new
        case rename(ItemID)
        case update(ItemID)
        case delete(ItemID)
        var id: Self { self }
    }

    /// The order and grouping a view opened with, and the version of the view they came from, which an update of
    /// them is based on.
    struct ViewSeed: Hashable {
        let version: Int64
        let options: ItemTableOptions
    }

    /// Shows a view's own order and grouping the first time the window opens it, and again when the view changes,
    /// unless the person has changed them since: those stay, and an update of them is based on what they changed.
    func followView(in library: any ItemLibrary) {
        guard case .view(let id) = item, let view = library.views.first(where: { $0.id == id }) else { return }
        if let seed = viewSeeds[id] {
            guard seed.version != view.version, !ViewDraft.differs(tableOptions[item], from: seed.options) else { return }
        }
        seed(view)
    }

    private func seed(_ view: LibraryView) {
        let place = SidebarItem.view(view.id)
        var options = ViewDraft.options(for: view)
        let collapsed = tableOptions[place]?.collapsed
        viewSeeds[view.id] = ViewSeed(version: view.version, options: options)
        options.collapsed = collapsed
        tableOptions[place] = options
    }

    /// Whether the window's order, grouping or filters differ from those of the view it shows.
    var hasViewChanges: Bool {
        guard case .view(let id) = item, let seed = viewSeeds[id] else { return false }
        // Only the table shows a view's order, grouping and filters, so only the table offers to update it.
        return viewMode == .table && ViewDraft.differs(tableOptions[item], from: seed.options)
    }

    /// The change that saves the window's choices to the view it shows, the version it is based on, and what of
    /// the window it leaves out.
    func viewUpdate(_ window: ViewDraft.Window, in library: any ItemLibrary) -> ViewUpdate? {
        guard case .view(let id) = item, let seed = viewSeeds[id], let view = library.views.first(where: { $0.id == id }) else {
            return nil
        }
        let update = ViewDraft.change(window, options: tableOptions[item], seed: seed.options, view: view)
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

    /// After an update the view holds the window's choices, so its filters are the view's own.
    func viewUpdated(_ view: LibraryView) {
        seed(view)
    }

    /// An update refused because the view changed elsewhere puts the window back to the view as the library holds
    /// it, and to its next version when that arrives.
    func viewRefused(_ id: ItemID, in library: any ItemLibrary) {
        viewSeeds[id] = nil
        followView(in: library)
    }
}
