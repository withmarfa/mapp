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
    /// The window whose search the order applies to, which adds Relevance while it searches. Nil in Settings and
    /// while no window is in front.
    var browser: Browser?
    @AppStorage(OrderKey.sort) private var sort = NoteOrder().sort
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = NoteOrder().groupsByDate

    var body: some View {
        picker
        group
    }

    private var picker: some View {
        Picker("Sort by", systemImage: "arrow.up.arrow.down", selection: Binding<NoteSort?> {
            browser?.ordersByRelevance == true ? nil : sort
        } set: { choice in
            if let choice { sort = choice }
            browser?.orderSearch(byRelevance: choice == nil)
        }) {
            // Relevance is the search's own order, so it is offered only while the window searches. It leaves the
            // stored sort alone, which comes back when the search ends.
            if browser?.isSearching == true {
                Text("Relevance").tag(NoteSort?.none)
                Divider()
            }
            ForEach(NoteSort.allCases, id: \.self) { sort in
                Text(sort.title).tag(Optional(sort))
            }
        }
        .accessibilityLabel("Sort by")
        .accessibilityIdentifier("NoteSort")
    }

    private var group: some View {
        // Title order has no dates to group by, and relevance lists one section.
        Picker("Group by", systemImage: "calendar", selection: $groupsByDate) {
            Text("None").tag(false)
            Text("Date").tag(true)
        }
        .accessibilityLabel("Group by")
        .accessibilityIdentifier("GroupBy")
        .disabled(sort == .title || browser?.ordersByRelevance == true)
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
