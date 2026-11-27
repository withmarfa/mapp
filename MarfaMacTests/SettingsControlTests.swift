import AppKit
import Marfa
import SwiftUI
import Synchronization
import Testing
@testable import MarfaMac

@MainActor @Suite(.serialized, .hangLimit)
struct SettingsControlTests {
    enum Finish: CaseIterable { case escape, submit, blur }

    @Test func pausedTelemetryLetsTheOwnerOpenTheirReportDestination() async throws {
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        let calls = FakeInstanceCalls()
        calls.changeElsewhere("telemetry_enabled", to: .bool(false))
        settings.instanceCalls = calls
        let model = MonitoringModel(context: OwnerContext(host: settings), calls: calls)
        let window = host(MonitoringPage(host: settings, model: model))
        defer { window.contentView = nil; window.close() }
        try await press(in: window, matching: "Monitoring-postHogHost", attribute: "accessibilityIdentifier")
        #expect(await eventually { model.sheet?.secret == .postHogHost })
    }

    @Test func storageWithReadAccessLoadsFileDetailsWithoutRequestingConfiguration() async throws {
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        settings.grants = [.instanceRead]
        let calls = FakeOwnerCalls()
        let configuration = FakeInstanceCalls()
        calls.state.withLock { $0.metrics = InstanceMetricsReading(version: "1", databaseBytes: 256, fileBytes: 512) }
        settings.ownerCalls = calls
        settings.instanceCalls = configuration
        let window = host(MarfaSettingsPageView(page: .fileStorage, host: settings))
        defer { window.contentView = nil; window.close() }
        #expect(await eventually { calls.calls.contains("fileStores") && calls.calls.contains("instanceMetrics") })
        #expect(configuration.calls.isEmpty)
        #expect(await eventually {
            window.contentView?.layoutSubtreeIfNeeded()
            return !elements(window.contentView, matching: "Database", attribute: "accessibilityValue").isEmpty
        })
    }

    @Test(arguments: [
        (OwnerFailure.signedOut, "Signed Out"), (.instanceChanged, "Another Marfa Answers"),
        (.notPermitted("profile:read"), "Needs a Permission"), (.unsupported, "No Server Settings"),
    ])
    func profileFailureGatesAccountControls(_ failure: OwnerFailure, title: String) async throws {
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        let calls = FakeOwnerCalls()
        calls.fail("profile", with: failure)
        settings.ownerCalls = calls
        let window = host(AccountPage(host: settings))
        defer {
            window.contentView = nil
            window.close()
        }
        try await press(in: window, matching: "AccountSignOut", attribute: "accessibilityIdentifier")
        #expect(await eventually(within: .seconds(3)) {
            window.contentView?.layoutSubtreeIfNeeded()
            return !elements(window.contentView, matching: title, attribute: "accessibilityValue").isEmpty
                && elements(window.contentView, matching: "AccountChangePassword", attribute: "accessibilityIdentifier").isEmpty
        })
    }

    @Test func returningToAccountRefreshesProblemsAndTheirBadge() async throws {
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        let calls = FakeOwnerCalls()
        calls.state.withLock { $0.concerns = [.init(kind: .clock, reference: "clock_ahead", title: "Clock changed")] }
        settings.ownerCalls = calls
        settings.bindOverview()
        await settings.overview.load()
        #expect(settings.overview.attentionBadge == 1)
        let window = host(AnyView(AccountPage(host: settings)))
        defer {
            window.contentView = nil
            window.close()
        }
        let content = try #require(window.contentView as? NSHostingView<AnyView>)
        try #require(await eventually { calls.calls.contains("housekeepingJobs") })
        content.rootView = AnyView(Text("Another page"))
        content.layoutSubtreeIfNeeded()
        calls.state.withLock { $0.concerns = [] }
        content.rootView = AnyView(AccountPage(host: settings))
        content.layoutSubtreeIfNeeded()
        #expect(await eventually(within: .seconds(3)) { settings.overview.concerns.isEmpty && settings.overview.attentionBadge == nil })
    }

    @Test func lockedProblemsAskForInstanceRead() async throws {
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        settings.grants.remove(.instanceRead)
        settings.bindOverview()
        let window = host(AccountPage(host: settings))
        defer {
            window.contentView = nil
            window.close()
        }
        try await press(in: window, matching: "Allow More", attribute: "accessibilityLabel")
        #expect(await eventually(within: .seconds(3)) { settings.allowed == [[.instanceRead]] })
    }

    @Test(arguments: [MarfaSettingsPage.account, .keys])
    func movedPagesFollowConnectionAndReadFailures(page: MarfaSettingsPage) async throws {
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        let calls = FakeOwnerCalls()
        settings.ownerCalls = calls
        let read = page == .account ? "profile" : "keys"
        let destination: MarfaSettingsPage = page == .account ? .network : .apps
        let link = "SettingsLink-\(destination.rawValue)"
        let pending = calls.hold(read)
        let window = host(MarfaSettingsPageView(page: page, host: settings))
        defer { pending.open(); window.contentView = nil; window.close() }

        try #require(await eventually { calls.state.withLock { $0.waiting[read] == 1 } })
        try await press(in: window, matching: link, attribute: "accessibilityIdentifier")
        #expect(settings.shown == [destination])

        calls.fail(read, with: .unreachable)
        pending.open()
        try #require(await eventually {
            window.contentView?.layoutSubtreeIfNeeded()
            if page == .account && !elements(window.contentView, matching: link, attribute: "accessibilityIdentifier").isEmpty { return false }
            return !elements(window.contentView, matching: "Try Again", attribute: "accessibilityLabel").isEmpty
        })
        if page == .account {
            try await press(in: window, matching: "AccountSignOut", attribute: "accessibilityIdentifier")
            #expect(settings.signOutRequests == 1)
        } else {
            try await press(in: window, matching: link, attribute: "accessibilityIdentifier")
            #expect(settings.shown == [destination, destination])
        }
    }

    @Test func accountLetsALimitedSignInSignOutAndAskForSecurityAccess() async throws {
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        settings.grants = []
        let window = host(MarfaSettingsPageView(page: .account, host: settings))
        defer { window.contentView = nil; window.close() }
        try await press(in: window, matching: "AccountSignOut", attribute: "accessibilityIdentifier")
        #expect(settings.signOutRequests == 1)
        try await press(in: window, matching: "AccountChangePassword", attribute: "accessibilityIdentifier")
        #expect(await eventually { settings.allowed == [[.signInsManage]] })
        for page in [MarfaSettingsPage.passkeys, .browsers] {
            try await press(in: window, matching: "SettingsLink-\(page.rawValue)", attribute: "accessibilityIdentifier")
        }
        #expect(settings.shown == [.passkeys, .browsers])
    }

    @Test(arguments: [MarfaSettingsPage.passkeys, .browsers])
    func anEmptySignInListShowsItsEmptyCard(_ page: MarfaSettingsPage) async throws {
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        let calls = FakeOwnerCalls()
        calls.state.withLock { $0.passkeys = []; $0.browsers = [] }
        settings.ownerCalls = calls
        let window = host(MarfaSettingsPageView(page: page, host: settings))
        defer { window.contentView = nil; window.close() }
        let title = page == .passkeys ? "No Passkeys" : "No Browsers"
        try #require(await eventually(within: .seconds(5)) {
            window.contentView?.layoutSubtreeIfNeeded()
            return !elements(window.contentView, matching: title, attribute: "accessibilityValue").isEmpty
        })
    }

    @Test(arguments: [MarfaSettingsPage.account, .passkeys, .browsers, .network])
    func anUnreachableServerOffersRetryAndSignOutOnlyFromAccount(_ page: MarfaSettingsPage) async throws {
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        settings.connection = .notAnswering(lastAnswered: nil)
        let calls = FakeOwnerCalls()
        settings.ownerCalls = calls
        let window = host(MarfaSettingsPageView(page: page, host: settings))
        defer { window.contentView = nil; window.close() }
        try #require(await eventually {
            window.contentView?.layoutSubtreeIfNeeded()
            return !elements(window.contentView, matching: "Try Again", attribute: "accessibilityLabel").isEmpty
        })
        #expect(calls.calls.isEmpty)
        if page == .account {
            try await press(in: window, matching: "AccountSignOut", attribute: "accessibilityIdentifier")
            #expect(settings.signOutRequests == 1)
            #expect(elements(window.contentView, matching: "AccountChangePassword", attribute: "accessibilityIdentifier").isEmpty)
        } else {
            #expect(elements(window.contentView, matching: "AccountSignOut", attribute: "accessibilityIdentifier").isEmpty)
        }
    }

    @Test(arguments: [0, 1], Finish.allCases)
    func finishFolderPattern(section: Int, finish: Finish) async throws {
        let folder = OwnerFolder(id: "folder", title: "Sample Folder")
        let calls = FakeOwnerCalls()
        calls.state.withLock {
            $0.folders = [folder]
            $0.reports[folder.id] = FolderReport(copies: [])
        }
        let folders = FakeFolderCalls(FakeFolderCalls.folder(folder.id, folder.title))
        let settings = StubMarfaHost(settings: InstanceSettingsModel { nil })
        settings.ownerCalls = calls
        settings.folderCalls = folders
        let window = host(FoldersPage(host: settings, subpage: FoldersPage.subpage(for: folder)))
        defer { window.contentView = nil; window.close() }
        try #require(await eventually(within: .seconds(3)) {
            window.contentView?.layoutSubtreeIfNeeded()
            return elements(window.contentView, matching: "Add a Name or Pattern", attribute: "accessibilityLabel").count == 2
        })
        let buttons = elements(window.contentView, matching: "Add a Name or Pattern", attribute: "accessibilityLabel")
        _ = buttons[section].perform(NSSelectorFromString("accessibilityPerformPress"))
        try #require(await eventually(within: .seconds(3)) {
            window.contentView?.layoutSubtreeIfNeeded()
            return fields(in: window.contentView).contains { $0.placeholderString == "*.tmp" }
        })
        let field = try #require(fields(in: window.contentView).first { $0.placeholderString == "*.tmp" })
        try #require(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        let pattern = "*.sample"
        editor.insertText(pattern, replacementRange: editor.selectedRange())
        #expect(editor.string == pattern)
        // Let SwiftUI finish its focus update after AppKit installs the field editor.
        try await Task.sleep(for: .milliseconds(200))
        switch finish {
        case .escape:
            try sendKey("\u{1b}", code: 53, in: window)
            window.makeFirstResponder(nil)
        case .submit:
            try sendKey("\r", code: 36, in: window, directlyTo: editor)
        case .blur:
            window.makeFirstResponder(nil)
        }
        #expect(await eventually(within: .seconds(3)) {
            window.contentView?.layoutSubtreeIfNeeded()
            return fields(in: window.contentView).allSatisfy { $0.placeholderString != "*.tmp" }
        })
        let expected: [FolderSettingChange] = finish == .escape ? [] : [section == 0 ? .ignore([pattern]) : .include([pattern])]
        #expect(folders.changes.map(\.change) == expected)
    }

    @Test func ordinaryTextSearchStillFiltersAndClears() async throws {
        let defaults = ThrowawayDefaults.make("SettingsControlTests")
        let libraries = Libraries(host: HostBench().host(), defaults: defaults, handOverPages: { $0(true) })
        let model = KeyboardPageModel(bindings: libraries.shortcuts, anyApp: libraries.anyAppShortcuts)
        let window = host(KeyboardPage(libraries: libraries, model: model))
        defer { window.contentView = nil; window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        let field = try #require(fields(in: window.contentView).compactMap { $0 as? NSSearchField }.first)
        try #require(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("zzzzzz", replacementRange: editor.selectedRange())
        try #require(await eventually(within: .seconds(3)) { model.search == "zzzzzz" && !model.hasResults })
        try clickClear(in: field)
        #expect(await eventually(within: .seconds(3)) { !model.isSearching && model.hasResults })
    }

    private func sendKey(_ characters: String, code: UInt16, in window: NSWindow, directlyTo editor: NSTextView? = nil) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        if let editor { editor.keyDown(with: event) } else { NSApp.sendEvent(event) }
    }

    private func clickClear(in field: NSSearchField) throws {
        let cell = try #require(field.cell as? NSSearchFieldCell)
        let cancel = try #require(cell.cancelButtonCell)
        cancel.performClick(field)
    }

    @Test(arguments: [false, true])
    func shortcutSearchClears(toggle: Bool) async throws {
        let defaults = ThrowawayDefaults.make("SettingsControlTests")
        let libraries = Libraries(host: HostBench().host(), defaults: defaults, handOverPages: { $0(true) })
        let model = KeyboardPageModel(bindings: libraries.shortcuts, anyApp: libraries.anyAppShortcuts)
        let window = host(KeyboardPage(libraries: libraries, model: model))
        defer { window.contentView = nil; window.close() }
        try await press(in: window, matching: "ShortcutSearchByKeys", attribute: "accessibilityIdentifier")
        try #require(await eventually(within: .seconds(3)) { model.searchesByKeys })
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45))
        try #require(await eventually(within: .seconds(3)) {
            if model.pressed == nil { NSApp.sendEvent(event) }
            return model.isSearching
        })
        if toggle {
            try await press(in: window, matching: "ShortcutSearchByKeys", attribute: "accessibilityIdentifier")
            try #require(await eventually(within: .seconds(3)) { !model.searchesByKeys })
            try await press(in: window, matching: "ShortcutSearchByKeys", attribute: "accessibilityIdentifier")
            try #require(await eventually(within: .seconds(3)) { model.searchesByKeys })
        } else {
            let field = try #require(fields(in: window.contentView).compactMap { $0 as? NSSearchField }.first)
            try clickClear(in: field)
        }
        #expect(await eventually(within: .seconds(3)) { !model.isSearching })
    }

    private func host(_ content: some View) -> NSWindow {
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, NSNumber(value: true))
        let window = BackgroundWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        return window
    }

    private final class BackgroundWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    private func press(in window: NSWindow, matching value: String, attribute: String) async throws {
        try #require(await eventually(within: .seconds(3)) {
            window.contentView?.layoutSubtreeIfNeeded()
            guard let button = elements(window.contentView, matching: value, attribute: attribute).first else { return false }
            _ = button.perform(NSSelectorFromString("accessibilityPerformPress"))
            return true
        })
    }

    private func elements(_ candidate: Any?, matching value: String, attribute: String, depth: Int = 0) -> [NSObject] {
        guard depth < 40, let candidate = candidate as? NSObject else { return [] }
        let selector = NSSelectorFromString(attribute)
        if candidate.responds(to: selector), candidate.perform(selector)?.takeUnretainedValue() as? String == value,
           candidate.responds(to: NSSelectorFromString("accessibilityPerformPress")) { return [candidate] }
        let children = NSSelectorFromString("accessibilityChildren")
        guard candidate.responds(to: children), let descendants = candidate.perform(children)?.takeUnretainedValue() as? [Any] else { return [] }
        return descendants.flatMap { elements($0, matching: value, attribute: attribute, depth: depth + 1) }
    }

    private func fields(in view: NSView?) -> [NSTextField] {
        if let field = view as? NSTextField { return [field] }
        return (view?.subviews ?? []).flatMap { fields(in: $0) }
    }
}
