import SwiftUI

/// The Lists page: how much each row says and the order every list takes until a view or a place chooses its own. What a
/// list leaves out belongs to Search, never here.
struct ListsPage: View {
    @AppStorage(ListKey.density) private var density = Density.standard
    @AppStorage(OrderKey.sort) private var sort = ItemOrder().sort
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = ItemOrder().groupsByDate

    var body: some View {
        SettingsPageColumn {
            SettingsSection("Density", line: "A view or a place can set its own.") {
                ChoiceTiles(
                    choices: Density.allCases.map { option in
                        .init(value: option, title: Text(verbatim: option.title), picture: AnyView(DensityPicture(density: option)))
                    },
                    selection: $density, columns: 3)
                    .accessibilityIdentifier("ListsDensity")
            }
            SettingsSection("Order") {
                SettingsRow("Sort By", line: "A view or a place can set its own.") {
                    SettingsPopUp(title: "Sort By", selection: $sort) {
                        ForEach(ItemSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("ItemSort")
                }
                SettingsRow("Group By", look: sort == .title ? .off : .normal) {
                    SettingsPopUp(title: "Group By", selection: $groupsByDate) {
                        Text("None").tag(false)
                        Text("Date").tag(true)
                    }
                    .accessibilityIdentifier("GroupBy")
                }
            }
        }
        .accessibilityIdentifier("ListsPage")
    }
}

/// A density's tile: the real list row, as the list draws it at that density, over a few sample items.
private struct DensityPicture: View {
    let density: Density

    private var samples: [RowContent] {
        [
            row(String(localized: "Weekly Review"), String(localized: "Three things for next week."), String(localized: "Mon")),
            row(String(localized: "Trip to Lisbon"), String(localized: "Flights and the hotel."), String(localized: "12 Nov")),
            row(String(localized: "Reading List"), String(localized: "Books to start this year."), String(localized: "9 Nov")),
            row(String(localized: "Budget"), String(localized: "Where the month went."), String(localized: "4 Nov")),
        ]
    }

    private func row(_ title: String, _ line: String, _ date: String) -> RowContent {
        RowContent(title: title, date: date, secondary: line, typeIcon: nil, typeLabel: "", mixesTypes: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(samples.prefix(density == .compact ? 4 : 2), id: \.title) { ItemRow(content: $0, density: density) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsTokens.card)
        .allowsHitTesting(false)
    }
}
