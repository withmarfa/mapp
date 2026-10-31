import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// A queue of probes the engine loop answers in order, so how long one waits is how far behind the loop is.
nonisolated final class LoopProbe: Sendable {
    struct Sample: Sendable {
        /// When the probe was asked, from the probe's start.
        let at: Duration
        /// How long the engine took to answer, which is how far behind its loop was.
        let wait: Duration
    }

    private final class Held: Sendable {
        let samples = Mutex<[Sample]>([])
        let task = Mutex<Task<Void, Never>?>(nil)
    }

    private let held = Held()

    init(_ source: MarfaSource, every interval: Duration) {
        let origin = ContinuousClock.now
        let held = held
        let task = Task.detached {
            while !Task.isCancelled {
                let asked = ContinuousClock.now
                await source.engineTook()
                let answered = ContinuousClock.now
                held.samples.withLock { $0.append(Sample(at: asked - origin, wait: answered - asked)) }
                try? await Task.sleep(for: interval)
            }
        }
        held.task.withLock { $0 = task }
    }

    /// Stops asking, waits for the probe in flight, and gives every sample.
    func stop() async -> Samples {
        let running = held.task.withLock { $0 }
        running?.cancel()
        await running?.value
        return Samples(all: held.samples.withLock { $0 })
    }

    struct Samples: Sendable {
        let all: [Sample]
        var longest: Duration { all.map(\.wait).max() ?? .zero }
        var count: Int { all.count }
        /// The sum, over the probes that waited longer than `limit`, of the wait beyond it: how long the loop was
        /// more than `limit` behind.
        func behind(by limit: Duration) -> Duration {
            all.reduce(.zero) { $0 + max(.zero, $1.wait - limit) }
        }
    }
}

/// How much of the main actor others use while it runs. It yields in a loop, and a yield that comes back late
/// means another job held the main actor for that long.
@MainActor final class MainActorMeter {
    private(set) var busy = Duration.zero
    private(set) var longest = Duration.zero
    private var task: Task<Void, Never>?

    func start() {
        task = Task { @MainActor [self] in
            while !Task.isCancelled {
                let before = ContinuousClock.now
                await Task.yield()
                let gap = ContinuousClock.now - before
                if gap > .milliseconds(1) {
                    busy += gap
                    longest = max(longest, gap)
                }
            }
        }
    }

    func stop() async {
        task?.cancel()
        await task?.value
        task = nil
    }
}

/// The test instance over HTTP, for what a connector does to it: bulk writes and clean-ups under the key's own source.
nonisolated enum EngineServer {
    static var isGiven: Bool {
        ["MARFA_API_URL", "MARFA_API_KEY"].allSatisfy {
            !(ProcessInfo.processInfo.environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        }
    }

    struct Reply: Sendable {
        let status: Int
        let data: Data
        var object: [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        var text: String { String(decoding: data.prefix(400), as: UTF8.self) }
    }

    static func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Reply {
        let base = try #require(URL(string: try LiveMarfa.address()))
        var components = try #require(URLComponents(url: base, resolvingAgainstBaseURL: false))
        components.path += path
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: try #require(components.url), timeoutInterval: 300)
        request.httpMethod = method
        request.setValue("Bearer \(try LiveMarfa.key())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return Reply(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }

    /// Every item in every state and tier, and those active, as the server counts them.
    static func counts() async throws -> (total: Int, active: Int) {
        let reply = try await send("GET", "/items/stats", query: [URLQueryItem(name: "by", value: "state"), URLQueryItem(name: "tier", value: "all")])
        let counts = try #require(reply.object, "stats answered \(reply.status) \(reply.text)")
        let numbers = counts.compactMapValues { ($0 as? NSNumber)?.intValue }
        return (numbers.values.reduce(0, +), numbers["active"] ?? 0)
    }

    /// Makes `count` notes tagged `tag`, in as few calls as the server takes, and answers their ids.
    static func createNotes(count: Int, tag: String) async throws -> [ItemID] {
        var ids: [ItemID] = []
        while ids.count < count {
            let batch = min(5000, count - ids.count)
            var items: [[String: Any]] = []
            for index in ids.count..<(ids.count + batch) {
                let id = ItemID.mint()
                ids.append(id)
                items.append([
                    "id": id.rawValue, "type": "core.note", "tier": "library", "tags": [tag], "source_id": "\(tag)-\(index)",
                    "properties": ["title": "MAPPTEST flood \(index)"],
                ])
            }
            let reply = try await send("POST", "/items/bulk", body: try json(["items": items, "mode": "create_only"]))
            let created = ((reply.object?["counts"] as? [String: Any])?["created"] as? NSNumber)?.intValue
            try #require(reply.status == 200 && created == batch, "bulk create answered \(reply.status) \(reply.text)")
        }
        return ids
    }

    /// Runs one bulk action on the items tagged `tag`, and waits for the job. Answers how many it matched.
    @discardableResult
    static func bulkAction(_ action: [String: Any], tag: String, state: String? = nil) async throws -> Int {
        var filter: [String: Any] = ["tags": [tag]]
        if let state { filter["state"] = state }
        var body = action
        body["filter"] = filter
        body["max_items"] = 50_000
        let reply = try await send("POST", "/items/bulk-actions", body: try json(body))
        let object = try #require(reply.object, "bulk action answered \(reply.status) \(reply.text)")
        if reply.status == 200 { return (object["matched"] as? NSNumber)?.intValue ?? 0 }
        let job = try #require(object["id"] as? String, "bulk action answered \(reply.status) \(reply.text)")
        let end = ContinuousClock.now + .seconds(600)
        while ContinuousClock.now < end {
            let status = try await send("GET", "/items/bulk-actions/jobs/\(job)")
            let state = status.object?["status"] as? String
            if state == "completed" { return (status.object?["matched"] as? NSNumber)?.intValue ?? 0 }
            try #require(state != "failed" && state != "canceled", "the bulk job ended \(state ?? "?"): \(status.text)")
            // Paces the poll of the bulk job on the server.
            try await Task.sleep(for: .milliseconds(200))
        }
        throw SourceFailure(kind: .failed, message: "the bulk job did not finish")
    }

    static func trash(tag: String) async throws {
        try await bulkAction(["action": "transition", "state": "trashed"], tag: tag)
    }

    /// Purges the trashed items tagged `tag`, as a connector's clean-up does: the ids first, then the purge naming them.
    static func purge(tag: String) async throws {
        let listed = try await send("POST", "/items/bulk-actions", body: try json([
            "action": "purge", "confirm": "PURGE", "dry_run": true, "max_items": 50_000, "filter": ["tags": [tag], "state": "trashed"],
        ]))
        let ids = (listed.object?["ids"] as? [String]) ?? []
        try #require(listed.status == 200, "purge listing answered \(listed.status) \(listed.text)")
        guard !ids.isEmpty else { return }
        try await bulkAction(["action": "purge", "confirm": "PURGE", "expected_ids": ids], tag: tag, state: "trashed")
    }

    /// Whatever was made under `tag`, whatever state it is in. Safe to run again.
    static func removeAll(tag: String) async {
        do {
            try await trash(tag: tag)
            try await purge(tag: tag)
        } catch {
            Issue.record("could not remove the items tagged \(tag): \(error)")
        }
    }
}

/// What MAPP's engine costs over a real core, against a test instance: opening a copy, reading it all again, what
/// the main actor does after a change, a write's round trip, and following a server that deletes a lot at once.
/// Run it with the Measure test plan, given a test instance's address and key through `TEST_RUNNER_MARFA_API_URL`
/// and `TEST_RUNNER_MARFA_API_KEY`. It prints one `ENGINE|<name>|<value>|<unit>` line per number and checks only
/// that each step reached its end: the numbers are for a person to read, never a gate. It creates and purges items
/// on the instance, so it is for a test instance only; every item it makes is titled `MAPPTEST` and is removed
/// when the test ends, passed or not.
@MainActor
@Suite(
    .tags(.measure), .enabled(if: ProcessInfo.processInfo.environment["MAPP_MEASURE"] != nil),
    .enabled(
        if: EngineServer.isGiven,
        "EngineCostTests need a test instance: give the Measure plan MARFA_API_URL and MARFA_API_KEY (TEST_RUNNER_MARFA_API_URL and TEST_RUNNER_MARFA_API_KEY to xcodebuild)"),
    .serialized)
struct EngineCostTests {
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private func line(_ name: String, _ value: Double, _ unit: String = "ms") {
        print("ENGINE|\(name)|\(String(format: unit == "count" ? "%.0f" : "%.1f", value))|\(unit)")
    }

    private func line(_ name: String, _ duration: Duration) { line(name, Self.ms(duration)) }

    private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    /// A copy of the instance on a temporary store, with a key in memory, and the library over it.
    private struct Open {
        let source: MarfaSource
        let library: MarfaLibrary
    }

    private final class Bench {
        let root = URL.temporaryDirectory.appending(path: "EngineCostTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let made = LiveMarfa.Made()
        var sources: [MarfaSource] = []
        var tags: [String] = []

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    private func open(_ bench: Bench) async throws -> Open {
        let connection = try MarfaConnection(address: try LiveMarfa.address())
        let source = try await MarfaSource.open(
            connection, keys: MemoryKeyStore([connection: try LiveMarfa.key()]), location: MarfaStoreLocation(root: bench.root))
        bench.sources.append(source)
        let library = MarfaLibrary(source: source, notices: Notices())
        source.refresh()
        return Open(source: source, library: library)
    }

    private func whole(_ library: MarfaLibrary) -> Bool {
        LiveMarfa.isWhole(library.syncReport) && library.connection == .online
    }

    /// Runs `body` with a bench, and removes everything the run made on the server and on disk, however it ends.
    private func withBench(_ body: (Bench) async throws -> Void) async throws {
        let bench = Bench()
        let counts = try await EngineServer.counts()
        line("server_items", Double(counts.total), "count")
        line("server_items_active", Double(counts.active), "count")
        func end() async {
            for source in bench.sources { await source.close() }
            for tag in bench.tags { await EngineServer.removeAll(tag: tag) }
            await LiveMarfa.purge(bench.made.ids)
        }
        do {
            try await body(bench)
        } catch {
            await end()
            throw error
        }
        await end()
    }

    /// The copy opened and made whole, and the library over it.
    private func openWhole(_ bench: Bench) async throws -> Open {
        let opened = try await open(bench)
        try #require(await eventually { opened.library.isLoaded && whole(opened.library) })
        await opened.source.engineTook()
        return opened
    }

    /// Opens a copy and times it to the first `.loaded` the library applies and to the fill being complete.
    private func timeOpen(_ bench: Bench, _ label: String) async throws -> Open {
        let start = ContinuousClock.now
        let opened = try await open(bench)
        try #require(await eventually { opened.library.isLoaded })
        let loaded = ContinuousClock.now - start
        line("\(label)_to_first_loaded", loaded)
        line("\(label)_first_loaded_items", Double(opened.library.count(in: .allNotes)), "count")
        try #require(await eventually { self.whole(opened.library) })
        line("\(label)_to_complete", ContinuousClock.now - start)
        await opened.source.engineTook()
        line("\(label)_to_engine_idle", ContinuousClock.now - start)
        line("\(label)_library_items", Double(opened.library.count(in: .allNotes)), "count")
        return opened
    }

    // MARK: 1 and 2

    @Test(.timeLimit(.minutes(10)))
    func coldOpen() async throws {
        try await withBench { bench in
            _ = try await timeOpen(bench, "cold_open")
        }
    }

    /// The same store closed and opened again, so its first paint holds everything.
    @Test(.timeLimit(.minutes(10)))
    func warmOpen() async throws {
        try await withBench { bench in
            let first = try await openWhole(bench)
            await first.source.close()
            _ = try await timeOpen(bench, "warm_open")
        }
    }

    // MARK: 3

    @Test(.timeLimit(.minutes(10)))
    func wholeReload() async throws {
        try await withBench { bench in
            let opened = try await openWhole(bench)
            var reloads: [Double] = []
            for _ in 0..<3 {
                await opened.source.engineTook()
                let start = ContinuousClock.now
                await opened.source.engine.reload()
                reloads.append(Self.ms(ContinuousClock.now - start))
            }
            line("reload_median", median(reloads))
            line("reload_max", reloads.max() ?? 0)

            // A library that takes the whole snapshot, as the first library over a copy does.
            var walls: [Double] = []
            var busy: [Double] = []
            var longest: [Double] = []
            for _ in 0..<3 {
                let meter = MainActorMeter()
                meter.start()
                let start = ContinuousClock.now
                let fresh = MarfaLibrary(source: opened.source, notices: Notices())
                try #require(await eventually { fresh.isLoaded })
                walls.append(Self.ms(ContinuousClock.now - start))
                await meter.stop()
                busy.append(Self.ms(meter.busy))
                longest.append(Self.ms(meter.longest))
                withExtendedLifetime(fresh) {}
            }
            line("library_apply_wall_median", median(walls))
            line("library_apply_wall_max", walls.max() ?? 0)
            line("library_apply_main_actor_busy_median", median(busy))
            line("library_apply_main_actor_longest_block_max", longest.max() ?? 0)
        }
    }

    // MARK: 4

    @Test(.timeLimit(.minutes(10)))
    func mainActorCostAfterAChange() async throws {
        try await withBench { bench in
            let opened = try await openWhole(bench)
            let library = opened.library
            let id = try #require(library.createItem(
                typeID: "core.note", title: "MAPPTEST change 0", body: "", properties: [:], parentID: nil, in: .allNotes, undoManager: nil))
            bench.made.add(id)
            try #require(await eventually { library.item(id)?.sync == .settled })

            let places: [(String, SidebarItem)] = [("all_items", .allNotes), ("inbox", .inbox)]
                + library.catalogue.itemTypes.keys.sorted { $0.rawValue < $1.rawValue }.map { ("type_\($0.rawValue)", .itemType($0.rawValue)) }
            var itemsTimes: [String: [Double]] = [:]
            var countTimes: [String: [Double]] = [:]
            var totals: [Double] = []
            for round in 1...3 {
                #expect(library.setItemProperty(id, key: "title", value: .string("MAPPTEST change \(round)"), undoManager: nil))
                try #require(await eventually { library.item(id)?.title == "MAPPTEST change \(round)" })
                var total = Duration.zero
                for (name, place) in places {
                    let start = ContinuousClock.now
                    _ = library.items(in: place)
                    let items = ContinuousClock.now - start
                    let counting = ContinuousClock.now
                    _ = library.count(in: place)
                    let count = ContinuousClock.now - counting
                    itemsTimes[name, default: []].append(Self.ms(items))
                    countTimes[name, default: []].append(Self.ms(count))
                    total += items + count
                }
                totals.append(Self.ms(total))
                try #require(await eventually { library.item(id)?.sync == .settled })
                await opened.source.engineTook()
            }
            // Only the places that hold items are listed one by one; the rest are in the totals.
            for (name, place) in places where name == "all_items" || name == "inbox" || library.count(in: place) > 0 {
                line("change_items_\(name)_median", median(itemsTimes[name] ?? [0]))
                line("change_count_\(name)_median", median(countTimes[name] ?? [0]))
            }
            line("change_places", Double(places.count), "count")
            line("change_all_places_median", median(totals))
            line("change_all_places_max", totals.max() ?? 0)
        }
    }

    // MARK: 5

    @Test(.timeLimit(.minutes(10)))
    func writeRoundTripAndTheLoop() async throws {
        try await withBench { bench in
            let opened = try await openWhole(bench)
            let library = opened.library, source = opened.source
            let id = try #require(library.createItem(
                typeID: "core.note", title: "MAPPTEST write", body: "First", properties: [:], parentID: nil, in: .allNotes, undoManager: nil))
            bench.made.add(id)
            try #require(await eventually { library.item(id)?.sync == .settled })
            await source.engineTook()

            var rest: [Double] = []
            for _ in 0..<20 {
                let start = ContinuousClock.now
                await source.engineTook()
                rest.append(Self.ms(ContinuousClock.now - start))
                // Spaces the samples of the loop at rest.
                try await Task.sleep(for: .milliseconds(50))
            }
            line("loop_at_rest_median", median(rest))
            line("loop_at_rest_max", rest.max() ?? 0)

            let probe = LoopProbe(source, every: .milliseconds(100))
            let read = library.body(of: id)?.version ?? library.item(id)?.version ?? ItemVersion(0)
            let start = ContinuousClock.now
            library.saveText("Second, typed by the engine cost test", of: id, readAt: read, failing: "MAPPTEST save")
            await source.queueSubmitted()
            line("save_to_queued", ContinuousClock.now - start)
            try #require(await eventually { library.item(id)?.sync == .settled })
            let answered = ContinuousClock.now - start
            line("save_round_trip", answered)
            // Keeps probing for ten seconds in all after the save, to see what the engine does once it is settled.
            try await Task.sleep(for: .seconds(10) - answered)
            let samples = await probe.stop()
            line("loop_after_save_probes", Double(samples.count), "count")
            line("loop_after_save_longest_wait", samples.longest)
            line("loop_after_save_over_250ms", samples.behind(by: .milliseconds(250)))
            let afterAnswer = samples.all.filter { $0.at >= answered }
            line("loop_after_answer_longest_wait", afterAnswer.map(\.wait).max() ?? .zero)
            line("loop_after_answer_over_250ms", LoopProbe.Samples(all: afterAnswer).behind(by: .milliseconds(250)))
            #expect(library.body(of: id)?.text == "Second, typed by the engine cost test")
        }
    }

    // MARK: 6

    /// The step a catch-up's `.refreshed(.caughtUp)` costs the engine after one change on the server, which the
    /// follow has already shown: what a catch-up costs when there is little to catch up on.
    @Test(.timeLimit(.minutes(10)))
    func catchUpAfterOneRemoteChange() async throws {
        try await withBench { bench in
            let opened = try await openWhole(bench)
            let library = opened.library, source = opened.source
            var steps: [Double] = []
            for round in 0..<5 {
                // A tag of its own each round, since a note's source id is its tag and its place in the call.
                let tag = "mapptest-catchup-\(UUID().uuidString.prefix(8).lowercased())"
                bench.tags.append(tag)
                let made = try await EngineServer.createNotes(count: 1, tag: tag)
                try #require(await eventually(within: .seconds(60)) { made.allSatisfy { library.item($0) != nil } }, "round \(round)")
                await source.engineTook()
                let start = ContinuousClock.now
                source.hear(Change(origin: .refreshed(.caughtUp), itemId: nil, edgeId: nil))
                await source.engineTook()
                steps.append(Self.ms(ContinuousClock.now - start))
            }
            line("catch_up_one_change_median", median(steps))
            line("catch_up_one_change_max", steps.max() ?? 0)
        }
    }

    /// Reading what every row's text links and embeds, as a whole read does when nothing is known yet.
    @Test(.timeLimit(.minutes(10)))
    func linkReadsOfEveryRow() async throws {
        try await withBench { bench in
            let opened = try await openWhole(bench)
            var reads: [Double] = []
            var asked = 0
            for _ in 0..<3 {
                await opened.source.engineTook()
                let start = ContinuousClock.now
                asked = await opened.source.engine.readLinksOfEveryRow()
                reads.append(Self.ms(ContinuousClock.now - start))
            }
            line("links_rows_asked", Double(asked), "count")
            line("links_every_row_median", median(reads))
            line("links_every_row_max", reads.max() ?? 0)
        }
    }

    // MARK: 7

    @Test(.timeLimit(.minutes(30)))
    func floodOfCreatesThenDeletes() async throws {
        let flood = Int(ProcessInfo.processInfo.environment["MAPP_ENGINE_FLOOD"] ?? "") ?? 2000
        try await withBench { bench in
            let opened = try await openWhole(bench)
            let library = opened.library, source = opened.source
            line("flood_items", Double(flood), "count")
            let tag = "mapptest-flood-\(UUID().uuidString.prefix(8).lowercased())"
            bench.tags.append(tag)

            let meter = MainActorMeter()
            meter.start()
            var probe = LoopProbe(source, every: .milliseconds(250))
            var start = ContinuousClock.now
            let ids = try await EngineServer.createNotes(count: flood, tag: tag)
            line("flood_create_server", ContinuousClock.now - start)
            try #require(await eventually(within: .seconds(600)) { ids.allSatisfy { library.item($0) != nil } })
            line("flood_create_to_library_holds_all", ContinuousClock.now - start)
            var samples = await probe.stop()
            line("flood_create_probe_longest_wait", samples.longest)
            line("flood_create_seconds_over_5s_behind", Self.ms(samples.behind(by: .seconds(5))) / 1000, "s")
            await source.engineTook()
            line("flood_create_to_engine_idle", ContinuousClock.now - start)

            probe = LoopProbe(source, every: .milliseconds(250))
            start = ContinuousClock.now
            try await EngineServer.trash(tag: tag)
            line("flood_delete_server", ContinuousClock.now - start)
            let purging = ContinuousClock.now
            try await EngineServer.purge(tag: tag)
            line("flood_purge_server", ContinuousClock.now - purging)
            try #require(await eventually(within: .seconds(1800)) { ids.allSatisfy { library.item($0) == nil } })
            line("flood_delete_to_library_holds_none", ContinuousClock.now - start)
            samples = await probe.stop()
            await meter.stop()
            line("flood_delete_probes", Double(samples.count), "count")
            line("flood_delete_probe_longest_wait", samples.longest)
            line("flood_delete_seconds_over_5s_behind", Self.ms(samples.behind(by: .seconds(5))) / 1000, "s")
            await source.engineTook()
            line("flood_delete_to_engine_idle", ContinuousClock.now - start)
            line("flood_main_actor_busy", meter.busy)
            line("flood_main_actor_longest_block", meter.longest)
        }
    }
}
