import Foundation

extension Browser {
    /// What the list tells its rows about itself: whether it holds several types, which date it is sorted by, and the day.
    /// It reads the items shown, so it holds for every place, search results and Include Subtypes alike. The sort is the
    /// table's resolved one, since a saved view stores its sort by column identifier alone.
    func rowList(
        of items: [Item], in library: any ItemLibrary, order: NoteOrder, now: Date, format: DateFormat, calendar: Calendar = .current
    ) -> RowList {
        let arranged = listShape?.arranged == true && !ordersByRelevance
        return RowList(
            mixesTypes: Set(items.lazy.map(\.type)).count > 1,
            date: RowDateSource.of(
                sort: arranged ? tableContent(in: library).sort.first : nil, order: order,
                ordersItself: keepsPlaceOrder || ordersByRelevance),
            format: format, day: calendar.startOfDay(for: now))
    }
}
