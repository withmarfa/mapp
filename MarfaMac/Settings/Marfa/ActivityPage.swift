import Marfa
import SwiftUI

/// Usage and Log. The page opens with neither permission: each tab asks for its own, and the other stays reachable.
enum ActivityTab: Hashable {
    case usage, log

    var permission: InstancePermission {
        switch self {
        case .usage: .instanceRead
        case .log: .auditRead
        }
    }

    /// What this tab cannot show without its permission. The two lines differ, and Usage differs from Overview's.
    var permissionLine: String {
        switch self {
        case .usage: String(localized: "The app isn’t allowed to read how many items this Marfa holds.")
        case .log: String(localized: "The app isn’t allowed to read the server’s audit log.")
        }
    }
}

/// Activity: how many items changed, and the audit log. Usage is the tab the page opens on.
struct ActivityPage: View {
    let host: any MarfaSettingsHost
    @State private var tab: ActivityTab
    @State private var usage: ActivityUsageModel
    @State private var model: ActivityModel

    init(host: any MarfaSettingsHost, tab: ActivityTab = .usage) {
        self.host = host
        _tab = State(initialValue: tab)
        _usage = State(initialValue: ActivityUsageModel(context: OwnerContext(host: host), calls: host.instanceCalls))
        _model = State(initialValue: ActivityModel(context: OwnerContext(host: host), calls: host.instanceCalls))
    }

    /// A page over models that already hold their state, for a render to draw.
    init(host: any MarfaSettingsHost, tab: ActivityTab = .usage, usage: ActivityUsageModel, model: ActivityModel) {
        self.host = host
        _tab = State(initialValue: tab)
        _usage = State(initialValue: usage)
        _model = State(initialValue: model)
    }

    private var allowsUsage: Bool { host.grants.contains(.instanceRead) }
    private var allowsLog: Bool { host.grants.contains(.auditRead) }

    private var usageTaskKey: String {
        "\(tab == .usage)-\(allowsUsage)-\(usage.period.rawValue)-\(usage.grouping.rawValue)"
    }

    private var logTaskKey: String { "\(tab == .log)-\(allowsLog)-\(model.filterKey)" }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            switch tab {
            case .usage: usageBody
            case .log: logBody
            }
        }
        .task(id: usageTaskKey) {
            guard tab == .usage, allowsUsage else { return }
            await usage.reload()
        }
        .task(id: logTaskKey) {
            guard tab == .log, allowsLog else { return }
            if model.hasLoaded { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await model.reload()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsTokens.page)
        .accessibilityIdentifier("ActivityPage")
    }

    private var tabs: some View {
        SettingsTabs(
            tabs: [
                .init(value: ActivityTab.usage, title: "Usage"),
                .init(value: ActivityTab.log, title: "Log"),
            ],
            selection: $tab)
    }

    /// The same place on both tabs: the leading edge of the page's column, so switching does not move them.
    private var tabStrip: some View {
        HStack(spacing: 0) {
            tabs.padding(.horizontal, SettingsTokens.Metric.inset)
                .frame(maxWidth: SettingsTokens.Metric.column, alignment: .leading)
        }
        .padding(.horizontal, SettingsTokens.Metric.pageSide)
        .padding(.top, SettingsTokens.Metric.pageTop)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var usageBody: some View {
        if !allowsUsage {
            gate(.usage)
        } else if !usage.hasLoaded {
            OwnerLoading()
        } else if !usage.hasStats, !usage.hasMetrics, let failure = usage.statsFailure ?? usage.metricsFailure {
            failureState(failure, tab: .usage) { Task { await usage.reload() } }
        } else {
            SettingsPageColumn {
                stored
                if usage.hasStats {
                    changed
                    table("Items by Type", rows: usage.typeRows, grouping: .type)
                    table("Items by Source", rows: usage.sourceRows, grouping: .source)
                } else if let failure = usage.statsFailure {
                    statsFailed(failure)
                }
            }
        }
    }

    @ViewBuilder private var logBody: some View {
        if !allowsLog {
            gate(.log)
        } else if !model.hasLoaded, model.entries.isEmpty, model.failure == nil {
            OwnerLoading()
        } else {
            logTable
        }
    }

    private var stored: some View {
        SettingsSection("Stored", footer: usage.metricsFailure == nil ? nil : "Couldn’t read the version count or storage sizes.") {
            SettingsCard {
                HStack(alignment: .firstTextBaseline, spacing: SettingsTokens.Metric.tableColumnGap) {
                    figure(usage.storedItems.map { $0.formatted() }, "Items")
                    figure(usage.versionCount.map { $0.formatted() }, "Versions")
                    figure(usage.fileBytes.map { Int64($0).formatted(.byteCount(style: .file)) }, "Files")
                    figure(usage.databaseBytes.map { Int64($0).formatted(.byteCount(style: .file)) }, "Database")
                }
                .padding(SettingsTokens.Metric.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func figure(_ value: String?, _ caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.rowTextPadding) {
            Text(verbatim: value ?? "—").settingsFont(.pageHeader).monospacedDigit()
            Text(caption).settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var changed: some View {
        SettingsSection(
            name: Text("Items Changed"),
            footer: Text("An item counts once, on the day it last changed.")
        ) {
            HStack(spacing: SettingsTokens.Metric.searchSpacing) {
                SettingsHeaderPopUp("Period", selection: $usage.period) {
                    Text("Last 7 Days").tag(UsagePeriod.last7Days)
                    Text("Last 30 Days").tag(UsagePeriod.last30Days)
                }
                SettingsHeaderPopUp("Grouping", selection: $usage.grouping) {
                    Text("By Type").tag(UsageGrouping.type)
                    Text("By Source").tag(UsageGrouping.source)
                }
            }
        } content: {
            SettingsCard {
                SettingsUsageChart(
                    days: usage.days,
                    series: chartSeries.map { SettingsUsageChart.Series(name: $0.name, tone: $0.tone, values: $0.values) })
            }
        }
    }

    private var chartSeries: [(name: String, tone: SettingsTokens.Tone, values: [Int])] {
        let tones: [SettingsTokens.Tone] = [.amber, .teal, .green, .blue]
        var series = usage.chart.series.enumerated().map { index, item in
            (name: name(item.key, grouping: usage.grouping), tone: tones[index % tones.count], values: item.values)
        }
        if let other = usage.chart.other {
            series.append((name: String(localized: "Other"), tone: .gray, values: other))
        }
        if series.isEmpty, !usage.days.isEmpty {
            series = [(name: String(localized: "Items"), tone: .gray, values: Array(repeating: 0, count: usage.days.count))]
        }
        return series
    }

    private func table(_ title: LocalizedStringKey, rows: [UsageRow], grouping: UsageGrouping) -> some View {
        SettingsSection(title) {
            if rows.isEmpty {
                SettingsCard {
                    Text("No items yet")
                        .settingsFont(.line)
                        .foregroundStyle(SettingsTokens.secondaryText)
                        .padding(SettingsTokens.Metric.inset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                SettingsSectionTable(rows: rows, columns: columns(grouping))
            }
        }
    }

    /// Metrics arrived and the item counts did not. The sizes stay; the chart is not a row of invented zeros.
    private func statsFailed(_ failure: OwnerFailure) -> some View {
        SettingsSection("Items Changed") {
            if case .notPermitted = failure {
                SettingsPageState(
                    symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: ActivityTab.usage.permissionLine),
                    action: (host.isAllowingMore ? "Waiting…" : "Allow More", { host.askForMore(naming: ActivityTab.usage.permission.rawValue) }))
                .disabled(host.isAllowingMore)
            } else {
                OwnerFailureState(page: .activity, failure: failure, host: host) { Task { await usage.reload() } }
            }
        }
    }

    private func columns(_ grouping: UsageGrouping) -> [SettingsTableColumn<UsageRow>] {
        [
            SettingsTableColumn(grouping == .type ? "Type" : "Source") { row in
                HStack(spacing: SettingsTokens.Metric.dotGap) {
                    lead(row.key, grouping: grouping)
                    Text(verbatim: name(row.key, grouping: grouping))
                }
            },
            SettingsTableColumn("Items", width: SettingsTokens.Metric.Column.day, numeric: true) { row in
                Text(verbatim: row.items.formatted()).monospacedDigit().foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("Changed", width: SettingsTokens.Metric.Column.day, numeric: true) { row in
                Text(verbatim: row.changed.formatted()).monospacedDigit().foregroundStyle(SettingsTokens.secondaryText)
            },
        ]
    }

    @ViewBuilder private func lead(_ key: String, grouping: UsageGrouping) -> some View {
        switch grouping {
        case .type:
            host.typeMark(for: key)
        case .source:
            host.markGlyph(host.sources.first { $0.code == key }?.mark ?? key)
        }
    }

    private func name(_ key: String, grouping: UsageGrouping) -> String {
        switch grouping {
        case .type: UsageNaming.typeName(key, plural: host.typePlural(of: key))
        case .source: UsageNaming.sourceName(key, named: host.sources.first { $0.code == key }?.name)
        }
    }

    private var columns: [SettingsTableColumn<ActivityEntry>] {
        [
            SettingsTableColumn("When", width: SettingsTokens.Metric.Column.day) { entry in
                Text(verbatim: ActivityWording.when(entry.date)).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("Who", width: SettingsTokens.Metric.Column.who) { entry in
                Text(verbatim: entry.who ?? String(localized: "Unknown")).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("What") { entry in
                Text(verbatim: ActivityWording.what(entry.action)).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("Address", width: SettingsTokens.Metric.Column.address) { entry in
                Text(verbatim: entry.address ?? "").foregroundStyle(SettingsTokens.secondaryText)
            },
        ]
    }

    private var logTable: some View {
        SettingsLogTable(
            rows: model.listed, columns: columns, count: Text(verbatim: model.orderLabel),
            filter: {
                SettingsTableFilter(choice: $model.kind, search: $model.search) {
                    Text("All Activity").tag(ActivityKind?.none)
                    Divider()
                    ForEach(ActivityKind.allCases, id: \.self) { kind in Text(verbatim: kind.title).tag(ActivityKind?.some(kind)) }
                }
            },
            foot: {
                if let failure = model.failure, !model.entries.isEmpty {
                    let guidance = OwnerWording.problemLine(failure, on: .activity, canRetry: true)
                    Text("Couldn’t load that page of activity. \(guidance)")
                        .settingsFont(.line).foregroundStyle(SettingsTokens.errorRed)
                } else if let range = model.range {
                    Text(verbatim: range).settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText)
                }
                Spacer(minLength: 0)
                if model.isLoading { ProgressView().controlSize(.small) }
                if model.isPaged {
                    SettingsButton("Newer", small: true) { Task { await model.newer() } }
                        .disabled(model.pageIndex == 0 || model.isLoading)
                        .accessibilityIdentifier("ActivityNewer")
                    SettingsButton("Older", small: true) { Task { await model.older() } }
                        .disabled(!model.hasNext || model.isLoading)
                        .accessibilityIdentifier("ActivityOlder")
                }
            },
            empty: {
                if let failure = model.failure {
                    failureState(failure, tab: .log) { Task { await model.reload() } }
                } else if !model.hasLoaded {
                    OwnerLoading()
                } else if model.isFiltered {
                    SettingsStateContent(symbol: "magnifyingglass", title: Text("Nothing Matches"), line: Text("No activity fits this filter."), action: nil)
                } else {
                    SettingsStateContent(
                        symbol: "list.bullet.rectangle", title: Text("No Activity Yet"),
                        line: Text("Changes and sign-ins are recorded here."), action: nil)
                }
            },
            sort: SettingsColumnSort(column: model.order.column.rawValue, ascending: model.order.ascending),
            onColumnSort: { index in
                if let column = ActivityColumn(rawValue: index) { model.toggleSort(column) }
            })
    }

    /// The tab's own words. A page line would not match, because the page itself needs no permission.
    private func gate(_ tab: ActivityTab) -> some View {
        SettingsPageState(
            symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: tab.permissionLine),
            action: (host.isAllowingMore ? "Waiting…" : "Allow More", { host.askForMore(naming: tab.permission.rawValue) }))
        .disabled(host.isAllowingMore)
        .accessibilityIdentifier(tab == .usage ? "ActivityUsageGate" : "ActivityLogGate")
    }

    @ViewBuilder private func failureState(_ failure: OwnerFailure, tab: ActivityTab, retry: @escaping () -> Void) -> some View {
        if case .notPermitted = failure {
            gate(tab)
        } else {
            OwnerFailureState(page: .activity, failure: failure, host: host, retry: retry)
        }
    }
}
