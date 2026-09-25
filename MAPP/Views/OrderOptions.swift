import SwiftUI

/// The list's sort and grouping, offered alike by the View menu, the list's toolbar and Settings.
struct OrderOptions: View {
    @AppStorage("noteSort") private var sort: NoteSort = .dateEdited
    @AppStorage("groupsByDate") private var groupsByDate = true

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
    @AppStorage("noteSort") private var sort: NoteSort = .dateEdited
    @AppStorage("groupsByDate") private var groupsByDate = true

    init() {}

    var wrappedValue: NoteOrder { NoteOrder(sort: sort, groupsByDate: groupsByDate) }
}
