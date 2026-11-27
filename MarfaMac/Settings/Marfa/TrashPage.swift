import Marfa
import SwiftUI

struct TrashFilter {
    var search = ""
    var kind: String?

    var isActive: Bool { kind != nil || !search.isEmpty }

    func canEmptyTrash(canDeletePermanently: Bool) -> Bool { canDeletePermanently && !isActive }

    func matches(_ item: MarfaDeletedItem) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (kind == nil || item.kind == kind) && (query.isEmpty || item.title.localizedStandardContains(query))
    }
}

struct TrashPage: View {
    static let allDeleted = SettingsSubpage(id: "all-deleted", title: String(localized: "All Deleted Items"))

    let host: any MarfaSettingsHost
    let showsAll: Bool
    @State private var showsEveryItem = false
    @State private var filter = TrashFilter()

    static func canReadItems(scopes: [String]) -> Bool {
        AccessScopes.parse(scopes).entries.contains { entry in
            guard let root = entry.pattern.split(separator: ".").first else { return false }
            return !["edge", "metadata", "profile", "app"].contains(root)
        }
    }

    var purgePermission: InstancePermission? {
        host.grants.contains(.itemsPurge) ? nil : .itemsPurge
    }

    var isEmpty: Bool { host.deletedCount == 0 }

    private var retention: Text {
        if host.deletedRetentionDays == 0 {
            Text("Deleted items stay here until you delete them permanently.")
        } else if host.deletedRetentionDays == 1 {
            Text("Deleted items stay here for one day.")
        } else if let days = host.deletedRetentionDays {
            Text("Deleted items stay here for \(days.formatted()) days.")
        } else {
            Text("Deleted items wait here before they are permanently deleted.")
        }
    }

    var body: some View {
        if !host.canReadTrash {
            SettingsPageState(
                symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: MarfaSettingsPage.trash.permissionLine),
                action: (host.isAllowingMore ? "Waiting…" : "Allow More", { host.askForMore(naming: "*:read") }))
                .disabled(host.isAllowingMore)
        } else if isEmpty {
            SettingsPageState(symbol: "trash", title: Text("Trash Is Empty"), line: retention)
                .accessibilityIdentifier("TrashEmptyState")
        } else {
            SettingsPageColumn {
                if !showsAll { summary }
                deletedList
            }
            .accessibilityIdentifier(showsAll ? "TrashAllPage" : "TrashPage")
        }
    }

    private var summary: some View {
        SettingsCard {
            SettingsRow(
                title: Text("^[\(host.deletedCount) item](inflect: true)"),
                line: filter.isActive ? Text("Clear the search and type filter to empty the whole Trash.") : retention
            ) {
                if let purgePermission {
                    SettingsLockedValue(text: String(localized: "Empty Trash"))
                    SettingsButton("Allow More") { host.askForMore(naming: purgePermission.rawValue) }
                        .disabled(host.isAllowingMore)
                } else {
                    SettingsButton("Empty Trash", role: .destructive) { host.emptyDeleted() }
                        .disabled(!filter.canEmptyTrash(canDeletePermanently: host.canDeletePermanently))
                        .accessibilityIdentifier("TrashEmpty")
                }
            }
        }
    }

    private var deletedList: some View {
        let items = host.deletedItems.filter { filter.matches($0) }
        let preview = SettingsTablePreview(total: items.count, expanded: showsAll || showsEveryItem)
        let kinds = Set(host.deletedItems.map(\.kind)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return VStack(spacing: SettingsTokens.Metric.sectionGap) {
            SettingsTableFilter(choice: $filter.kind, search: $filter.search) {
                Text("All Types").tag(String?.none)
                ForEach(kinds, id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            SettingsCard {
                if items.isEmpty {
                    SettingsEmptyCard(symbol: "magnifyingglass", title: Text("No Matching Items"))
                }
                ForEach(items.prefix(preview.visibleCount)) { item in
                    itemRow(item)
                }
                if let count = preview.countLabel {
                    SettingsRow(verbatim: count, size: .compact) {
                        SettingsShowAllButton { showsEveryItem = true }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: MarfaDeletedItem) -> some View {
        SettingsRow(title: Text(verbatim: item.title), line: detail(item), lead: lead(item)) {
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                if item.canWrite {
                    SettingsButton("Restore") { host.restoreDeleted([item.id]) }
                } else {
                    SettingsLockedValue(text: String(localized: "Restore"))
                        .help("Restoring this item needs write access to its type.")
                }
                if purgePermission != nil || !item.canWrite {
                    SettingsLockedValue(text: String(localized: "Delete"))
                        .help("Deleting this item permanently needs write access to its type and permission to empty Trash.")
                } else {
                    SettingsButton("Delete", role: .destructive) { host.deleteDeletedPermanently([item.id]) }
                        .disabled(!host.canDeletePermanently)
                }
            }
        }
        .help(item.title)
    }

    private func lead(_ item: MarfaDeletedItem) -> SettingsLead {
        guard let typeID = item.typeID else { return .symbol("doc") }
        return .custom(host.typeMark(for: typeID))
    }

    private func detail(_ item: MarfaDeletedItem) -> Text {
        let day = Self.when(item.deleted)
        if let source = item.source {
            if day.isEmpty { return Text("From \(source)") }
            return Text("\(day), from \(source)")
        }
        return Text(verbatim: day)
    }

    static func when(_ date: Date?, now: Date = .now, calendar: Calendar = .current, format: DateFormat = .stored()) -> String {
        guard let date else { return "" }
        return DateDisplay.text(of: date, hasTime: false, place: .table, format: format, now: now, calendar: calendar)
    }
}
