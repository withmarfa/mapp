import Marfa
import SwiftUI

/// The Recently Deleted page: what the server holds in its bin, with Restore on every row, Permanently Delete and Empty.
/// A section shows the latest page of it, and Show All opens the whole list as a page of its own.
struct RecentlyDeletedPage: View {
    static let allDeleted = SettingsSubpage(id: "all-deleted", title: String(localized: "All Deleted Items"))
    private static let pageSize = 8

    let host: any MarfaSettingsHost
    let showsAll: Bool
    @Environment(\.settingsPush) private var push
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
                footer: canChangeRetention ? nil : host.deletedRetentionDays.map { LocalizedStringKey("Deleted items are kept for \($0) days.") }) {
                if canChangeRetention {
                    InstanceChoiceRow(
                        model: settings, setting: .trashRetentionDays, among: [.trashRetentionDays],
                        line: "Items wait here first, so they can come back.")
                }
                SettingsRow(
                    "Empty Recently Deleted",
                    line: host.deletedCount == 0 ? "Nothing is waiting here." : "Permanently deletes \(host.deletedCount.formatted()) items."
                ) {
                    SettingsButton("Empty…", role: .destructive) { host.emptyDeleted() }
                        .disabled(host.deletedCount == 0 || !host.canDeletePermanently)
                        .accessibilityIdentifier("RecentlyDeletedEmpty")
                }
            }
            if canChangeRetention { InstanceStatusLine(model: settings, settings: [.trashRetentionDays]) }
            SettingsSection(name: Text("Deleted Items"), accessory: { filter }) {
                if host.deletedCount == 0 {
                    SettingsEmptyCard(
                        symbol: "trash", title: Text("Nothing Is in Recently Deleted"),
                        line: Text("Items you delete wait here before they are permanently deleted."))
                } else {
                    SettingsSectionTable(
                        rows: Array(items.prefix(Self.pageSize)), columns: columns(withType: false), action: restore,
                        total: isFiltered ? items.count : host.deletedCount,
                        showAll: { push(Self.allDeleted) })
                }
            }
        }
        .accessibilityIdentifier("RecentlyDeletedPage")
    }

    private var allPage: some View {
        SettingsPageTable(
            rows: items, columns: columns(withType: true), count: Text("\((isFiltered ? items.count : host.deletedCount).formatted()) items"), selection: $selection,
            filter: { filter },
            foot: {
                SettingsButton("Permanently Delete…", role: .destructive, small: true) { host.deleteDeletedPermanently(selection) }
                    .disabled(selection.isEmpty || !host.canDeletePermanently)
                SettingsButton("Restore", small: true) {
                    host.restoreDeleted(selection)
                    selection = []
                }
                .disabled(selection.isEmpty)
            }
        )
        .onChange(of: host.deletedItems.map(\.id)) { selection.formIntersection(host.deletedItems.map(\.id)) }
        .accessibilityIdentifier("RecentlyDeletedAllPage")
    }

    /// When an item was deleted, as a table says a day (`DateDisplay`).
    static func when(_ date: Date?, now: Date = .now, calendar: Calendar = .current, format: DateFormat = .stored()) -> String {
        guard let date else { return "" }
        return DateDisplay.text(of: date, hasTime: false, place: .table, format: format, now: now, calendar: calendar)
    }
}
