import Foundation
import Observation

/// How far back Items Changed looks, and whether the chart groups types or sources.
nonisolated enum UsagePeriod: Int, CaseIterable, Hashable, Sendable {
    case last7Days = 7
    case last30Days = 30

    var dayCount: Int { rawValue }
}

nonisolated enum UsageGrouping: String, CaseIterable, Hashable, Sendable {
    case type, source
}

/// Without dates, the server counts every item the sign-in can read. The lower bound is inclusive and the upper bound is exclusive.
nonisolated struct UsageStatsQuery: Hashable, Sendable {
    var grouping: UsageGrouping
    var updatedAfter: Date?
    var updatedBefore: Date?
}

/// Versions, files and the database from `GET /metrics`. Item counts are not taken from here.
nonisolated struct UsageMetrics: Hashable, Sendable {
    var versionCount: Int?
    var fileBytes: Int
    var databaseBytes: Int?
}

/// One type or source in the tables: how many items it holds, and how many changed in the period.
nonisolated struct UsageRow: Identifiable, Hashable, Sendable {
    var key: String
    var items: Int
    var changed: Int
    var id: String { key }
}

/// One local day, `[start, end)`, oldest first across a period.
nonisolated struct UsageWindow: Hashable, Sendable {
    var start: Date
    var end: Date
}

/// A chart series before its colour: the key, and one count per day. `other` is the rest, folded.
nonisolated struct UsageChartBuild: Hashable, Sendable {
    var series: [(key: String, values: [Int])]
    var other: [Int]?

    static func == (lhs: UsageChartBuild, rhs: UsageChartBuild) -> Bool {
        lhs.other == rhs.other && lhs.series.elementsEqual(rhs.series, by: { $0.key == $1.key && $0.values == $1.values })
    }

    func hash(into hasher: inout Hasher) {
        for item in series {
            hasher.combine(item.key)
            hasher.combine(item.values)
        }
        hasher.combine(other)
    }
}

/// The words of a type id or a source code when the catalogue has no plural and the server has no name.
nonisolated enum UsageNaming {
    /// A known plural, otherwise the last part of the id in words. A name with no separator is kept, only its first letter raised.
    static func typeName(_ key: String, plural: String?) -> String {
        if let plural, !plural.isEmpty { return plural }
        return humanized(key)
    }

    static func sourceName(_ code: String, named: String?) -> String {
        if let named, !named.isEmpty { return named }
        return humanized(code)
    }

    static func humanized(_ key: String) -> String {
        let last = key.split(separator: ".").last.map(String.init) ?? key
        let words = last.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return words.split(separator: " ", omittingEmptySubsequences: true).map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}

/// Turns the server's counts into the chart and the two tables. The chart keeps the four busiest and folds the rest into Other.
nonisolated enum UsageMath {
    static let chartLimit = 4

    static func windows(count: Int, now: Date, calendar: Calendar) -> [UsageWindow] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { ago in
            guard let start = calendar.date(byAdding: .day, value: -ago, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return UsageWindow(start: start, end: end)
        }
    }

    static func totals(_ daily: [[String: Int]]) -> [String: Int] {
        var sums: [String: Int] = [:]
        for day in daily {
            for (key, count) in day { sums[key, default: 0] += count }
        }
        return sums
    }

    /// Every key either map names, including a zero, most items first.
    static func rows(items: [String: Int], changed: [String: Int]) -> [UsageRow] {
        Set(items.keys).union(changed.keys).map { key in
            UsageRow(key: key, items: items[key] ?? 0, changed: changed[key] ?? 0)
        }.sorted { lhs, rhs in
            if lhs.items != rhs.items { return lhs.items > rhs.items }
            return lhs.key < rhs.key
        }
    }

    /// The busiest series first, which the chart draws at the bottom. More than four folds the rest into Other. A zero is not a series.
    static func chart(daily: [[String: Int]], limit: Int = chartLimit) -> UsageChartBuild {
        let ranked = totals(daily).filter { $0.value > 0 }.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.map(\.key)
        let shown: [String]
        let folded: [String]
        if ranked.count > limit {
            shown = Array(ranked.prefix(limit))
            folded = Array(ranked.dropFirst(limit))
        } else {
            shown = ranked
            folded = []
        }
        let series = shown.map { key in (key: key, values: daily.map { $0[key] ?? 0 }) }
        let other: [Int]? = folded.isEmpty ? nil : daily.indices.map { day in folded.reduce(0) { $0 + (daily[day][$1] ?? 0) } }
        return UsageChartBuild(series: series, other: other)
    }
}

/// Usage: how many items this Marfa holds, and how many changed in the period. A late answer never replaces a newer one.
@Observable @MainActor final class ActivityUsageModel {
    private let context: OwnerContext
    private let calls: any InstanceCalls
    private let now: Date
    private let calendar: Calendar

    var period: UsagePeriod = .last7Days
    var grouping: UsageGrouping = .type

    private(set) var hasStats = false
    private(set) var hasMetrics = false
    private(set) var statsFailure: OwnerFailure?
    private(set) var metricsFailure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var days: [Date] = []
    private(set) var versionCount: Int?
    private(set) var fileBytes: Int?
    private(set) var databaseBytes: Int?
    private var typeItems: [String: Int] = [:]
    private var sourceItems: [String: Int] = [:]
    private var otherChanged: [String: Int] = [:]
    private var daily: [[String: Int]] = []
    private var generation = 0

    init(context: OwnerContext, calls: any InstanceCalls, now: Date = .now, calendar: Calendar = .current) {
        self.context = context
        self.calls = calls
        self.now = now
        self.calendar = calendar
    }

    /// The sum of items by type. Nil until a stats read has succeeded, so a failure is not shown as a new Marfa.
    var storedItems: Int? { hasStats ? typeItems.values.reduce(0, +) : nil }

    var typeRows: [UsageRow] { UsageMath.rows(items: typeItems, changed: typeChanged) }
    var sourceRows: [UsageRow] { UsageMath.rows(items: sourceItems, changed: sourceChanged) }

    var chart: UsageChartBuild { UsageMath.chart(daily: daily) }

    /// What changed in the period, by the selected grouping, is the sum of the days. The other grouping is one read of the period.
    private var typeChanged: [String: Int] { grouping == .type ? UsageMath.totals(daily) : otherChanged }
    private var sourceChanged: [String: Int] { grouping == .source ? UsageMath.totals(daily) : otherChanged }

    /// Reads metrics and the stats for the period and grouping as they are now. An older read that finishes later is dropped.
    func reload() async {
        generation += 1
        let mine = generation
        let period = period
        let grouping = grouping
        let windows = UsageMath.windows(count: period.dayCount, now: now, calendar: calendar)
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        let loaded = await Self.load(calls: calls, grouping: grouping, windows: windows)
        guard mine == generation, !Task.isCancelled else { return }
        days = windows.map(\.start)
        switch loaded.metrics {
        case .success(let metrics):
            versionCount = metrics.versionCount
            fileBytes = metrics.fileBytes
            databaseBytes = metrics.databaseBytes
            hasMetrics = true
            metricsFailure = nil
        case .failure(let failure):
            versionCount = nil
            fileBytes = nil
            databaseBytes = nil
            hasMetrics = false
            metricsFailure = failure
            await context.learn(from: failure)
        }
        switch loaded.stats {
        case .success(let stats):
            typeItems = stats.typeItems
            sourceItems = stats.sourceItems
            otherChanged = stats.otherChanged
            daily = stats.daily
            hasStats = true
            statsFailure = nil
        case .failure(let failure):
            // The period on screen is this read's. Keeping the previous period's counts would put them under the new one.
            typeItems = [:]
            sourceItems = [:]
            otherChanged = [:]
            daily = []
            hasStats = false
            statsFailure = failure
            await context.learn(from: failure)
        }
        hasLoaded = true
    }

    private struct Loaded: Sendable {
        var metrics: Result<UsageMetrics, OwnerFailure>
        var stats: Result<Stats, OwnerFailure>
    }

    private struct Stats: Sendable {
        var typeItems: [String: Int]
        var sourceItems: [String: Int]
        var otherChanged: [String: Int]
        var daily: [[String: Int]]
    }

    /// Metrics and every stats read together. One stats failure drops the set, so a chart is never half a period.
    private nonisolated static func load(calls: any InstanceCalls, grouping: UsageGrouping, windows: [UsageWindow]) async -> Loaded {
        async let metricsRead = metrics(calls)
        async let statsRead = stats(calls, grouping: grouping, windows: windows)
        return await Loaded(metrics: metricsRead, stats: statsRead)
    }

    private nonisolated static func metrics(_ calls: any InstanceCalls) async -> Result<UsageMetrics, OwnerFailure> {
        do throws(OwnerFailure) { return .success(try await calls.usageMetrics()) } catch { return .failure(error) }
    }

    private enum Piece: Sendable {
        case typeItems, sourceItems, otherChanged, day(Int)
    }

    private nonisolated static func stats(
        _ calls: any InstanceCalls, grouping: UsageGrouping, windows: [UsageWindow]
    ) async -> Result<Stats, OwnerFailure> {
        let other: UsageGrouping = grouping == .type ? .source : .type
        let period = UsageStatsQuery(grouping: other, updatedAfter: windows.first?.start, updatedBefore: windows.last?.end)
        return await withTaskGroup(of: Result<(Piece, [String: Int]), OwnerFailure>.self) { group in
            group.addTask { await piece(.typeItems, read(calls, UsageStatsQuery(grouping: .type))) }
            group.addTask { await piece(.sourceItems, read(calls, UsageStatsQuery(grouping: .source))) }
            group.addTask { await piece(.otherChanged, read(calls, period)) }
            for (index, window) in windows.enumerated() {
                group.addTask {
                    await piece(.day(index), read(calls, UsageStatsQuery(
                        grouping: grouping, updatedAfter: window.start, updatedBefore: window.end)))
                }
            }
            var typeItems: [String: Int]?
            var sourceItems: [String: Int]?
            var otherChanged: [String: Int]?
            var daily = Array(repeating: [String: Int](), count: windows.count)
            var days = 0
            var failure: OwnerFailure?
            for await result in group {
                switch result {
                case .failure(let error):
                    if failure == nil { failure = error }
                    group.cancelAll()
                case .success(let (piece, counts)):
                    switch piece {
                    case .typeItems: typeItems = counts
                    case .sourceItems: sourceItems = counts
                    case .otherChanged: otherChanged = counts
                    case .day(let index):
                        daily[index] = counts
                        days += 1
                    }
                }
            }
            if let failure { return .failure(failure) }
            guard let typeItems, let sourceItems, let otherChanged, days == windows.count else { return .failure(.unreachable) }
            return .success(Stats(typeItems: typeItems, sourceItems: sourceItems, otherChanged: otherChanged, daily: daily))
        }
    }

    private nonisolated static func read(
        _ calls: any InstanceCalls, _ query: UsageStatsQuery
    ) -> @Sendable () async throws(OwnerFailure) -> [String: Int] {
        { try await calls.itemStats(query) }
    }

    private nonisolated static func piece(
        _ piece: Piece, _ call: @Sendable () async throws(OwnerFailure) -> [String: Int]
    ) async -> Result<(Piece, [String: Int]), OwnerFailure> {
        do throws(OwnerFailure) { return .success((piece, try await call())) } catch { return .failure(error) }
    }
}
