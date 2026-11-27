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
    /// Nil when that read failed or was not asked for. A key the successful read did not name is zero.
    var items: Int?
    var changed: Int?
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

    /// Every key either map names. A missing key in a read that arrived is zero. A read that failed is nil on every row.
    static func rows(items: [String: Int]?, changed: [String: Int]?) -> [UsageRow] {
        var keys = Set<String>()
        if let items { keys.formUnion(items.keys) }
        if let changed { keys.formUnion(changed.keys) }
        return keys.map { key in
            UsageRow(key: key, items: count(items, key), changed: count(changed, key))
        }.sorted { lhs, rhs in
            let left = lhs.items ?? -1
            let right = rhs.items ?? -1
            if left != right { return left > right }
            return lhs.key < rhs.key
        }
    }

    /// Nil when the read failed. Zero when the read arrived and did not name the key.
    private static func count(_ counts: [String: Int]?, _ key: String) -> Int? {
        guard let counts else { return nil }
        return counts[key] ?? 0
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

/// Which sign-in scopes can read an item, which is what item counts need. Profile, edge and metadata scopes are not item types.
nonisolated enum ActivityAccess {
    static func readsItems(_ scopes: some Sequence<String>) -> Bool {
        scopes.contains { scope in
            guard scope.hasSuffix(":read") else { return false }
            let type = String(scope.dropLast(":read".count))
            if type.isEmpty { return false }
            if type == "profile" || type.hasPrefix("profile.") { return false }
            if type == "edge" || type.hasPrefix("edge.") { return false }
            if type == "metadata" || type.hasPrefix("metadata.") { return false }
            return true
        }
    }
}

/// Usage: how many items this Marfa holds, and how many changed in the period. Period, grouping and the figures that
/// arrived are published together, so a late answer never puts one period's counts under another.
@Observable @MainActor final class ActivityUsageModel {
    private let context: OwnerContext
    private let calls: any InstanceCalls
    /// Read on every reload, so a window that stays open moves past midnight.
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    var period: UsagePeriod = .last7Days
    var grouping: UsageGrouping = .type

    private var snapshot: Snapshot?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private var generation = 0
    /// What the last reload asked for, so Try Again asks for the same parts. A plain `reload()` still reads both until a
    /// caller says otherwise.
    private var loadItems = true
    private var loadStorage = true

    init(
        context: OwnerContext, calls: any InstanceCalls, now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.context = context
        self.calls = calls
        self.now = now
        self.calendar = calendar
    }

    /// The period whose figures are on screen. Nil until the first read publishes.
    var shownPeriod: UsagePeriod? { snapshot?.period }
    /// The grouping those figures were read with. Changing the popup does not reinterpret what is already shown.
    var shownGrouping: UsageGrouping { snapshot?.grouping ?? grouping }
    var chartNow: Date { snapshot?.now ?? now() }
    var chartCalendar: Calendar { calendar }
    var hasStats: Bool { snapshot?.hasStats ?? false }
    var hasMetrics: Bool { snapshot?.hasMetrics ?? false }
    var hasDaily: Bool { snapshot?.daily != nil }
    /// An all-time count or a day arrived, even where another item read failed.
    var hasAnyItems: Bool { snapshot?.typeItems != nil || snapshot?.sourceItems != nil || snapshot?.daily != nil }
    var statsFailure: OwnerFailure? { snapshot?.statsFailure }
    var metricsFailure: OwnerFailure? { snapshot?.metricsFailure }
    var askedItems: Bool { snapshot?.askedItems ?? false }
    var askedStorage: Bool { snapshot?.askedStorage ?? false }
    var days: [Date] { snapshot?.days ?? [] }
    var versionCount: Int? { snapshot?.versionCount }
    var fileBytes: Int? { snapshot?.fileBytes }
    var databaseBytes: Int? { snapshot?.databaseBytes }

    /// The sum of items by type. Nil until that read has succeeded, so a failure is not shown as a new Marfa.
    var storedItems: Int? { snapshot?.typeItems?.values.reduce(0, +) }
    var typeRows: [UsageRow] { UsageMath.rows(items: snapshot?.typeItems, changed: snapshot?.typeChanged) }
    var sourceRows: [UsageRow] { UsageMath.rows(items: snapshot?.sourceItems, changed: snapshot?.sourceChanged) }
    var chart: UsageChartBuild { UsageMath.chart(daily: snapshot?.daily ?? []) }

    /// Both reads were asked for and neither arrived. A section that was not asked for stays on the page as its own lock.
    var failedEntirely: Bool {
        guard let snapshot, hasLoaded, snapshot.askedItems, snapshot.askedStorage else { return false }
        let itemsGone = snapshot.typeItems == nil && snapshot.sourceItems == nil && snapshot.daily == nil
        let failed = snapshot.statsFailure != nil || snapshot.metricsFailure != nil
        return itemsGone && !snapshot.hasMetrics && failed
    }

    func reload() async { await reload(items: loadItems, storage: loadStorage) }

    /// Reads the parts this sign-in may see. An older read that finishes later is dropped, including one that waited on grants.
    func reload(items: Bool, storage: Bool) async {
        loadItems = items
        loadStorage = storage
        generation += 1
        let mine = generation
        let period = self.period
        let grouping = self.grouping
        let now = now()
        let windows = UsageMath.windows(count: period.dayCount, now: now, calendar: calendar)
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        let loaded = await Self.load(calls: calls, grouping: grouping, windows: windows, items: items, storage: storage)
        guard mine == generation, !Task.isCancelled else { return }
        if let refusal = Self.refusal(in: loaded) {
            await context.learn(from: refusal)
            guard mine == generation, !Task.isCancelled else { return }
        }
        snapshot = Self.snapshot(
            period: period, grouping: grouping, now: now, windows: windows, loaded: loaded, items: items, storage: storage)
        hasLoaded = true
    }

    private struct Snapshot: Sendable {
        var period: UsagePeriod
        var grouping: UsageGrouping
        var now: Date
        var days: [Date]
        var typeItems: [String: Int]? = nil
        var sourceItems: [String: Int]? = nil
        var typeChanged: [String: Int]? = nil
        var sourceChanged: [String: Int]? = nil
        var daily: [[String: Int]]? = nil
        var hasStats = false
        var hasMetrics = false
        var statsFailure: OwnerFailure? = nil
        var metricsFailure: OwnerFailure? = nil
        var versionCount: Int? = nil
        var fileBytes: Int? = nil
        var databaseBytes: Int? = nil
        var askedItems: Bool
        var askedStorage: Bool
    }

    private struct Loaded: Sendable {
        var metrics: Result<UsageMetrics, OwnerFailure>?
        var items: ItemPieces?
    }

    private struct ItemPieces: Sendable {
        var typeItems: Result<[String: Int], OwnerFailure>
        var sourceItems: Result<[String: Int], OwnerFailure>
        var otherChanged: Result<[String: Int], OwnerFailure>
        var daily: Result<[[String: Int]], OwnerFailure>
    }

    private nonisolated static func snapshot(
        period: UsagePeriod, grouping: UsageGrouping, now: Date, windows: [UsageWindow], loaded: Loaded, items: Bool, storage: Bool
    ) -> Snapshot {
        var shot = Snapshot(period: period, grouping: grouping, now: now, days: windows.map(\.start), askedItems: items, askedStorage: storage)
        if let metrics = loaded.metrics {
            switch metrics {
            case .success(let value):
                shot.versionCount = value.versionCount
                shot.fileBytes = value.fileBytes
                shot.databaseBytes = value.databaseBytes
                shot.hasMetrics = true
            case .failure(let error):
                shot.metricsFailure = error
            }
        }
        if let pieces = loaded.items {
            switch pieces.typeItems {
            case .success(let counts): shot.typeItems = counts
            case .failure(let error): shot.statsFailure = error
            }
            switch pieces.sourceItems {
            case .success(let counts): shot.sourceItems = counts
            case .failure(let error): shot.statsFailure = shot.statsFailure ?? error
            }
            let other: [String: Int]?
            switch pieces.otherChanged {
            case .success(let counts): other = counts
            case .failure(let error):
                other = nil
                shot.statsFailure = shot.statsFailure ?? error
            }
            let selected: [String: Int]?
            switch pieces.daily {
            case .success(let days):
                shot.daily = days
                selected = UsageMath.totals(days)
            case .failure(let error):
                selected = nil
                shot.statsFailure = shot.statsFailure ?? error
            }
            if grouping == .type {
                shot.typeChanged = selected
                shot.sourceChanged = other
            } else {
                shot.sourceChanged = selected
                shot.typeChanged = other
            }
            shot.hasStats = shot.statsFailure == nil
        }
        return shot
    }

    private nonisolated static func refusal(in loaded: Loaded) -> OwnerFailure? {
        var found: [OwnerFailure] = []
        if let metrics = loaded.metrics, case .failure(let error) = metrics { found.append(error) }
        if let items = loaded.items {
            let totals: [Result<[String: Int], OwnerFailure>] = [items.typeItems, items.sourceItems, items.otherChanged]
            for result in totals {
                if case .failure(let error) = result { found.append(error) }
            }
            if case .failure(let error) = items.daily { found.append(error) }
        }
        return found.first { failure in
            if case .notPermitted = failure { return true }
            return false
        }
    }

    private enum LoadPart: Sendable {
        case metrics(Result<UsageMetrics, OwnerFailure>)
        case items(ItemPieces)
    }

    private nonisolated static func load(
        calls: any InstanceCalls, grouping: UsageGrouping, windows: [UsageWindow], items: Bool, storage: Bool
    ) async -> Loaded {
        await withTaskGroup(of: LoadPart.self) { group in
            if storage { group.addTask { .metrics(await metrics(calls)) } }
            if items { group.addTask { .items(await stats(calls, grouping: grouping, windows: windows)) } }
            var loaded = Loaded()
            for await part in group {
                switch part {
                case .metrics(let value): loaded.metrics = value
                case .items(let value): loaded.items = value
                }
            }
            return loaded
        }
    }

    private nonisolated static func metrics(_ calls: any InstanceCalls) async -> Result<UsageMetrics, OwnerFailure> {
        do throws(OwnerFailure) { return .success(try await calls.usageMetrics()) } catch { return .failure(error) }
    }

    private enum Piece: Sendable {
        case typeItems, sourceItems, otherChanged, day(Int)
    }

    private struct Outcome: Sendable {
        var piece: Piece
        var counts: Result<[String: Int], OwnerFailure>
    }

    /// Each read stands on its own. A failed day does not discard the totals, and a failed total does not discard the days.
    private nonisolated static func stats(
        _ calls: any InstanceCalls, grouping: UsageGrouping, windows: [UsageWindow]
    ) async -> ItemPieces {
        let other: UsageGrouping = grouping == .type ? .source : .type
        let period = UsageStatsQuery(grouping: other, updatedAfter: windows.first?.start, updatedBefore: windows.last?.end)
        return await withTaskGroup(of: Outcome.self) { group in
            group.addTask { await outcome(.typeItems, read(calls, UsageStatsQuery(grouping: .type))) }
            group.addTask { await outcome(.sourceItems, read(calls, UsageStatsQuery(grouping: .source))) }
            group.addTask { await outcome(.otherChanged, read(calls, period)) }
            for (index, window) in windows.enumerated() {
                group.addTask {
                    await outcome(.day(index), read(calls, UsageStatsQuery(
                        grouping: grouping, updatedAfter: window.start, updatedBefore: window.end)))
                }
            }
            var typeItems: Result<[String: Int], OwnerFailure>?
            var sourceItems: Result<[String: Int], OwnerFailure>?
            var otherChanged: Result<[String: Int], OwnerFailure>?
            var days = Array(repeating: Result<[String: Int], OwnerFailure>?.none, count: windows.count)
            for await outcome in group {
                switch outcome.piece {
                case .typeItems: typeItems = outcome.counts
                case .sourceItems: sourceItems = outcome.counts
                case .otherChanged: otherChanged = outcome.counts
                case .day(let index): days[index] = outcome.counts
                }
            }
            let daily: Result<[[String: Int]], OwnerFailure>
            if let failure = days.lazy.compactMap({ day -> OwnerFailure? in
                guard let day else { return .unreachable }
                if case .failure(let error) = day { return error }
                return nil
            }).first {
                daily = .failure(failure)
            } else {
                daily = .success(days.map { day in
                    if case .success(let counts) = day { return counts }
                    return [:]
                })
            }
            return ItemPieces(
                typeItems: typeItems ?? .failure(.unreachable),
                sourceItems: sourceItems ?? .failure(.unreachable),
                otherChanged: otherChanged ?? .failure(.unreachable),
                daily: daily)
        }
    }

    private nonisolated static func read(
        _ calls: any InstanceCalls, _ query: UsageStatsQuery
    ) -> @Sendable () async throws(OwnerFailure) -> [String: Int] {
        { try await calls.itemStats(query) }
    }

    private nonisolated static func outcome(
        _ piece: Piece, _ call: @Sendable () async throws(OwnerFailure) -> [String: Int]
    ) async -> Outcome {
        do throws(OwnerFailure) { return Outcome(piece: piece, counts: .success(try await call())) } catch { return Outcome(piece: piece, counts: .failure(error)) }
    }
}
