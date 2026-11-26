import AppKit
import SwiftUI
import Testing
@testable import MarfaMac

@MainActor @Suite(.serialized, .hangLimit)
struct SettingsControlTests {
    @Test(arguments: [0, 1])
    func escapeCancelsFolderPattern(section: Int) async throws {
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
        editor.insertText("cancel-this", replacementRange: editor.selectedRange())
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        #expect(await eventually(within: .seconds(2)) {
            window.contentView?.layoutSubtreeIfNeeded()
            return fields(in: window.contentView).allSatisfy { $0.placeholderString != "*.tmp" }
        })
        window.makeFirstResponder(nil)
        #expect(folders.changes.isEmpty)
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
            let cell = try #require(field.cell as? NSSearchFieldCell)
            let cancel = try #require(cell.cancelButtonCell)
            let action = try #require(cancel.action)
            try #require(NSApp.sendAction(action, to: cancel.target, from: cancel))
        }
        #expect(await eventually(within: .seconds(3)) { !model.isSearching })
    }

    private func host(_ content: some View) -> NSWindow {
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, NSNumber(value: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        return window
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
