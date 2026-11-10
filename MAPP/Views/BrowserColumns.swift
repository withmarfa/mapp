import SwiftUI

/// The table's columns for the window's place. A saved view's are stored for this Mac as they are changed (`ViewColumns`); any
/// other place keeps its own too (`ItemTableColumnLayouts`), so every control that shows or hides a column asks here.
extension Browser {
    private var columnsViewID: ItemID? {
        if case .view(let id) = item { id } else { nil }
    }

    /// The columns the table shows, in order.
    func shownColumns(_ columns: [ItemTableColumn], stored: Data) -> [ItemTableColumn] {
        if let id = columnsViewID { return macSettings(for: id).columns.shownColumns(columns) }
        return ItemTableColumnLayouts.shown(columns, in: ItemTableColumnLayouts.layout(for: item, in: stored))
    }

    func showsColumn(_ column: ItemTableColumn, stored: Data) -> Bool {
        if let id = columnsViewID { return macSettings(for: id).columns.isShown(column) }
        return ItemTableColumnLayouts.layout(for: item, in: stored).shows(column)
    }

    func setColumn(_ column: ItemTableColumn, shown: Bool, stored: Binding<Data>) {
        if let id = columnsViewID {
            changeViewSettings(id) { $0.columns.setShown(column, shown) }
        } else {
            var layout = ItemTableColumnLayouts.layout(for: item, in: stored.wrappedValue)
            layout[visibility: column.id] = shown ? .visible : .hidden
            stored.wrappedValue = ItemTableColumnLayouts.storing(layout, for: item, in: stored.wrappedValue)
        }
    }

    func resetColumns(stored: Binding<Data>) {
        if let id = columnsViewID {
            changeViewSettings(id) { $0.columns.reset() }
        } else {
            stored.wrappedValue = ItemTableColumnLayouts.storing(TableColumnCustomization(), for: item, in: stored.wrappedValue)
        }
    }
}
