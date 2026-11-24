import AppKit
import Foundation
import Testing
@testable import MarfaMac

/// A registrar that records what the system would hold.
@MainActor
final class FakeHotKeys: HotKeyRegistrar {
    private(set) var registered: [AnyAppCommand: Shortcut] = [:]
    private(set) var calls: [String] = []
    /// Keys another app holds, which the system refuses to register.
    var heldByAnotherApp: Set<Shortcut> = []
    /// Keys the system's own shortcuts use.
    var systemKeys: Set<Shortcut> = []
    private(set) var isSuspended = false

    func register(_ shortcut: Shortcut, for command: AnyAppCommand, action: @escaping @MainActor () -> Void) -> Bool {
        guard !heldByAnotherApp.contains(shortcut) else { return false }
        registered[command] = shortcut
        calls.append("register \(command.rawValue)")
        return true
    }

    func isTakenBySystem(_ shortcut: Shortcut) -> Bool { systemKeys.contains(shortcut) }

    func setSuspended(_ suspended: Bool) { isSuspended = suspended }

    func unregister(_ command: AnyAppCommand) {
        registered.removeValue(forKey: command)
        calls.append("unregister \(command.rawValue)")
    }
}

@MainActor
struct ShortcutTests {
    private func defaults() -> UserDefaults {
        let defaults = ThrowawayDefaults.make("ShortcutTests")
        return defaults
    }

    private func key(_ key: String, _ modifiers: ShortcutModifiers = .command, code: Int? = nil) -> Shortcut {
        Shortcut(key: key, modifiers: modifiers, keyCode: code)
    }

    private func page(_ defaults: UserDefaults, hotKeys: FakeHotKeys = FakeHotKeys()) -> (KeyboardPageModel, ShortcutBindings, AnyAppShortcuts) {
        let bindings = ShortcutBindings(defaults: defaults)
        let anyApp = AnyAppShortcuts(defaults: defaults, registrar: hotKeys)
        anyApp.start()
        return (KeyboardPageModel(bindings: bindings, anyApp: anyApp), bindings, anyApp)
    }

    // MARK: Writing and recording

    @Test func theCataloguesDefaultsNeverGiveTwoCommandsOneKeyOrTakeTheSystemsOwn() {
        let commands = ShortcutCommand.all
        #expect(Set(commands.map(\.id)).count == commands.count)
        let defaults = commands.compactMap(\.defaultShortcut)
        #expect(Set(defaults).count == defaults.count)
        #expect(defaults.allSatisfy { SystemShortcuts.owner(of: $0) == nil })
        #expect(defaults.allSatisfy { $0.menuProblem == nil })
    }

    // MARK: Menu commands

    @Test func aChosenShortcutDrivesTheCommandAndSurvivesARelaunch() {
        let store = defaults()
        let bindings = ShortcutBindings(defaults: store)
        #expect(bindings.shortcut(for: .newItem) == key("n"))
        bindings.set(key("n", [.command, .control]), for: .newItem)
        #expect(bindings.shortcut(for: .newItem)?.display == "⌃⌘N")
        #expect(bindings.shortcut(for: .newItem)?.keyboardShortcut != nil)
        #expect(ShortcutBindings(defaults: store).shortcut(for: .newItem)?.display == "⌃⌘N")
    }

    @Test func aClearedShortcutStaysClearedAndTheDefaultComesBackOnRestore() {
        let store = defaults()
        let bindings = ShortcutBindings(defaults: store)
        bindings.set(nil, for: .refresh)
        #expect(ShortcutBindings(defaults: store).shortcut(for: .refresh) == nil)
        #expect(bindings.hasChoices)
        bindings.restoreDefaults()
        #expect(bindings.shortcut(for: .refresh) == key("r"))
        #expect(!bindings.hasChoices)
        #expect(store.data(forKey: ShortcutBindings.defaultsKey) == nil)
    }

    @Test func aShortcutAnotherCommandHoldsIsShownAsTakenAndCancelLeavesBothAlone() {
        let (model, bindings, _) = page(defaults())
        model.startRecording(.menu(.addTag))
        model.record(key("k"))
        #expect(model.refusal?.reason == .taken(by: ShortcutCommand.commandPalette.title, canReplace: true))
        #expect(model.error(for: .menu(.addTag)) == "⌘K is \(ShortcutCommand.commandPalette.title)’s.")
        #expect(model.keys(for: .menu(.addTag)) == "⌘K")
        model.cancelRefusal()
        #expect(bindings.shortcut(for: .addTag) == nil)
        #expect(bindings.shortcut(for: .commandPalette) == key("k"))
        #expect(model.error(for: .menu(.addTag)) == nil)
    }

    @Test func replacingATakenShortcutMovesItAndLeavesTheOldHolderWithNone() {
        let store = defaults()
        let (model, bindings, _) = page(store)
        model.startRecording(.menu(.addTag))
        model.record(key("k"))
        model.replace()
        #expect(bindings.shortcut(for: .addTag) == key("k"))
        #expect(bindings.shortcut(for: .commandPalette) == nil)
        #expect(ShortcutBindings(defaults: store).shortcut(for: .commandPalette) == nil)
        #expect(model.refusal == nil)
    }

    @Test func aShortcutTheSystemOwnsIsRefusedAndCannotBeReplaced() {
        let (model, bindings, _) = page(defaults())
        model.startRecording(.menu(.addTag))
        model.record(key("c"))
        #expect(model.refusal?.canReplace == false)
        model.replace()
        #expect(bindings.shortcut(for: .addTag) == nil)
    }

    @Test func aMenuShortcutNeedsCommandControlOrOption() {
        let (model, bindings, _) = page(defaults())
        model.startRecording(.menu(.addTag))
        model.record(key("t", [.shift]))
        #expect(model.refusal?.reason == .needsModifier)
        #expect(bindings.shortcut(for: .addTag) == nil)
    }

    @Test func aStoredShortcutForACommandThatIsGoneIsIgnoredAndKept() throws {
        let store = defaults()
        let stored = ShortcutBindings.Stored(shortcuts: ["gone": key("g"), "newItem": nil])
        store.set(try JSONEncoder().encode(stored), forKey: ShortcutBindings.defaultsKey)
        let bindings = ShortcutBindings(defaults: store)
        #expect(bindings.shortcut(for: .newItem) == nil)
        #expect(bindings.commands.allSatisfy { $0.id != "gone" })
        bindings.set(key("m", [.command, .option]), for: .refresh)
        let saved = try JSONDecoder().decode(ShortcutBindings.Stored.self, from: #require(store.data(forKey: ShortcutBindings.defaultsKey)))
        #expect(saved.shortcuts["gone"] == key("g"))
        bindings.restoreDefaults()
        let after = try JSONDecoder().decode(ShortcutBindings.Stored.self, from: #require(store.data(forKey: ShortcutBindings.defaultsKey)))
        #expect(after.shortcuts.keys.sorted() == ["gone"])
    }

    @Test func unreadableStoredTextIsSetAsideAndTheDefaultsStand() {
        let store = defaults()
        let garbage = Data("{\"shortcuts\": 3}".utf8)
        store.set(garbage, forKey: ShortcutBindings.defaultsKey)
        let bindings = ShortcutBindings(defaults: store)
        #expect(bindings.shortcut(for: .newItem) == key("n"))
        #expect(store.array(forKey: ShortcutBindings.setAsideKey) as? [Data] == [garbage])
    }

    // MARK: Any app

    @Test func aShortcutForAnyAppNeedsCommandOrControlAndOptionAloneIsRefused() {
        let hotKeys = FakeHotKeys()
        let (model, _, anyApp) = page(defaults(), hotKeys: hotKeys)
        model.startRecording(.anyApp(.commandPalette))
        model.record(key(" ", .option, code: 49))
        #expect(model.refusal?.reason == .needsCommandOrControl)
        #expect(model.error(for: .anyApp(.commandPalette)) == "Include ⌘ or ⌃.")
        #expect(anyApp.shortcut(for: .commandPalette) == nil)
        #expect(hotKeys.registered.isEmpty)
        model.startRecording(.anyApp(.commandPalette))
        model.record(key(" ", [.control, .option], code: 49))
        #expect(anyApp.shortcut(for: .commandPalette)?.display == "⌃⌥Space")
    }

    @Test func anyAppShortcutsAreRegisteredOnlyWhileTheyAreSet() {
        let store = defaults()
        let hotKeys = FakeHotKeys()
        let anyApp = AnyAppShortcuts(defaults: store, registrar: hotKeys)
        anyApp.start()
        #expect(hotKeys.registered.isEmpty)
        #expect(anyApp.set(key(" ", [.control, .option], code: 49), for: .commandPalette) == nil)
        #expect(hotKeys.registered[.commandPalette]?.keyCode == 49)
        anyApp.set(nil, for: .commandPalette)
        #expect(hotKeys.registered.isEmpty)
        #expect(hotKeys.calls == ["register commandPalette", "unregister commandPalette"])
    }

    @Test func nothingIsRegisteredBeforeStartAndOnlyWhatWasSetAfterIt() {
        let store = defaults()
        let first = AnyAppShortcuts(defaults: store, registrar: FakeHotKeys())
        first.start()
        first.set(key("n", [.command, .option], code: 45), for: .quickAdd)
        let hotKeys = FakeHotKeys()
        let second = AnyAppShortcuts(defaults: store, registrar: hotKeys)
        #expect(hotKeys.registered.isEmpty)
        second.start()
        #expect(hotKeys.registered.keys.sorted { $0.rawValue < $1.rawValue } == [.quickAdd])
    }

    @Test func twoAnyAppCommandsNeverShareKeys() {
        let (model, _, anyApp) = page(defaults())
        anyApp.set(key("k", [.command, .control], code: 40), for: .commandPalette)
        model.startRecording(.anyApp(.searchItems))
        model.record(key("k", [.command, .control], code: 40))
        #expect(model.refusal?.reason == .taken(by: AnyAppCommand.commandPalette.title, canReplace: true))
        model.replace()
        #expect(anyApp.shortcut(for: .searchItems) != nil)
        #expect(anyApp.shortcut(for: .commandPalette) == nil)
    }

    @Test func restoreDefaultsTurnsAnyAppShortcutsOffAndUnregistersThem() {
        let hotKeys = FakeHotKeys()
        let (model, bindings, anyApp) = page(defaults(), hotKeys: hotKeys)
        anyApp.set(key("k", [.command, .control], code: 40), for: .commandPalette)
        bindings.set(nil, for: .newItem)
        model.restoreDefaults()
        #expect(hotKeys.registered.isEmpty)
        #expect(bindings.shortcut(for: .newItem) == key("n"))
    }

    @Test func anAnyAppShortcutNeverTakesAKeyTheSystemOrAMenuOwns() {
        let hotKeys = FakeHotKeys()
        let ours = Shortcut(key: "k", modifiers: [.command, .control], keyCode: 40)
        hotKeys.systemKeys = [ours]
        let (model, _, anyApp) = page(defaults(), hotKeys: hotKeys)
        model.startRecording(.anyApp(.commandPalette))
        model.record(key("c", .command, code: 8))
        #expect(model.refusal?.reason == .taken(by: "Copy", canReplace: false))
        #expect(model.error(for: .anyApp(.commandPalette)) == "⌘C is Copy’s.")
        model.startRecording(.anyApp(.commandPalette))
        model.record(ours)
        #expect(model.refusal?.reason == .taken(by: "macOS", canReplace: false))
        model.replace()
        #expect(anyApp.shortcut(for: .commandPalette) == nil)
        #expect(hotKeys.registered.isEmpty)
    }

    @Test func aHotKeyAnotherAppHoldsShowsOneLineAndKeepsNothingNew() {
        let hotKeys = FakeHotKeys()
        let held = key("j", [.command, .control], code: 38)
        hotKeys.heldByAnotherApp = [held]
        let (model, _, anyApp) = page(defaults(), hotKeys: hotKeys)
        anyApp.set(key("n", [.command, .control], code: 45), for: .commandPalette)
        model.startRecording(.anyApp(.commandPalette))
        model.record(held)
        #expect(model.refusal?.reason == .unavailable)
        #expect(model.error(for: .anyApp(.commandPalette)) == "Another app already uses ⌃⌘J.")
        #expect(anyApp.shortcut(for: .commandPalette) == key("n", [.command, .control]))
        #expect(hotKeys.registered[.commandPalette] == key("n", [.command, .control]))
        model.startRecording(.anyApp(.searchItems))
        model.record(held)
        #expect(anyApp.shortcut(for: .searchItems) == nil)
    }

    @Test func nothingIsStoredForAHotKeyTheSystemRefused() {
        let store = defaults()
        let hotKeys = FakeHotKeys()
        let held = key("j", [.command, .control], code: 38)
        hotKeys.heldByAnotherApp = [held]
        let anyApp = AnyAppShortcuts(defaults: store, registrar: hotKeys)
        anyApp.start()
        #expect(anyApp.set(held, for: .quickAdd) == .unavailable)
        #expect(store.data(forKey: AnyAppShortcuts.defaultsKey) == nil)
    }

    // MARK: Recording

    @Test func hotKeysStopAnsweringWhileAFieldRecordsAndWhileSearchingByKeys() {
        let hotKeys = FakeHotKeys()
        let (model, _, _) = page(defaults(), hotKeys: hotKeys)
        #expect(!hotKeys.isSuspended)
        model.startRecording(.menu(.addTag))
        #expect(hotKeys.isSuspended)
        model.stopRecording()
        #expect(!hotKeys.isSuspended)
        model.startRecording(.menu(.addTag))
        model.record(key("y", [.command, .option]))
        #expect(!hotKeys.isSuspended)
        model.searchesByKeys = true
        #expect(hotKeys.isSuspended)
        model.searchesByKeys = false
        #expect(!hotKeys.isSuspended)
    }

    @Test func leavingThePageStopsRecordingAndSearchingByKeysAndWakesTheHotKeys() {
        let hotKeys = FakeHotKeys()
        let (model, _, _) = page(defaults(), hotKeys: hotKeys)
        model.startRecording(.anyApp(.quickAdd))
        model.pageDidDisappear()
        #expect(model.recording == nil)
        #expect(!hotKeys.isSuspended)
        model.searchesByKeys = true
        model.pageDidDisappear()
        #expect(!model.searchesByKeys)
        #expect(!hotKeys.isSuspended)
    }

    @Test func recordingTurnsSearchByKeysOffSoOnlyOneMonitorRuns() {
        let (model, _, _) = page(defaults())
        model.searchesByKeys = true
        model.startRecording(.menu(.addTag))
        #expect(!model.searchesByKeys)
        #expect(model.recording == .menu(.addTag))
        model.searchesByKeys = true
        #expect(model.recording == nil)
    }

    // MARK: System keys

    @Test func theSystemsOwnMenuKeysAreReserved() {
        let reserved: [(String, ShortcutModifiers, String)] = [
            ("f", [.control, .command], "Enter Full Screen"), ("w", [.option, .command], "Close All"),
            (" ", [.control, .command], "Emoji & Symbols"), ("/", [.shift, .command], "Help"),
            ("m", [.option, .command], "Minimize All"), ("v", [.option, .shift, .command], "Paste and Match Style"),
            ("\\", [.shift, .command], "Show All Tabs")
        ]
        for (letter, modifiers, _) in reserved { #expect(SystemShortcuts.owner(of: key(letter, modifiers)) != nil, "\(letter)") }
    }

    // MARK: Files

    @Test func exportedShortcutsReadBackAndApply() throws {
        let source = ShortcutBindings(defaults: defaults())
        source.set(key("j", [.command, .option]), for: .refresh)
        source.set(nil, for: .newWindow)
        let file = ShortcutsFile(shortcuts: source.current, anyApp: ["newItem": key("n", [.command, .control], code: 45)])
        let read = try ShortcutsFile.read(file.encoded())
        let target = ShortcutBindings(defaults: defaults())
        let result = target.apply(read.shortcuts)
        #expect(result.skipped == 0)
        #expect(target.shortcut(for: .refresh) == key("j", [.command, .option]))
        #expect(target.shortcut(for: .newWindow) == nil)
        #expect(read.anyApp?["newItem"]?.keyCode == 45)
    }

    @Test func aFileThatIsNotOursIsRefused() throws {
        #expect(throws: ShortcutsFile.ReadError.notOurs) { try ShortcutsFile.read(Data("not json".utf8)) }
        #expect(throws: ShortcutsFile.ReadError.notOurs) { try ShortcutsFile.read(Data("{\"format\":\"marfa-mac-looks\",\"version\":1}".utf8)) }
        #expect(throws: ShortcutsFile.ReadError.notOurs) { try ShortcutsFile.read(Data("[1,2]".utf8)) }
        #expect(throws: ShortcutsFile.ReadError.notOurs) { try ShortcutsFile.read(Data("{\"format\":\"marfa-mac-shortcuts\",\"version\":1}".utf8)) }
    }

    @Test func aFileFromANewerVersionIsRefused() {
        let newer = "{\"format\":\"marfa-mac-shortcuts\",\"version\":\(ShortcutsFile.version + 1),\"shortcuts\":{}}"
        #expect(throws: ShortcutsFile.ReadError.newerVersion) { try ShortcutsFile.read(Data(newer.utf8)) }
    }

    @Test func aShortcutNamingACommandTheAppNoLongerHasIsSkippedAndCounted() {
        let bindings = ShortcutBindings(defaults: defaults())
        let result = bindings.apply(["removedCommand": key("x"), "refresh": key("j", [.command, .option])])
        #expect(result.skipped == 1)
        #expect(result.applied == 1)
        #expect(bindings.shortcut(for: .refresh) == key("j", [.command, .option]))
    }

    @Test func aFileNeverGivesTwoCommandsOneKey() {
        let bindings = ShortcutBindings(defaults: defaults())
        let result = bindings.apply(["addTag": key("k"), "changeType": key("y", [.command, .option])])
        // ⌘K is Command Palette's by default, which the file leaves alone.
        #expect(result.skipped == 1)
        #expect(bindings.shortcut(for: .addTag) == nil)
        #expect(bindings.shortcut(for: .changeType) == key("y", [.command, .option]))
        #expect(bindings.shortcut(for: .commandPalette) == key("k"))
    }

    @Test func importingAnEmptyFileChangesNothingInEitherHalf() {
        let store = defaults()
        let hotKeys = FakeHotKeys()
        let (_, bindings, anyApp) = page(store, hotKeys: hotKeys)
        bindings.set(key("j", [.command, .option]), for: .refresh)
        bindings.set(nil, for: .newItem)
        anyApp.set(key("k", [.command, .control], code: 40), for: .commandPalette)
        let result = bindings.apply([:])
        let anyAppResult = anyApp.apply([:])
        #expect(result == ShortcutBindings.Applied())
        #expect(anyAppResult.applied == 0 && anyAppResult.skipped == 0)
        #expect(bindings.shortcut(for: .refresh) == key("j", [.command, .option]))
        #expect(bindings.shortcut(for: .newItem) == nil)
        #expect(anyApp.shortcut(for: .commandPalette) == key("k", [.command, .control]))
        #expect(hotKeys.registered[.commandPalette] != nil)
    }

    @Test func aFileNamingOneCommandChangesOnlyThatOne() {
        let (_, bindings, anyApp) = page(defaults())
        bindings.set(key("j", [.command, .option]), for: .refresh)
        anyApp.set(key("k", [.command, .control], code: 40), for: .commandPalette)
        let result = bindings.apply(["newWindow": key("y", [.command, .option])])
        #expect(result.applied == 1 && result.skipped == 0)
        #expect(bindings.shortcut(for: .newWindow) == key("y", [.command, .option]))
        #expect(bindings.shortcut(for: .refresh) == key("j", [.command, .option]))
        let anyAppResult = anyApp.apply(["quickAdd": key("n", [.command, .control], code: 45)])
        #expect(anyAppResult.applied == 1 && anyAppResult.skipped == 0)
        #expect(anyApp.shortcut(for: .quickAdd) != nil)
        #expect(anyApp.shortcut(for: .commandPalette) == key("k", [.command, .control]))
    }

    @Test func aFileNeverTakesAKeyACommandItDoesNotNameHasChosen() {
        let (_, bindings, _) = page(defaults())
        bindings.set(key("j", [.command, .option]), for: .refresh)
        let result = bindings.apply(["addTag": key("j", [.command, .option])])
        #expect(result.skipped == 1)
        #expect(bindings.shortcut(for: .refresh) == key("j", [.command, .option]))
        #expect(bindings.shortcut(for: .addTag) == nil)
    }

    @Test func anAnyAppShortcutTheFileNamesThatTheSystemRefusesIsSkippedAndCounted() {
        let hotKeys = FakeHotKeys()
        hotKeys.heldByAnotherApp = [key("j", [.command, .control])]
        let (_, _, anyApp) = page(defaults(), hotKeys: hotKeys)
        let result = anyApp.apply([
            "newItem": key("j", [.command, .control], code: 38), "searchItems": key("s", [.command, .control], code: 1),
            "gone": key("g", [.command, .control], code: 5),
        ])
        #expect(result.applied == 1 && result.skipped == 2)
        #expect(anyApp.shortcut(for: .quickAdd) == nil)
    }

}

@MainActor
struct FormatKeymapTests {
    @Test func aClearedShortcutOrOneThePageHasNoNameForIsLeftToTheMenu() {
        #expect(Format.bold.pageKey(for: nil) == nil)
        #expect(Format.link.pageKey(for: Shortcut(key: "k", modifiers: .command)) == nil)
        #expect(Format.bold.pageKey(for: Shortcut(key: String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!), modifiers: .command)) == nil)
    }
}
