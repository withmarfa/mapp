import SwiftUI

/// The Lists page: how much each row says, and the starting order of a place's list: the sort and the sections by date a
/// place shows until its own Sort by or Group by is chosen in View Options. What a
/// list leaves out belongs to Search, never here.
struct ListsPage: View {
    @AppStorage(ListKey.density) private var density = Density.standard
    @AppStorage(OrderKey.sort) private var sort = ItemOrder().sort
    @AppStorage(ListKey.showsQuickAdd) private var showsQuickAdd = false
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = ItemOrder().groupsByDate

    var body: some View {
        SettingsPageColumn {
            SettingsSection("Density", line: "A view or a place can set its own.") {
                ChoiceTiles(
                    choices: Density.allCases.map { option in
                        .init(value: option, title: Text(verbatim: option.title), picture: AnyView(DensityPicture(density: option)))
                    },
                    selection: $density)
                    .accessibilityIdentifier("ListsDensity")
            }
            SettingsSection("Order", line: "The order a place starts in until you change its Sort by or Group by in View Options.") {
                SettingsRow("Sort By") {
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
            SettingsSection("Items Page") {
                SettingsRow("Show Quick Add Options", line: "Tiles above the table for making a new item of a type.") {
                    SettingsToggle(title: "Show Quick Add Options", isOn: $showsQuickAdd)
                        .accessibilityIdentifier("ShowsQuickAdd")
                }
            }
        }
        .accessibilityIdentifier("ListsPage")
    }
}

/// A density's tile: the real list row, as the list draws it at that density, over a few sample items of different
/// types. Standard shows a picture on its first row, drawn for the tile; nothing is read from the library or the network.
private struct DensityPicture: View {
    let density: Density

    private static let note = "lucide:sticky-note"
    private static let task = "lucide:square-check-big"
    private static let event = "lucide:calendar"
    private static let bookmark = "lucide:bookmark"

    private var samples: [RowContent] {
        [
            row(Self.note, String(localized: "Note"), String(localized: "Trip to Lisbon"), String(localized: "Flights and the hotel."), String(localized: "12 Nov")),
            row(
                Self.task, String(localized: "Task"), String(localized: "Weekly Review"), String(localized: "Three things for next week."), String(localized: "Mon"),
                status: String(localized: "In Progress")),
            row(Self.note, String(localized: "Note"), String(localized: "Budget"), String(localized: "Where the month went."), String(localized: "4 Nov")),
            row(Self.event, String(localized: "Event"), String(localized: "Dinner with Sam"), nil, String(localized: "3 Nov")),
            row(Self.task, String(localized: "Task"), String(localized: "Renew passport"), nil, String(localized: "2 Nov")),
            row(Self.bookmark, String(localized: "Bookmark"), String(localized: "Oiling an oak worktop"), nil, String(localized: "1 Nov")),
        ]
    }

    /// What the list makes of an item of a type: the type's chip first, then its status.
    private func row(_ icon: String, _ type: String, _ title: String, _ line: String?, _ date: String, status: String? = nil) -> RowContent {
        var content = RowContent(title: title, date: date, secondary: line, typeIcon: icon, typeLabel: type, mixesTypes: true)
        content.chips = [.type(icon: icon, label: type)] + (status.map { [.status(.inProgress, label: $0)] } ?? [])
        return content
    }

    var body: some View {
        let isCompact = density == .compact
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(samples.prefix(isCompact ? 6 : 2).enumerated()), id: \.offset) { index, content in
                ItemRow(content: content, density: density, showsSample: !isCompact && index == 0)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(SettingsTokens.rule)
                                .frame(height: 1)
                        }
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsTokens.card)
        .allowsHitTesting(false)
    }
}
