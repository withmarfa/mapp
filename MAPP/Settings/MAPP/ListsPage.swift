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
                        .init(value: option, title: Text(verbatim: option.title), picture: AnyView(SettingsRowStylePicture(isCompact: option == .compact)))
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
