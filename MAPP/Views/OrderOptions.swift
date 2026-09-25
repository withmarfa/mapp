import SwiftUI

/// Where the list's order is kept, shared by every view that reads or sets it.
enum OrderKey {
    static let sort = "noteSort"
    static let groupsByDate = "groupsByDate"
}

/// The list's sort and grouping, offered alike by the View menu, the list's toolbar and Settings.
struct OrderOptions: View {
    @AppStorage(OrderKey.sort) private var sort: NoteSort = .dateEdited
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = true

    var body: some View {
        Picker("Sort By", systemImage: "arrow.up.arrow.down", selection: $sort) {
            ForEach(NoteSort.allCases, id: \.self) { sort in
                Text(sort.title)
            }
        }
        // Title order has no dates to group by.
        Toggle("Group by Date", systemImage: "calendar", isOn: $groupsByDate)
            .disabled(sort == .title)
    }
}

/// Reads the stored order, for views that lay the list out rather than change it.
@propertyWrapper
struct StoredOrder: DynamicProperty {
    @AppStorage(OrderKey.sort) private var sort: NoteSort = .dateEdited
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = true

    init() {}

    var wrappedValue: NoteOrder { NoteOrder(sort: sort, groupsByDate: groupsByDate) }
}
