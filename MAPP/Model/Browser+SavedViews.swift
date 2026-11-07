import Foundation

/// Following the saved view a window shows: its order, grouping, filters and timeline date from Marfa, and its
/// layout, columns and cards from this Mac (`ViewLayouts`). Whatever the person changes is held for the window until Save
/// keeps it (`Browser+ViewPanel`) or Revert drops it.
extension Browser {
    /// The order, grouping and filters a view opened with, the date its timeline showed, the types it showed as a
    /// Type filter, the version of the view they came from, which a save of them is based on, and the settings the Mac
    /// held for it.
    struct ViewSeed: Hashable {
        let version: Int64
        let options: ItemTableOptions
        let timelineDate: String?
        let types: [String]?
        /// What to read the view's items with while the window's filters differ from these (`previewQuery`); nil where
        /// the view's own list stands for them.
        let preview: LibraryViewQuery?
        let mac: ViewMacSettings
        /// The layout the window showed when it took the seed, which stands for one the Mac holds none of: the view
        /// follows the window, so a layout the person chose is a change from it, and Revert goes back to it.
        let windowLayout: ItemViewMode

        /// The layout a Revert puts back and a choice is compared with.
        var ownLayout: ItemViewMode { mac.layout ?? windowLayout }
    }

    /// Shows a view's own order, grouping and filters the first time the window opens it, and again when the view
    /// changes, unless the person has changed them since: those stay, and a save of them is based on what they
    /// changed. Every layout shows them, and the view opens in the layout held for it or kept on this Mac.
    func followView(in library: any ItemLibrary) {
        guard case .view(let id) = item, let view = library.views.first(where: { $0.id == id }) else { return }
        guard let seed = viewSeeds[id] else {
            apply(layout: ViewLayouts.stored(in: defaults).settings(for: id)?.layout, in: library)
            return self.seed(view, catalogue: library.catalogue)
        }
        apply(layout: viewWorking[id]?.layout ?? seed.mac.layout, in: library)
        guard seed.version != view.version, !differs(id, from: seed) else { return }
        self.seed(view, catalogue: library.catalogue)
    }

    private func seed(_ view: LibraryView, catalogue: Catalogue) {
        let place = SidebarItem.view(view.id)
        var options = ViewDraft.options(for: view, catalogue: catalogue)
        let timelineDate = ViewDraft.timelineDate(of: view)
        let collapsed = tableOptions[place]?.collapsed
        let mac = ViewLayouts.stored(in: defaults).settings(for: view.id) ?? ViewMacSettings()
        let types = ViewDraft.seededTypes(of: view.query, catalogue: catalogue)
        viewSeeds[view.id] = ViewSeed(
            version: view.version, options: options, timelineDate: timelineDate, types: types,
            preview: ViewDraft.previewQuery(of: view.query, seededTypes: types, catalogue: catalogue), mac: mac, windowLayout: viewMode)
        viewWorking[view.id] = nil
        options.collapsed = collapsed
        tableOptions[place] = options
        timelineFields[place] = timelineDate
    }

    private func differs(_ id: ItemID, from seed: ViewSeed) -> Bool {
        let place = SidebarItem.view(id)
        return ViewDraft.differs(tableOptions[place], timelineDate: timelineFields[place], from: seed.options, seedTimelineDate: seed.timelineDate)
            || viewWorking[id].map { !$0.sameChoices(as: seed.mac) } == true
    }

    /// Shows the layout without taking it for a change of the person's, which only the person's own choice is.
    private func apply(layout: ItemViewMode?, in library: any ItemLibrary) {
        guard let layout, layout != viewMode, availableViewModes(in: library).contains(layout) else { return }
        set(layout: layout)
    }

    func set(layout: ItemViewMode) {
        isApplyingLayout = true
        defer { isApplyingLayout = false }
        viewMode = layout
    }

    /// Whether the window's filters, order, grouping, timeline date, layout, columns, empty groups or cards differ from
    /// those of the view it shows, in whichever layout it shows them.
    var hasViewChanges: Bool {
        guard case .view(let id) = item, let seed = viewSeeds[id] else { return false }
        return differs(id, from: seed)
    }

    /// The query the window reads the view's items with while its filters differ from the view's own, and nil while
    /// they do not: the view's list is then the library's own reading of the saved view. A window that opened the
    /// view keeps the query of that version, whatever the view has since become elsewhere, as it keeps its filters.
    var viewPreview: (view: ItemID, query: LibraryViewQuery)? {
        guard case .view(let id) = item, let seed = viewSeeds[id], let query = seed.preview,
              (tableOptions[item] ?? ItemTableOptions()).filterChoices != seed.options.filterChoices else { return nil }
        return (id, query)
    }

    // MARK: This Mac's settings for a view

    /// The layout, columns, empty groups and cards the window shows for a view: what the person has changed and not saved,
    /// else what the Mac holds.
    func macSettings(for id: ItemID) -> ViewMacSettings {
        viewWorking[id] ?? viewSeeds[id]?.mac ?? ViewLayouts.stored(in: defaults).settings(for: id) ?? ViewMacSettings()
    }

    /// Whether the board leaves out a lane with no items: a saved view's choice, held until Save.
    var hidesEmptyGroups: Bool {
        guard case .view(let id) = item else { return false }
        return macSettings(for: id).hidesEmptyGroups
    }

    /// What the gallery draws on each card in the open place: a saved view's choice, held until Save, else the
    /// window's own for the place.
    var cards: ViewCards {
        if case .view(let id) = item { macSettings(for: id).cards } else { placeCards[item] ?? ViewCards() }
    }

    /// Changes what the gallery draws on each card. A saved view's change stays unsaved until Save, and a place's lasts
    /// as long as the window.
    func changeCards(_ change: (inout ViewCards) -> Void) {
        if case .view(let id) = item {
            changeViewSettings(id) { change(&$0.cards) }
        } else {
            var cards = placeCards[item] ?? ViewCards()
            change(&cards)
            placeCards[item] = cards == ViewCards() ? nil : cards
        }
    }

    /// Changes the window's settings for a view, which stay unsaved until Save.
    func changeViewSettings(_ id: ItemID, _ change: (inout ViewMacSettings) -> Void) {
        var settings = macSettings(for: id)
        change(&settings)
        guard settings != macSettings(for: id) else { return }
        viewWorking[id] = settings
    }

    /// Takes the person's own change of layout, in a view, for an unsaved one. Back in the layout the view opened in,
    /// where the Mac holds none for it, is no change.
    func recordLayout() {
        guard !isApplyingLayout, case .view(let id) = item, let seed = viewSeeds[id] else { return }
        changeViewSettings(id) { $0.layout = seed.mac.layout == nil && viewMode == seed.windowLayout ? nil : viewMode }
    }

    /// Keeps the table's column widths as the person drags them, at once: a width is not a choice a Save waits for.
    func keepWidths(_ widths: Data?, of id: ItemID) {
        ViewLayouts.update(in: defaults) {
            var settings = $0.settings(for: id) ?? ViewMacSettings()
            guard settings.widths != widths else { return }
            settings.widths = widths
            $0.set(settings, for: id)
        }
    }

    // MARK: Reverting and saving

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

    /// A save refused because the view changed elsewhere, or a revert, puts the window back to the view as the
    /// library holds it (its next version when that arrives), in the layout the Mac keeps for it.
    func viewRefused(_ id: ItemID, in library: any ItemLibrary) {
        if case .view(id) = item, let layout = viewSeeds[id]?.ownLayout, layout != viewMode { set(layout: layout) }
        viewSeeds[id] = nil
        viewWorking[id] = nil
        followView(in: library)
    }

    /// Forgets a view this window deleted, and what the Mac kept for it. Only a delete from here forgets the Mac's
    /// settings: a view missing from a list proves nothing, since a read that failed publishes an empty one.
    func forgetView(_ id: ItemID) {
        viewSeeds[id] = nil
        viewWorking[id] = nil
        ViewLayouts.update(in: defaults) { $0.forget(id) }
    }

    /// Deletes the view for good, once the person confirmed. Nothing of it stays on this Mac, and its panel closes
    /// with nothing said: the person did this.
    func deleteView(_ id: ItemID, in library: any ItemLibrary) async {
        deletingView = nil
        viewsBeingDeleted.insert(id)
        defer { viewsBeingDeleted.remove(id) }
        guard await library.deleteView(id) else { return }
        if viewPanel?.viewID == id { viewPanel = nil }
        forgetView(id)
    }
}
