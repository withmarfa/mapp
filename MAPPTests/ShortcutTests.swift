import AppKit
import Foundation
import Testing
@testable import MAPP

/// A registrar that records what the system would hold.
@MainActor
final class FakeHotKeys: HotKeyRegistrar {
    private(set) var registered: [AnyAppCommand: Shortcut] = [:]
    private(set) var calls: [String] = []

    func register(_ shortcut: Shortcut, for command: AnyAppCommand, action: @escaping @MainActor () -> Void) {
        registered[command] = shortcut
        calls.append("register \(command.rawValue)")
    }

    func unregister(_ command: AnyAppCommand) {
        registered.removeValue(forKey: command)
        calls.append("unregister \(command.rawValue)")
    }
}

@MainActor
struct ShortcutTests {
    private func defaults() -> UserDefaults {
        let suite = "ShortcutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
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

    @Test func shortcutsAreWrittenWithTheirModifiersInTheSystemsOrder() {
        #expect(key("n").display == "⌘N")
        #expect(key("n", [.command, .option]).display == "⌥⌘N")
        #expect(key("p", [.shift, .command]).display == "⇧⌘P")
        #expect(key("\u{7F}").display == "⌘⌫")
        #expect(key(" ", [.control, .option]).display == "⌃⌥Space")
        #expect(key(String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!), [.command, .option]).display == "⌥⌘←")
    }

    @Test func aKeyPressBecomesAShortcutWithItsKeyCode() throws {
        func press(_ characters: String, _ modifiers: NSEvent.ModifierFlags, code: UInt16) throws -> Shortcut {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            return try #require(Shortcut(event: event))
        }
        let palette = try press("k", .command, code: 40)
        #expect(palette == key("k"))
        #expect(palette.keyCode == 40)
        #expect(try press("P", [.command, .shift], code: 35) == key("p", [.command, .shift]))
    }

    @Test func theCataloguesDefaultsNeverGiveTwoCommandsOneKeyOrTakeTheSystemsOwn() {
        let commands = ShortcutCommand.all
        #expect(Set(commands.map(\.id)).count == commands.count)
        let defaults = commands.compactMap(\.defaultShortcut)
        #expect(Set(defaults).count == defaults.count)
        #expect(defaults.allSatisfy { SystemShortcuts.owner(of: $0) == nil })
        #expect(defaults.allSatisfy { $0.menuProblem == nil })
    }

    @Test func everyCommandTheMenusBindIsInTheCatalogue() {
        let ids = Set(ShortcutCommand.all.map(\.id))
        for command in ItemCommand.allCases { #expect(ids.contains(command.shortcutCommand.id)) }
        for command in FileViewCommand.allCases { #expect(ids.contains(command.shortcutCommand.id)) }
        for format in Format.allCases { #expect(ids.contains(ShortcutCommand.format(format).id)) }
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
        first.set(key("n", [.command, .option], code: 45), for: .newItem)
        let hotKeys = FakeHotKeys()
        let second = AnyAppShortcuts(defaults: store, registrar: hotKeys)
        #expect(hotKeys.registered.isEmpty)
        second.start()
        #expect(hotKeys.registered.keys.sorted { $0.rawValue < $1.rawValue } == [.newItem])
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
        #expect(throws: ShortcutsFile.ReadError.notOurs) { try ShortcutsFile.read(Data("{\"format\":\"mapp-looks\",\"version\":1}".utf8)) }
        #expect(throws: ShortcutsFile.ReadError.notOurs) { try ShortcutsFile.read(Data("[1,2]".utf8)) }
        #expect(throws: ShortcutsFile.ReadError.notOurs) { try ShortcutsFile.read(Data("{\"format\":\"mapp-shortcuts\",\"version\":1}".utf8)) }
    }

    @Test func aFileFromANewerVersionIsRefused() {
        let newer = "{\"format\":\"mapp-shortcuts\",\"version\":\(ShortcutsFile.version + 1),\"shortcuts\":{}}"
        #expect(throws: ShortcutsFile.ReadError.newerVersion) { try ShortcutsFile.read(Data(newer.utf8)) }
    }

    @Test func aShortcutNamingACommandMAPPNoLongerHasIsSkippedAndCounted() {
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

    // MARK: Search

    @Test func aSearchByNameLeavesTheCommandsWhoseTitleHasTheWords() {
        let (model, _, _) = page(defaults())
        model.search = "tag"
        #expect(model.sections.flatMap(\.commands).map(\.id).contains("addTag"))
        #expect(!model.sections.flatMap(\.commands).map(\.id).contains("newItem"))
        model.search = "zzzz"
        #expect(!model.hasResults)
    }

    @Test func aSearchByKeysFindsTheCommandThatHasThem() {
        let (model, _, _) = page(defaults())
        model.searchesByKeys = true
        model.pressed = key("k")
        #expect(model.sections.flatMap(\.commands).map(\.id) == ["commandPalette"])
        #expect(model.line(forCount: 1) == "One command uses ⌘K.")
        model.search = "tag"
        #expect(model.sections.count == 1)
    }
}

@MainActor
struct FormatKeymapTests {
    @Test func theItemPageAnswersTheShortcutThePersonChoseForAFormat() {
        let chosen = Shortcut(key: "b", modifiers: [.command, .option])
        #expect(Format.bold.pageKey(for: chosen) == "Alt-Mod-b")
        #expect(Format.bold.pageKey(for: ShortcutCommand.format(.bold).defaultShortcut) == "Mod-b")
        #expect(Format.title.pageKey(for: ShortcutCommand.format(.title).defaultShortcut) == "Shift-Mod-t")
    }

    @Test func aClearedShortcutOrOneThePageHasNoNameForIsLeftToTheMenu() {
        #expect(Format.bold.pageKey(for: nil) == nil)
        #expect(Format.link.pageKey(for: Shortcut(key: "k", modifiers: .command)) == nil)
        #expect(Format.bold.pageKey(for: Shortcut(key: String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!), modifiers: .command)) == nil)
    }
}
