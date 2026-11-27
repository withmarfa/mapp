import SwiftUI

/// The starting density, scope, sort and grouping for lists.
struct ListsPage: View {
    @AppStorage(ListKey.density) private var density = Density.standard
    @AppStorage private var storedScope: ListScope
    @AppStorage(OrderKey.sort) private var sort = ItemOrder().sort
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = ItemOrder().groupsByDate

    init(defaults: UserDefaults? = nil) {
        _storedScope = AppStorage(wrappedValue: .all, ListScope.defaultScopeKey, store: defaults)
    }

    var scope: Binding<ListScope> {
        Binding { storedScope == .library ? .library : .all } set: { storedScope = $0 }
    }

    var body: some View {
        SettingsPageColumn {
            SettingsSection("Density") {
                ChoiceTiles(
                    choices: Density.allCases.map { option in
                        .init(value: option, title: Text(verbatim: option.title), picture: AnyView(DensityPicture(density: option)))
                    },
                    selection: $density)
                    .accessibilityIdentifier("ListsDensity")
            }
            SettingsSection("Defaults", footer: "A view or a place can set its own.") {
                SettingsRow("From", line: "What a type, a collection or a new view lists.", lines: nil) {
                    SettingsPopUp(title: "From", selection: scope) {
                        Text("All Items").tag(ListScope.all)
                        Text("Library").tag(ListScope.library)
                    }
                    .accessibilityIdentifier("ListScope")
                }
                SettingsRow("Sort by") {
                    SettingsPopUp(title: "Sort by", selection: $sort) {
                        ForEach(ItemSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("ItemSort")
                }
                SettingsRow("Group by", look: sort == .title ? .off : .normal) {
                    SettingsPopUp(title: "Group by", selection: $groupsByDate) {
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

/// A density's tile: the real list row, as the list draws it at that density, over a few sample items of different
/// types. Standard shows a picture on its first row, drawn for the tile; nothing is read from the library or the network.
private struct DensityPicture: View {
    let density: Density

    private static let note = "lucide:sticky-note"
    private static let task = "lucide:square-check-big"
    private static let bookmark = "lucide:bookmark"

    private var samples: [RowContent] {
        [
            row(Self.note, String(localized: "Note"), String(localized: "Kiln log, firing 14"),
                String(localized: "Bisque, 1000°C, nine hours. Two test tiles cracked on the lower shelf, both from the new clay."), String(localized: "Saturday")),
            row(
                Self.task, String(localized: "Task"), String(localized: "Reply to Ines about the zine proofs"),
                String(localized: "Pages 6 and 7 are the wrong way round in the second proofs."), String(localized: "Thursday"),
                status: String(localized: "Not Started")),
            row(Self.note, String(localized: "Note"), String(localized: "Lewes Trust: comments on the draft"), nil, String(localized: "Tuesday")),
            row("lucide:user", String(localized: "Person"), String(localized: "Ines Barros"), nil, String(localized: "16 Nov")),
            row(Self.task, String(localized: "Task"), String(localized: "Keep the gallery grid aligned when the window resizes"), nil, String(localized: "12 Nov")),
            row(Self.bookmark, String(localized: "Bookmark"), String(localized: "Paper for the zine"), nil, String(localized: "8 Nov")),
        ]
    }

    /// What the list makes of an item of a type: the type's chip first, then its status.
    private func row(_ icon: String, _ type: String, _ title: String, _ line: String?, _ date: String, status: String? = nil) -> RowContent {
        var content = RowContent(title: title, date: date, secondary: line, typeIcon: icon, typeLabel: type, mixesTypes: true)
        content.chips = [.type(icon: icon, label: type)] + (status.map { [.status(.notStarted, label: $0)] } ?? [])
        return content
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, SettingsTokens.Metric.column / 2)
            rows
                .frame(width: width, height: width / SettingsTokens.Metric.choiceAspect, alignment: .topLeading)
                .scaleEffect(geometry.size.width / width, anchor: .topLeading)
        }
        .background(SettingsTokens.card)
        .allowsHitTesting(false)
    }

    private var rows: some View {
        let isCompact = density == .compact
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(samples.prefix(isCompact ? 6 : 2).enumerated()), id: \.offset) { index, content in
                ItemRow(content: content, density: density, showsSample: !isCompact && index == 0)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(SettingsTokens.rule)
                                .frame(height: SettingsTokens.Metric.ruleThickness)
                        }
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsTokens.Metric.previewRowSide)
        .padding(.top, SettingsTokens.Metric.previewCardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
