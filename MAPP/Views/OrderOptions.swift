import SwiftUI

/// Where the list's starting order is kept (Settings > Lists): the sort and the sections by date a place shows until it
/// has its own (`Browser.datedList`).
enum OrderKey {
    static let sort = "noteSort"
    static let groupsByDate = "groupsByDate"
    static let all = [sort, groupsByDate]
}

/// Reads the stored order, for views that lay the list out rather than change it.
@propertyWrapper
struct StoredOrder: DynamicProperty {
    @AppStorage(OrderKey.sort) private var sort = ItemOrder().sort
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = ItemOrder().groupsByDate

    init() {}

    var wrappedValue: ItemOrder { ItemOrder(sort: sort, groupsByDate: groupsByDate) }
}
