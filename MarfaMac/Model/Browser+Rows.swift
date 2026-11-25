import Foundation

extension Browser {
    /// What the list tells its rows about itself: whether its rows name their type, which date it is sorted by, whether they
    /// show a picture (a Standard list's do) and the day.
    /// A list grouped by type names each type once, in its group's header, so its rows leave the type off.
    /// It reads the items shown, so it holds for every place, search results and Include Kinds alike. The sort is the
    /// table's resolved one, since a saved view stores its sort by column identifier alone.
    func rowList(
        of items: [Item], in library: any ItemLibrary, order: ItemOrder, now: Date, format: DateFormat, density: Density = .standard,
        calendar: Calendar = .current
    ) -> RowList {
        let arranged = listShape?.arranged == true && !ordersByRelevance
        var groupedByType = false
        if arranged, let id = tableOptions[shown]?.grouping.columnID { groupedByType = id == ItemTableColumn.type.id }
        return RowList(
            mixesTypes: !groupedByType && Set(items.lazy.map(\.type)).count > 1,
            date: RowDateSource.of(
                sort: arranged ? tableContent(in: library).sort.first : nil, order: order,
                ordersItself: keepsPlaceOrder || ordersByRelevance),
            format: format, showsPictures: density == .standard, day: calendar.startOfDay(for: now))
    }
}
