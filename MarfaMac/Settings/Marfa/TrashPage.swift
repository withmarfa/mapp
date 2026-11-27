import Marfa
import SwiftUI

/// Trash opens the selection page through Select Items or Show All so individual items can be permanently deleted.
struct TrashPage: View {
    static let allDeleted = SettingsSubpage(id: "all-deleted", title: String(localized: "All Deleted Items"))

    let host: any MarfaSettingsHost
    let showsAll: Bool
    @Environment(\.settingsNavigation) private var navigation
    @State private var search = ""
    @State private var kind: String?
    @State private var selection: Set<String> = []

    private var settings: InstanceSettingsModel { host.instanceSettings }
    private var canChangeRetention: Bool { host.grants.contains(.configManage) && settings.isAvailable }

    private var kinds: [String] { Set(host.deletedItems.map(\.kind)).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    private var items: [MarfaDeletedItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return host.deletedItems.filter { item in
            (kind == nil || item.kind == kind) && (query.isEmpty || item.title.localizedStandardContains(query))
        }
    }

    /// Whether a filter is on, so the table counts what it shows rather than everything in the bin.
    private var isFiltered: Bool { kind != nil || !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private func columns(withType: Bool) -> [SettingsTableColumn<MarfaDeletedItem>] {
        var columns = [SettingsTableColumn<MarfaDeletedItem>("Item") { Text(verbatim: $0.title) }]
        if withType {
            columns.append(SettingsTableColumn("Type", width: SettingsTokens.Metric.Column.label) { Text(verbatim: $0.kind).foregroundStyle(SettingsTokens.secondaryText) })
        }
        columns.append(
            SettingsTableColumn("Deleted", width: SettingsTokens.Metric.Column.day) { item in
                Text(verbatim: Self.when(item.deleted)).foregroundStyle(SettingsTokens.secondaryText)
            })
        columns.append(
            SettingsTableColumn("By", width: SettingsTokens.Metric.Column.address) { item in
                Text(verbatim: item.source ?? "").foregroundStyle(SettingsTokens.secondaryText)
            })
        return columns
    }

    private var filter: some View {
        SettingsTableFilter(choice: $kind, search: $search) {
            Text("All Types").tag(String?.none)
            ForEach(kinds, id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
        }
    }

    private var restore: SettingsRowAction<MarfaDeletedItem> {
        SettingsRowAction(title: "Restore") { host.restoreDeleted([$0.id]) }
    }

    var body: some View {
        Group {
            if showsAll { allPage } else { overview }
        }
        .task(id: host.serverAddress) { if host.grants.contains(.configManage) { await settings.load() } }
        .instanceSettingsQuestion(settings)
    }

    private var overview: some View {
        SettingsPageColumn {
            SettingsSection(
                "Cleanup",
                footer: canChangeRetention ? nil : host.deletedRetentionDays.map { LocalizedStringKey("Deleted items are kept for \($0) days.") },
                accessory: {
                    if !items.isEmpty && items.count <= SettingsTokens.Metric.tablePreviewThreshold {
                        SettingsButton("Select Items") { navigation?.push(Self.allDeleted) }
                    }
                }
            ) {
                if canChangeRetention {
                    InstanceChoiceRow(
                        model: settings, setting: .trashRetentionDays, among: [.trashRetentionDays],
                        line: "Items wait here first, so they can come back.")
                }
                SettingsRow(
                    "Trash",
                    line: host.deletedCount == 0 ? "Nothing is waiting here." : "Permanently deletes \(host.deletedCount.formatted()) items."
                ) {
                    SettingsButton("Empty Trash", role: .destructive) { host.emptyDeleted() }
                        .disabled(host.deletedCount == 0 || !host.canDeletePermanently)
                        .accessibilityIdentifier("TrashEmpty")
                }
            }
            if canChangeRetention { InstanceStatusLine(model: settings, settings: [.trashRetentionDays]) }
            SettingsSection(name: Text("Deleted Items"), accessory: { filter }) {
                if host.deletedCount == 0 {
                    SettingsEmptyCard(
                        symbol: "trash", title: Text("Trash Is Empty"),
                        line: Text("Items you delete wait here before they are permanently deleted."))
                } else {
                    SettingsSectionTable(
                        rows: items, columns: columns(withType: false), action: restore,
                        showAll: { navigation?.push(Self.allDeleted) })
                }
            }
        }
        .accessibilityIdentifier("TrashPage")
    }

    private var allPage: some View {
        SettingsPageTable(
            rows: items, columns: columns(withType: true), count: Text("\((isFiltered ? items.count : host.deletedCount).formatted()) items"), selection: $selection,
            filter: { filter },
            foot: {
                SettingsButton("Permanently Delete", role: .destructive, small: true) { host.deleteDeletedPermanently(selection) }
                    .disabled(selection.isEmpty || !host.canDeletePermanently)
                SettingsButton("Restore", small: true) {
                    host.restoreDeleted(selection)
                    selection = []
                }
                .disabled(selection.isEmpty)
            }
        )
        .onChange(of: host.deletedItems.map(\.id)) { selection.formIntersection(host.deletedItems.map(\.id)) }
        .accessibilityIdentifier("TrashAllPage")
    }

    /// When an item was deleted, as a table says a day (`DateDisplay`).
    static func when(_ date: Date?, now: Date = .now, calendar: Calendar = .current, format: DateFormat = .stored()) -> String {
        guard let date else { return "" }
        return DateDisplay.text(of: date, hasTime: false, place: .table, format: format, now: now, calendar: calendar)
    }
}
