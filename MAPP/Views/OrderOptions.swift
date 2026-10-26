import SwiftUI

/// Where the list's order is kept, shared by every view that reads or sets it.
enum OrderKey {
    static let sort = "noteSort"
    static let groupsByDate = "groupsByDate"
    static let all = [sort, groupsByDate]
}

/// The list's sort and grouping, offered alike by the View menu, the View Options menu of the list and the gallery
/// (`CurrentViewOptions`) and Settings.
struct OrderOptions: View {
    @AppStorage(OrderKey.sort) private var sort = NoteOrder().sort
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = NoteOrder().groupsByDate

    var body: some View {
        picker
        group
    }

    private var picker: some View {
        Picker("Sort By", systemImage: "arrow.up.arrow.down", selection: $sort) {
            ForEach(NoteSort.allCases, id: \.self) { sort in
                Text(sort.title)
            }
        }
        .accessibilityLabel("Sort By")
        .accessibilityIdentifier("NoteSort")
    }

    private var group: some View {
        // Title order has no dates to group by.
        Toggle("Group by Date", systemImage: "calendar", isOn: $groupsByDate)
            .accessibilityLabel("Group by Date")
            .accessibilityIdentifier("GroupByDate")
            .disabled(sort == .title)
    }
}

/// Reads the stored order, for views that lay the list out rather than change it.
@propertyWrapper
struct StoredOrder: DynamicProperty {
    @AppStorage(OrderKey.sort) private var sort = NoteOrder().sort
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = NoteOrder().groupsByDate

    init() {}

    var wrappedValue: NoteOrder { NoteOrder(sort: sort, groupsByDate: groupsByDate) }
}
