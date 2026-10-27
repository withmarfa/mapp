import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MAPP

extension Tag {
    /// Timing runs that print numbers rather than check behavior. The Measure test plan selects them and sets
    /// `MAPP_MEASURE`, which they need to run; any other plan reports them skipped.
    @Tag static var measure: Self
}

/// About 650 items shaped like a working Marfa record: several types with status, priority and date fields,
/// a few epics and projects holding the rest through `child-of`, and some favorites. Made in code so that a run
/// needs no server, no key and none of anyone's data.
nonisolated enum BigLibrary {
    static let session = TypeID("aic.session"), decision = TypeID("aic.decision"), epic = TypeID("aic.ticket.epic")
    static let task = TypeID("aic.ticket.task"), feature = TypeID("aic.ticket.feature"), spike = TypeID("aic.ticket.spike")
    static let log = TypeID("aic.log"), note = TypeID("core.note"), project = TypeID("aic.project")

    private static func field(_ key: String, _ kind: ItemTypeInfo.Field.Kind, in type: TypeID) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(key: key, label: MarfaMapping.label(forField: key), kind: kind, declaredBy: type)
    }

    private static func info(_ id: TypeID, _ label: String, _ extra: [ItemTypeInfo.Field]) -> ItemTypeInfo {
        ItemTypeInfo(
            id: id, label: label, fields: [field("title", .text, in: id), field("body", .text, in: id)] + extra,
            titleField: "title", bodyField: "body", parent: nil)
    }

    static let catalogue: Catalogue = {
        let day = ItemTypeInfo.Field.Kind.date(includesTime: false), time = ItemTypeInfo.Field.Kind.date(includesTime: true)
        func ticket(_ id: TypeID, _ label: String) -> ItemTypeInfo {
            info(id, label, [
                field("status", .choice(["backlog", "todo", "in_progress", "in_review", "done", "canceled"]), in: id),
                field("priority", .choice(["low", "medium", "high"]), in: id), field("due_at", day, in: id),
                field("assignee", .text, in: id), field("estimate", .number, in: id), field("blocked", .boolean, in: id),
            ])
        }
        let catalogue = Catalogue(itemTypes: [
            info(session, "Session", [
                field("status", .choice(["planned", "running", "closed"]), in: session), field("starts_at", time, in: session),
                field("ends_at", time, in: session), field("number", .number, in: session),
            ]),
            info(decision, "Decision", [
                field("status", .choice(["proposed", "accepted", "superseded"]), in: decision), field("decided_at", day, in: decision),
                field("area", .text, in: decision),
            ]),
            ticket(epic, "Epic"), ticket(task, "Task"), ticket(feature, "Feature"), ticket(spike, "Spike"),
            info(log, "Log", [field("occurred_at", time, in: log)]),
            info(note, "Note", []),
            info(project, "Project", [field("status", .choice(["active", "paused", "done"]), in: project), field("due_at", day, in: project)]),
        ], edgeTypes: LibraryFixture.catalogue.edgeTypes.values.map { $0 })
        return catalogue
    }()

    /// A fixed pseudo-random run, so every run times the same data.
    private struct Rng: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let counts: [(TypeID, Int)] = [
        (session, 90), (decision, 175), (task, 180), (feature, 40), (spike, 20), (epic, 30), (log, 60), (note, 40), (project, 15),
    ]

    static func items() -> [Item] {
        var rng = Rng(state: 137)
        func pick<T>(_ values: [T]) -> T { values[Int(rng.next() % UInt64(values.count))] }
        func day(_ offset: Int) -> String {
            let date = Date(timeIntervalSince1970: 1_780_000_000 - Double(offset) * 86_400)
            return date.formatted(.iso8601.year().month().day())
        }
        func time(_ offset: Int, hours: Int = 0) -> String {
            Date(timeIntervalSince1970: 1_780_000_000 - Double(offset) * 86_400 + Double(hours) * 3600).formatted(.iso8601)
        }
        var made: [Item] = []
        var parents: [ItemID] = []
        for (type, count) in counts {
            for index in 0..<count {
                let id = ItemID("\(type.rawValue)-\(index)")
                var properties = [Property(key: "title", value: .string("\(pick(["Fix", "Plan", "Review", "Ship", "Decide", "Move", "Trim"])) \(pick(["sidebar", "table", "sync", "search", "layout", "keys", "docs"])) number \(index)"))]
                func add(_ key: String, _ value: PropertyValue) { properties.append(Property(key: key, value: value)) }
                let age = Int(rng.next() % 400)
                switch type {
                case session:
                    add("status", .string(pick(["planned", "running", "closed", "closed", "closed"])))
                    add("starts_at", .string(time(age))); add("ends_at", .string(time(age, hours: 1 + Int(rng.next() % 6))))
                    add("number", .number(Decimal(index + 1)))
                case decision:
                    add("status", .string(pick(["accepted", "accepted", "proposed", "superseded"])))
                    add("decided_at", .string(day(age))); add("area", .string(pick(["app", "contract", "docs", "release"])))
                case log:
                    add("occurred_at", .string(time(age)))
                case note:
                    break
                case project:
                    add("status", .string(pick(["active", "paused", "done"]))); add("due_at", .string(day(age - 60)))
                default:
                    add("status", .string(pick(["backlog", "todo", "in_progress", "in_review", "done", "done", "canceled"])))
                    // A few tickets carry no priority, as in the record, so the sort meets an absent field.
                    if rng.next() % 5 != 0 { add("priority", .string(pick(["low", "medium", "high"]))) }
                    if rng.next() % 2 == 0 { add("due_at", .string(day(age - 30))) }
                    if rng.next() % 3 == 0 { add("assignee", .string(pick(["august", "claude", "codex"]))) }
                    if rng.next() % 4 == 0 { add("estimate", .number(Decimal(Int(rng.next() % 13)))) }
                }
                var item = LibraryFixture.item(
                    id, type, properties[0].value.string ?? "", age: age * 3600, tags: rng.next() % 25 == 0 ? [ItemTag.favorite] : [],
                    properties: properties)
                if type == epic || type == project { parents.append(id) }
                if [task, feature, spike, session, decision].contains(type), !parents.isEmpty, rng.next() % 4 != 0 {
                    item.edgesOut = [LibraryFixture.child("\(id.rawValue)#child-of", id, of: pick(parents))]
                }
                made.append(item)
            }
        }
        return made
    }

    @MainActor
    static func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items(), catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }
}

/// What moving around the window costs, timed on 650 items (`BigLibrary`). It prints one line per action for
/// each place, `COST|<place>|<action>|<milliseconds>|<runs>`, and checks only that the data is the size it claims.
/// Run it with the Measure test plan; the numbers are for a person to read, never a gate.
@MainActor
@Suite(.tags(.measure), .enabled(if: ProcessInfo.processInfo.environment["MAPP_MEASURE"] != nil), .serialized)
struct NavigationCostTests {
    private let order = NoteOrder()

    /// The median of a few runs, in milliseconds.
    private func median(_ runs: Int = 7, _ work: () -> Void) -> Double {
        var times: [Double] = []
        for _ in 0..<runs {
            let start = ContinuousClock.now
            work()
            let elapsed = ContinuousClock.now - start
            times.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        return times.sorted()[times.count / 2]
    }

    private func line(_ place: String, _ action: String, _ ms: Double, runs: Int = 1) {
        print("COST|\(place)|\(action)|\(String(format: "%.2f", ms))|\(runs)")
    }

    @Test func sizesOfTheData() async throws {
        let (library, _) = try await BigLibrary.loaded()
        #expect(library.items(in: .allNotes).count == BigLibrary.counts.map(\.1).reduce(0, +))
    }

    @Test func eachActionInEachPlace() async throws {
        let (library, _) = try await BigLibrary.loaded()
        let places: [(String, SidebarItem)] = [
            ("all", .allNotes), ("decisions", .itemType("aic.decision")), ("tasks", .itemType("aic.ticket.task")),
            ("sessions", .itemType("aic.session")), ("recents", .recents), ("favorites", .favorites),
        ]
        for (name, place) in places {
            let browser = Browser()
            browser.sidebarItem = place
            let count = browser.items(in: library).count
            line(name, "items(\(count))", median { _ = browser.items(in: library) })
            line(name, "sections", median { _ = browser.sections(in: library, order: order, now: .now) })
            line(name, "viewModes", median { _ = browser.availableViewModes(in: library) })
            line(name, "tableInit", median { _ = ItemTableContent(browser: browser, library: library, items: browser.items(in: library)) })
            line(name, "tableRows", median { _ = ItemTableContent(browser: browser, library: library, items: browser.items(in: library)).rows })
            line(name, "tableGroups", median { _ = ItemTableContent(browser: browser, library: library, items: browser.items(in: library)).groups })
            let content = ItemTableContent(browser: browser, library: library, items: browser.items(in: library))
            for column in content.columns where ["title", "field.status", "field.priority", "field.due_at", "edited"].contains(column.id) || column.id.hasSuffix("starts_at") {
                let comparator = ItemTableComparator(column: column, order: column.firstOrder)
                line(name, "sort[\(column.id)]", median { _ = ItemTableLayout.sorted(content.allRows, by: [comparator]) })
            }
            let items = browser.items(in: library)
            line(name, "boardFields", median { _ = ItemBoardLayout.availableFields(items: items, catalogue: library.catalogue) })
            line(name, "timelineFields", median { _ = ItemTimelineLayout.fields(for: items, catalogue: library.catalogue) })
        }
    }

    /// How often each cost runs for one window render of each layout, as the views ask for them today.
    @Test func countsForOneNavigation() async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = Browser()
        browser.sidebarItem = .itemType("aic.decision")
        #if DEBUG
        Cost.resetTallies()
        _ = ItemTableContent(browser: browser, library: library, items: browser.items(in: library)).rows
        for (cost, tally) in Cost.tallies.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("COUNT|one table content|\(cost.rawValue)|\(tally.count)|\(String(format: "%.2f", tally.milliseconds))")
        }
        #endif
    }

    /// The real window, hosted in a window nobody sees: for each move a person makes, how many times each cost ran
    /// before the window was still again, and how long the main actor spent on it all. The editor's web view is
    /// part of the window, so the wall time here includes whatever the window does besides these costs.
    @Test func aHostedWindowAcrossTheMovesAPersonMakes() async throws {
        #if DEBUG
        let (library, _) = try await BigLibrary.loaded()
        let browser = Browser()
        let libraries = ItemPreviewFixtures.libraries(named: "MAPP.NavigationCost")
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 1280, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(browser: browser, details: DetailsPresentation(), restoresWindow: false)
            .environment(\.library, library)
            .environment(libraries))
        window.makeKeyAndOrderFront(nil)
        defer { window.performClose(nil); window.contentView = nil }

        /// Runs `move`, waits until nothing more is made for a moment, and prints what ran.
        func step(_ name: String, _ move: () -> Void) async throws {
            try await Task.sleep(for: .milliseconds(400))
            Cost.resetTallies()
            let start = ContinuousClock.now
            move()
            var last = -1
            var stall = 0.0
            while true {
                // A short sleep that wakes late says how long the main actor was held in between.
                for _ in 0..<30 {
                    let before = ContinuousClock.now
                    try await Task.sleep(for: .milliseconds(5))
                    let late = (ContinuousClock.now - before) - .milliseconds(5)
                    stall = max(stall, Double(late.components.seconds) * 1000 + Double(late.components.attoseconds) / 1e15)
                }
                let now = Cost.tallies.values.map(\.count).reduce(0, +)
                if now == last { break }
                last = now
            }
            let rows = window.contentView.map { Self.tableRows(in: $0) } ?? []
            let counts = Cost.tallies.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue)=\($0.value.count)x\(String(format: "%.1f", $0.value.milliseconds))ms" }.joined(separator: " ")
            _ = start
            print("HOSTED|\(name)|\(counts)|longest main-actor stall=\(String(format: "%.1f", stall))ms|table rows=\(rows)")
        }

        try await step("open decisions (list)") { browser.sidebarItem = .itemType("aic.decision") }
        try await step("table") { browser.viewMode = .table }
        try await step("select a row") { browser.selection = [library.items(in: .itemType("aic.decision"))[3].id] }
        try await step("select another row") { browser.selection = [library.items(in: .itemType("aic.decision"))[4].id] }
        try await step("tasks (table)") { browser.sidebarItem = .itemType("aic.ticket.task") }
        try await step("board") { browser.viewMode = .board }
        try await step("timeline") { browser.viewMode = .timeline }
        try await step("gallery") { browser.viewMode = .gallery }
        try await step("list") { browser.viewMode = .list }
        try await step("all items (list)") { browser.sidebarItem = .allNotes }
        try await step("table") { browser.viewMode = .table }
        #endif
    }

    /// The row counts of every table the window holds, found in its view tree.
    private static func tableRows(in view: NSView) -> [Int] {
        (view as? NSTableView).map { [$0.numberOfRows] } ?? view.subviews.flatMap { tableRows(in: $0) }
    }
}
