import Marfa
import SwiftUI

/// Usage and Log. The page opens with neither permission. Item counts follow type access, storage needs `instance.read`, and Log needs `audit.read`.
enum ActivityTab: Hashable {
    case usage, log

    /// Log's permission. Usage has none of its own: its sections ask for what each read needs.
    var permission: InstancePermission? {
        switch self {
        case .usage: nil
        case .log: .auditRead
        }
    }

    /// What this tab cannot show without its permission. Usage and Log say different things.
    var permissionLine: String {
        switch self {
        case .usage: Self.itemsLine
        case .log: String(localized: "The app isn’t allowed to read the server’s audit log.")
        }
    }

    static let itemsLine = String(localized: "The app isn’t allowed to read how many items this Marfa holds.")
    static let storageLine = String(localized: "The app isn’t allowed to read how much this Marfa stores.")
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

    private var readsItems: Bool { host.readsItems }
    private var allowsStorage: Bool { host.grants.contains(.instanceRead) }
    private var allowsLog: Bool { host.grants.contains(.auditRead) }

    private var usageTaskKey: String {
        "\(tab == .usage)-\(readsItems)-\(allowsStorage)-\(usage.period.rawValue)-\(usage.grouping.rawValue)"
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
            guard tab == .usage else { return }
            await usage.reload(items: readsItems, storage: allowsStorage)
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

    /// The same place on both tabs: the leading edge of the page's column, so switching does not move them. Log's filter sits beside the tabs.
    private var tabStrip: some View {
        HStack(spacing: 0) {
            HStack(spacing: SettingsTokens.Metric.searchSpacing) {
                tabs
                if tab == .log, allowsLog {
                    Spacer(minLength: SettingsTokens.Metric.searchSpacing)
                    logFilter
                }
            }
            .frame(maxWidth: SettingsTokens.Metric.column, alignment: .leading)
        }
        .padding(.horizontal, SettingsTokens.Metric.pageSide)
        .padding(.top, SettingsTokens.Metric.pageTop)
        .frame(maxWidth: .infinity)
    }

    private var logFilter: some View {
        SettingsTableFilter(choice: $model.kind, search: $model.search) {
            Text("All Activity").tag(ActivityKind?.none)
            Divider()
            ForEach(ActivityKind.allCases, id: \.self) { kind in Text(verbatim: kind.title).tag(ActivityKind?.some(kind)) }
        }
    }

    @ViewBuilder private var usageBody: some View {
        if !usage.hasLoaded {
            OwnerLoading()
        } else if usage.failedEntirely, let failure = usage.statsFailure ?? usage.metricsFailure {
            failureState(failure, tab: .usage) { Task { await usage.reload() } }
        } else {
            SettingsPageColumn {
                stored
                if !usage.askedItems {
                    itemsGate
                } else if usage.hasStats || usage.hasAnyItems {
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
        } else if model.entries.isEmpty {
            logEmpty
        } else {
            SettingsPageColumn {
                VStack(alignment: .trailing, spacing: SettingsTokens.Metric.barGap) {
                    SettingsSectionTable(rows: model.listed, columns: columns)
                    logPager
                }
            }
        }
    }

    private var stored: some View {
        SettingsSection("Stored") {
            SettingsCard {
                HStack(alignment: .firstTextBaseline, spacing: SettingsTokens.Metric.tableColumnGap) {
                    if usage.askedItems {
                        figure(usage.storedItems.map { $0.formatted() }, "Items")
                    }
                    if usage.askedStorage {
                        figure(usage.versionCount.map { $0.formatted() }, "Versions")
                        figure(usage.fileBytes.map { Int64($0).formatted(.byteCount(style: .file)) }, "Files")
                        figure(usage.databaseBytes.map { Int64($0).formatted(.byteCount(style: .file)) }, "Database")
                    }
                }
                .padding(SettingsTokens.Metric.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !usage.askedStorage { storageLock }
                if let failure = usage.metricsFailure {
                    OwnerProblemRow(
                        title: "Stored", failure: failure,
                        line: String(localized: "Couldn’t read the version count or storage sizes."),
                        page: .activity, host: host
                    ) { Task { await usage.reload() } }
                    .padding(.horizontal, SettingsTokens.Metric.inset)
                    .padding(.bottom, SettingsTokens.Metric.inset)
                }
            }
        }
    }

    /// Storage was not read, because this sign-in lacks `instance.read`. Item counts do not ask for that.
    private var storageLock: some View {
        OwnerProblemRow(
            title: "Storage", failure: .notPermitted(InstancePermission.instanceRead.rawValue), line: ActivityTab.storageLine,
            page: .activity, host: host, retry: nil)
        .padding(.horizontal, SettingsTokens.Metric.inset)
        .padding(.bottom, SettingsTokens.Metric.inset)
    }

    private func figure(_ value: String?, _ caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.rowTextPadding) {
            Text(verbatim: value ?? "—").settingsFont(.usageFigure).monospacedDigit()
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
            if usage.hasDaily {
                SettingsCard {
                    SettingsUsageChart(
                        days: usage.days, now: usage.chartNow, calendar: usage.chartCalendar,
                        series: chartSeries.map { SettingsUsageChart.Series(name: $0.name, tone: $0.tone, values: $0.values) })
                }
            } else if let failure = usage.statsFailure {
                OwnerProblemRow(title: "Couldn’t read items changed", failure: failure, page: .activity, host: host) {
                    Task { await usage.reload() }
                }
            }
        }
    }

    private var chartSeries: [(name: String, tone: SettingsTokens.Tone, values: [Int])] {
        let tones: [SettingsTokens.Tone] = [.amber, .teal, .green, .blue]
        var series = usage.chart.series.enumerated().map { index, item in
            (name: name(item.key, grouping: usage.shownGrouping), tone: tones[index % tones.count], values: item.values)
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
    /// A refusal here is about reading items, so it never asks for `instance.read`.
    private func statsFailed(_ failure: OwnerFailure) -> some View {
        SettingsSection("Items Changed") {
            if case .notPermitted(let scope) = failure {
                let naming = scope == InstancePermission.instanceRead.rawValue ? nil : scope
                SettingsPageState(
                    symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: ActivityTab.itemsLine),
                    action: (host.isAllowingMore ? "Waiting…" : "Allow More", { host.askForMore(naming: naming) }))
                .disabled(host.isAllowingMore)
            } else {
                OwnerFailureState(page: .activity, failure: failure, host: host) { Task { await usage.reload() } }
            }
        }
    }

    /// This sign-in cannot read any item type. Allow More asks again for what the app asks at sign-in, not for `instance.read`.
    private var itemsGate: some View {
        SettingsPageState(
            symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: ActivityTab.itemsLine),
            action: (host.isAllowingMore ? "Waiting…" : "Allow More", { host.askForMore(naming: nil) }))
        .disabled(host.isAllowingMore)
        .accessibilityIdentifier("ActivityUsageGate")
    }

    private func columns(_ grouping: UsageGrouping) -> [SettingsTableColumn<UsageRow>] {
        [
            SettingsTableColumn(grouping == .type ? "Type" : "Source") { row in
                HStack(spacing: SettingsTokens.Metric.dotGap) {
                    lead(row.key, grouping: grouping)
                    Text(verbatim: name(row.key, grouping: grouping))
                }
            },
            SettingsTableColumn("Items", width: SettingsTokens.Metric.Column.number, numeric: true) { row in
                Text(verbatim: row.items.map { $0.formatted() } ?? "—").monospacedDigit().foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("Changed", width: SettingsTokens.Metric.Column.number, numeric: true) { row in
                Text(verbatim: row.changed.map { $0.formatted() } ?? "—").monospacedDigit().foregroundStyle(SettingsTokens.secondaryText)
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

    /// This table's own widths. The shared column tokens are other tables' widths.
    private enum LogColumn {
        static let when: CGFloat = 100
        static let who: CGFloat = 170
        static let address: CGFloat = 120
    }

    private var columns: [SettingsTableColumn<ActivityEntry>] {
        [
            SettingsTableColumn(
                "When", width: LogColumn.when,
                sortedAscending: model.order.ascending(for: .when), onSort: { model.toggleSort(.when) }
            ) { entry in
                Text(verbatim: ActivityWording.when(entry.date))
            },
            SettingsTableColumn(
                "Who", width: LogColumn.who,
                sortedAscending: model.order.ascending(for: .who), onSort: { model.toggleSort(.who) }
            ) { entry in
                Text(verbatim: entry.who ?? String(localized: "Unknown")).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn(
                "What", sortedAscending: model.order.ascending(for: .what), onSort: { model.toggleSort(.what) }
            ) { entry in
                Text(verbatim: ActivityWording.what(entry.action)).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn(
                "Address", width: LogColumn.address,
                sortedAscending: model.order.ascending(for: .address), onSort: { model.toggleSort(.address) }
            ) { entry in
                Text(verbatim: entry.address ?? "").foregroundStyle(SettingsTokens.secondaryText)
            },
        ]
    }

    @ViewBuilder private var logEmpty: some View {
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
    }

    /// Below the card, on its trailing edge. Not a footer of the window.
    private var logPager: some View {
        VStack(alignment: .trailing, spacing: SettingsTokens.Metric.searchSpacing) {
            if let failure = model.failure {
                let guidance = OwnerWording.problemLine(failure, on: .activity, canRetry: true)
                Text("Couldn’t load that page of activity. \(guidance)")
                    .settingsFont(.line).foregroundStyle(SettingsTokens.errorRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let range = model.range {
                    Text(verbatim: range).settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText)
                }
                if model.isLoading { ProgressView().controlSize(.small) }
                if model.isPaged {
                    SettingsButton("Newer", small: true) { Task { await model.newer() } }
                        .disabled(model.pageIndex == 0 || model.isLoading)
                        .accessibilityIdentifier("ActivityNewer")
                    SettingsButton("Older", small: true) { Task { await model.older() } }
                        .disabled(!model.hasNext || model.isLoading)
                        .accessibilityIdentifier("ActivityOlder")
                }
            }
        }
    }

    /// The tab's own words. A page line would not match, because the page itself needs no permission.
    private func gate(_ tab: ActivityTab) -> some View {
        SettingsPageState(
            symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: tab.permissionLine),
            action: (host.isAllowingMore ? "Waiting…" : "Allow More", { host.askForMore(naming: tab.permission?.rawValue) }))
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
