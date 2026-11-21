import SwiftUI

/// The Recently Deleted page: what the server holds in its bin, with Restore on every row, Delete Permanently and Empty.
/// A section shows the latest page of it, and Show All opens the whole list as a page of its own.
struct RecentlyDeletedPage: View {
    static let allDeleted = SettingsSubpage(id: "all-deleted", title: String(localized: "All Deleted Items"))
    private static let pageSize = 8

    let host: any MarfaSettingsHost
    let showsAll: Bool
    @Environment(\.settingsPush) private var push
    @State private var search = ""
    @State private var selection: Set<String> = []

    private var items: [MarfaDeletedItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? host.deletedItems : host.deletedItems.filter { $0.title.localizedStandardContains(query) }
    }

    private var columns: [SettingsTableColumn<MarfaDeletedItem>] {
        [
            SettingsTableColumn("Item") { Text(verbatim: $0.title) },
            SettingsTableColumn("Deleted", width: 90) { item in
                Text(verbatim: Self.when(item.deleted)).foregroundStyle(SettingsTokens.secondaryText)
            },
        ]
    }

    private var restore: SettingsRowAction<MarfaDeletedItem> {
        SettingsRowAction(title: "Restore") { host.restoreDeleted([$0.id]) }
    }

    var body: some View {
        if showsAll { allPage } else { overview }
    }

    private var overview: some View {
        SettingsPageColumn {
            SettingsSection(
                "Cleanup",
                footer: host.deletedRetentionDays.map { "Deleted items are kept for \($0) days." }.map { LocalizedStringKey($0) }) {
                SettingsRow(
                    "Empty Recently Deleted",
                    line: host.deletedCount == 0 ? "Nothing is waiting here." : "Permanently deletes \(host.deletedCount.formatted()) items."
                ) {
                    SettingsButton("Empty…", role: .destructive) { host.emptyDeleted() }
                        .disabled(host.deletedCount == 0 || !host.canDeletePermanently)
                        .accessibilityIdentifier("RecentlyDeletedEmpty")
                }
            }
            SettingsSection(name: Text("Deleted Items"), accessory: { SettingsTableSearch(text: $search) }) {
                if host.deletedCount == 0 {
                    SettingsEmptyCard(
                        symbol: "trash", title: Text("Nothing Is in Recently Deleted"),
                        line: Text("Items you delete wait here before they are permanently deleted."))
                } else {
                    SettingsSectionTable(
                        rows: Array(items.prefix(Self.pageSize)), columns: columns, action: restore,
                        total: search.isEmpty ? host.deletedCount : items.count,
                        showAll: { push(Self.allDeleted) })
                }
            }
        }
        .accessibilityIdentifier("RecentlyDeletedPage")
    }

    private var allPage: some View {
        SettingsPageColumn {
            SettingsPageTable(
                rows: items, columns: columns, count: Text("\(items.count.formatted()) items"), selection: $selection,
                action: restore,
                filter: { SettingsTableSearch(text: $search) },
                foot: {
                    SettingsButton("Restore", small: true) {
                        host.restoreDeleted(selection)
                        selection = []
                    }
                    .disabled(selection.isEmpty)
                    SettingsButton("Delete Permanently…", role: .destructive, small: true) { host.deleteDeletedPermanently(selection) }
                        .disabled(selection.isEmpty || !host.canDeletePermanently)
                    Spacer(minLength: 0)
                    SettingsButton("Empty…", role: .destructive, small: true) { host.emptyDeleted() }
                        .disabled(host.deletedCount == 0 || !host.canDeletePermanently)
                })
        }
        .onChange(of: host.deletedItems.map(\.id)) { selection.formIntersection(host.deletedItems.map(\.id)) }
        .accessibilityIdentifier("RecentlyDeletedAllPage")
    }

    /// When an item was deleted: Today, Yesterday, the day of this year, or the day with its year.
    static func when(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return date.formatted(.dateTime.day().month(.abbreviated)) }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
