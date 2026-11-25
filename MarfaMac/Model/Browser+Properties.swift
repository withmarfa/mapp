import Foundation

/// The open place's Properties list: a saved view's, kept in its Mac settings, or a place's, kept in its default view. Every
/// layout reads it, the table as its columns (`shownColumns`) and the rest as the looks they draw their chips from
/// (`propertyLooks`), and every control that shows, hides or orders a property asks here.
extension Browser {
    /// The list the window shows for the open place. Empty is "As in Layouts": the types' looks, untouched.
    var properties: ViewProperties {
        if let id = shown.savedView { macSettings(for: id).properties } else { placeProperties[shown] ?? ViewProperties() }
    }

    /// Changes the list. A saved view's is kept in the app's settings as it is made, and a place's in its default
    /// view. Undo takes either back.
    func changeProperties(_ change: (inout ViewProperties) -> Void) {
        if let id = shown.savedView {
            changeViewSettings(id) { change(&$0.properties) }
            return
        }
        let place = shown
        let before = properties
        var next = before
        change(&next)
        guard next != before else { return }
        setPlaceProperties(next, before: before, in: place)
    }

    private func setPlaceProperties(_ next: ViewProperties, before: ViewProperties, in place: PlaceView) {
        placeProperties[place] = next.isChanged ? next : nil
        updatePlaceDefault(place) { $0.properties = next }
        registerUndo(String(localized: "Change Properties")) { browser in
            guard browser.shown == place else { return }
            browser.setPlaceProperties(before, before: next, in: place)
        }
    }

    /// The properties the table shows as columns, in order.
    func shownColumns(_ columns: [ItemTableColumn]) -> [ItemTableColumn] {
        properties.shownColumns(columns)
    }

    func showsColumn(_ column: ItemTableColumn) -> Bool {
        properties.isShown(column)
    }

    func setColumn(_ column: ItemTableColumn, shown: Bool) {
        changeProperties { $0.setShown(column, shown) }
    }

    /// Use Layouts: each item shows its own type's look again.
    func useLayouts() {
        changeProperties { $0.reset() }
    }

    /// The looks a row, a card or a timeline row is drawn from: each type's own until the list is changed, then the
    /// list's. The table reads the types' own looks for the columns it starts from, never these.
    func propertyLooks(in library: any ItemLibrary) -> [TypeID: TypeLook] {
        let base = looks(in: library)
        let properties = properties
        guard properties.isChanged else { return base }
        return properties.looks(base, columns: tableContent(in: library).columns, catalogue: library.catalogue)
    }

    /// The properties the open layout lists: every column in a table, and in another layout those a chip can say, less
    /// what its own arrangement says already: the field a board's lanes are, which a card never repeats, and the date a
    /// timeline places by.
    func offeredProperties(in library: any ItemLibrary) -> [ItemTableColumn] {
        let columns = tableContent(in: library).columns
        var leaving: Set<String> = []
        switch viewMode {
        case .board:
            if case .column(let id, let mode)? = boardGrouping(in: library) {
                leaving.insert(id)
                if mode == .statusGroups { leaving.formUnion(columns.filter(\.isStatus).map(\.id)) }
            }
        case .timeline:
            let fields = timelineFieldChoices(in: library)
            if let key = ItemTimelineLayout.selectedField(timelineFields[shown], fields: fields) { leaving.insert(Self.fieldColumnPrefix + key) }
        default:
            break
        }
        return ViewProperties.offered(
            columns, in: viewMode, leaving: leaving, looks: looks(in: library), types: layoutTypes(in: library).map(\.id),
            catalogue: library.catalogue)
    }

    // MARK: Edit Layouts

    /// The types the place lists, by name, whose pages in Settings > Layouts Edit Layouts… leads to: the types it lists
    /// and those of the items it shows.
    func layoutTypes(in library: any ItemLibrary) -> [ItemTypeInfo] {
        let catalogue = library.catalogue
        let types = listedTypes(in: library).union(tableContent(in: library).allRows.map(\.item.type))
        return types.compactMap { catalogue.itemTypes[$0] }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// Opens Settings > Layouts at one type's page.
    func showLayouts(of type: ItemTypeInfo) {
        showSettings(.layouts, subpage: LayoutsSubpage.subpage(for: type.id, label: type.plural))
    }
}
