import os
import XCTest

/// Times what a person feels in the window, on a library held by a real Marfa test instance: launching to a usable
/// window, choosing a place, opening an item, New and Search answering, and typing. It gates nothing: every
/// iteration that completes passes, and the numbers are for a person to read.
///
/// It runs only in the `Measure UI` plan with `MAPP_MEASURE_UI` set and the instance's address and key given as
/// `MARFA_API_URL` and `MARFA_API_KEY` (xcodebuild's `TEST_RUNNER_` prefix hands them over); otherwise each test is
/// skipped. The one write is a note it makes for the typing; `Scripts/measure-ui.sh` removes it afterwards.
///
/// Each test prints `UI|<name>|<median>|<max>|<unit>` lines after XCTest's own report, for the time the test itself
/// saw, from the action to the result it waited for. That includes UI testing's own query cost, so it bounds what a
/// person feels from above. The app's own measure of the same work, its signposts, launch line and slow events, is in
/// the unified log, which a sandboxed test cannot read: `Scripts/measure-ui.sh` records it around the run and prints
/// the same kind of lines per test, between the `phase` markers each test logs (`MAPP/Model/AGENTS.md`, "Logs and
/// signposts").
@MainActor
final class SpeedMeasureTests: XCTestCase {
    private static let subsystem = "com.withmarfa.mapp.debug"
    private static let iterations = 5
    /// Marks where each test's measured part begins and ends, and which process the app is, in the log, for
    /// `Scripts/measure-ui.sh`; another session's debug build shares the subsystem.
    private static let phases = Logger(subsystem: "com.withmarfa.mapp.speedtest", category: "phase")
    /// Whether this run has left a complete copy of the instance for a warm launch to open.
    private static var hasCopy = false

    private var address = ""
    private var key = ""
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var label = ""
    private var samples: [String: [Double]] = [:]

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = Self.iterations
        return options
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["MAPP_MEASURE_UI"] != nil, "MAPP_MEASURE_UI is not set")
        address = try XCTUnwrap(environment["MARFA_API_URL"], "A test instance's address is needed (MARFA_API_URL)")
        key = try XCTUnwrap(environment["MARFA_API_KEY"], "A key for the test instance is needed (MARFA_API_KEY)")
    }

    override func tearDown() async throws {
        app?.terminate()
        guard !label.isEmpty else { return }
        Self.phases.notice("end \(self.label, privacy: .public)")
        for (name, values) in samples.sorted(by: { $0.key < $1.key }) {
            let sorted = values.sorted()
            let median = (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
            print("UI|\(label).\(name)|\(String(format: "%.1f", median))|\(String(format: "%.1f", sorted.last ?? 0))|ms")
        }
    }

    // MARK: Launch

    func testLaunchCold() throws {
        try begin("launch.cold")
        app = makeApp(keepingCopy: false)
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            launchAndWait()
        }
        Self.hasCopy = true
    }

    func testLaunchWarm() throws {
        try seedCopy()
        try begin("launch.warm")
        app = makeApp(keepingCopy: true)
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            launchAndWait()
        }
    }

    // MARK: Moving about

    func testChoosingPlaces() throws {
        try launchWarm()
        let types = typeRows().prefix(2)
        try XCTSkipIf(types.count < 2, "The instance shows fewer than two types in the sidebar")
        let items = sidebarElement("SidebarPlace-all")
        let places = [items, sidebarText("Inbox")] + types.map(sidebarElement) + [items]
        // The window's title starts with the place's name, which is how a choice is seen to have landed.
        let titles = places.map(\.placeName)
        let spots = places.map(spot)
        try begin("places")
        measure(metrics: [signpost("place.choose"), XCTClockMetric(), XCTHitchMetric(application: app)], options: options) {
            for (spot, title) in zip(spots, titles) {
                time("choose") { spot.click() }
                XCTAssertTrue(waitUntil { self.window.title.hasPrefix(title) }, "the window shows \(title)")
            }
        }
    }

    func testMovingBetweenListAndGallery() throws {
        try launchWarm()
        let place = try XCTUnwrap(typeRows().first, "The instance shows a type in the sidebar")
        sidebarElement(place).click()
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        try begin("layout")
        measure(metrics: [XCTClockMetric(), XCTHitchMetric(application: app)], options: options) {
            for (mode, key, shown) in [("gallery", "2", self.element("ItemGallery")), ("list", "1", self.list)] {
                time(mode) { self.app.typeKey(key, modifierFlags: .command) }
                XCTAssertTrue(self.waitUntil { shown.exists }, "\(mode) showed")
            }
        }
    }

    func testOpeningItems() throws {
        try launchWarm()
        let place = try XCTUnwrap(typeRows().first, "The instance shows a type in the sidebar")
        sidebarElement(place).click()
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        XCTAssertTrue(list.outlineRows.element(boundBy: 4).waitForExistence(timeout: 20), "the place holds five items")
        let spots = (0..<5).map { spot(list.outlineRows.element(boundBy: $0)) }
        try begin("items")
        measure(metrics: [signpost("item.open"), XCTClockMetric(), XCTHitchMetric(application: app)], options: options) {
            for spot in spots {
                time("open") { spot.click() }
            }
        }
    }

    // MARK: Panels

    func testNewOpensQuickAdd() throws {
        try launchWarm()
        try begin("quickAdd")
        let field = element("QuickAddTitle")
        measure(metrics: [signpost("quickAdd.open"), XCTClockMetric()], options: options) {
            // Both calls return once the app is idle, so a letter typed before the field had the keyboard would be lost.
            time("ready") {
                app.typeKey("n", modifierFlags: .command)
                app.typeText("a")
            }
            XCTAssertTrue(waitUntil { (field.value as? String) == "a" }, "the title field took the keyboard")
            // Leave the draft empty, so the next iteration starts as the first did.
            app.typeKey("a", modifierFlags: .command)
            app.typeKey(.delete, modifierFlags: [])
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        }
    }

    func testSearchOpensThePalette() throws {
        try launchWarm()
        try begin("palette")
        let field = element("CommandPaletteField")
        measure(metrics: [XCTClockMetric()], options: options) {
            time("ready") {
                app.typeKey("p", modifierFlags: [.command, .shift])
                app.typeText("a")
            }
            XCTAssertTrue(waitUntil { (field.value as? String) == "a" }, "the palette's field took the keyboard")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        }
    }

    // MARK: Typing

    /// Makes a note and types forty characters into its page one key at a time; `Scripts/measure-ui.sh` removes the
    /// note afterwards. A keystroke's time runs from the key event until the app is idle again; the page reports no
    /// echo to wait on, and reading its accessibility value costs more than a keystroke, so the text is checked once
    /// at the end. The total is the sum.
    func testTypingInANote() throws {
        try launchWarm()
        try begin("typing")
        let title = "Speed measure \(UUID().uuidString.prefix(8))"
        // The helper's waits allow for a small library; querying a tree this size takes seconds.
        let field = element("QuickAddTitle")
        element("SidebarNew").click()
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        element("QuickAddType").click()
        window.menuItems["Note"].click()
        field.click()
        field.typeText(title)
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: 30))
        let editor = window.itemPageBody
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        editor.click()
        let text = String(repeating: "the quick brown fox jumps over ", count: 2).prefix(40)
        for character in text { time("key") { app.typeText(String(character)) } }
        samples["total"] = [samples["key", default: []].reduce(0, +)]
        XCTAssertTrue(waitUntil { (editor.value as? String)?.hasSuffix(String(text)) == true }, "the text showed in the page")
    }

    // MARK: Helpers

    private func begin(_ name: String) throws {
        label = name
        samples = [:]
        Self.phases.notice("begin \(name, privacy: .public)")
    }

    private func makeApp(keepingCopy: Bool) -> XCUIApplication {
        let app = XCUIApplication.sample(flags: keepingCopy ? ["-MAPPKeepTestStore"] : [])
        app.launchEnvironment["MAPP_TEST_MARFA_URL"] = address
        app.launchEnvironment["MAPP_TEST_MARFA_KEY"] = key
        return app
    }

    /// One unmeasured cold launch, so a warm launch has a complete copy to open.
    private func seedCopy() throws {
        guard !Self.hasCopy else { return }
        app = makeApp(keepingCopy: false)
        launchAndWait()
        app.terminate()
        Self.hasCopy = true
    }

    private func launchWarm() throws {
        try seedCopy()
        app = makeApp(keepingCopy: true)
        launchAndWait()
    }

    /// Launches and waits for the window to show the library, filled from the copy and the server. It is the time a
    /// person waits, seen from outside.
    private func launchAndWait() {
        if app.state != .notRunning { app.terminate() }
        time("shown") {
            app.launch()
            // XCUIApplication does not publish its process ID; the key is private but long-standing.
            if let pid = self.app.value(forKey: "processID") as? Int32 { Self.phases.notice("pid \(pid)") }
            XCTAssertTrue(waitUntil(timeout: 300) { self.showsLibrary }, "the library showed")
        }
    }

    /// The sidebar lists the library's types, which it can only do once the copy has loaded, and the fill is done.
    private var showsLibrary: Bool {
        let type = sidebar.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'SidebarType-'"))
        return type.firstMatch.exists && !element("LibraryFillProgress").exists
    }

    private func signpost(_ name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: Self.subsystem, category: "navigation", name: name)
    }

    private func time(_ name: String, _ work: () -> Void) {
        let start = ContinuousClock.now
        work()
        samples[name, default: []].append((ContinuousClock.now - start).milliseconds)
    }

    /// Polls as fast as UI testing's own queries allow, since a sleep between them would be counted as the app's time.
    private func waitUntil(timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
        }
        return false
    }

    private func element(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    private func sidebarText(_ title: String) -> XCUIElement {
        sidebar.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", title, title)).element(boundBy: 0)
    }

    /// The identifiers of the sidebar's type rows, in order, once each.
    private func typeRows() -> [String] {
        var seen: [String] = []
        let rows = sidebar.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'SidebarType-'"))
        for row in rows.allElementsBoundByIndex where !seen.contains(row.identifier) { seen.append(row.identifier) }
        return seen
    }

    private func sidebarElement(_ identifier: String) -> XCUIElement {
        sidebar.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    /// Where the element's middle is, as a point of the window, so a click on it needs no query of the tree. UI
    /// testing's own queries of a library this size take seconds, which would be counted as the app's time.
    private func spot(_ element: XCUIElement) -> XCUICoordinate {
        let frame = element.frame
        let origin = window.frame.origin
        return window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX - origin.x, dy: frame.midY - origin.y))
    }
}

private extension XCUIElement {
    /// The name a place shows in the window's title: its label, or for a type its value before the count.
    var placeName: String {
        let text = label.isEmpty ? (value as? String ?? "") : label
        return String(text.prefix { $0 != "," })
    }
}

private extension Duration {
    var milliseconds: Double { Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15 }
}

