import Foundation
import Observation

/// What a shortcut that works in any app does. The palettes bring the app forward and open in the window that was in
/// front; New Item opens the new-item line over the other app, which keeps the keyboard when it closes
/// (`NewItemAnywhere`).
nonisolated enum AnyAppCommand: String, CaseIterable, Sendable {
    case commandPalette, searchItems, newItem

    var title: String {
        switch self {
        case .commandPalette: String(localized: "Show Command Palette")
        case .searchItems: String(localized: "Search Items")
        case .newItem: String(localized: "New Item")
        }
    }

    /// The line under the title.
    var line: String? {
        switch self {
        case .commandPalette: String(localized: "Over whatever you’re doing.")
        case .searchItems: nil
        case .newItem: String(localized: "One line, over any app.")
        }
    }
}

/// Registers and unregisters a hot key with the system. A test gives its own.
@MainActor
protocol HotKeyRegistrar {
    /// Whether the system took the hot key. It refuses one that another app holds.
    func register(_ shortcut: Shortcut, for command: AnyAppCommand, action: @escaping @MainActor () -> Void) -> Bool
    func unregister(_ command: AnyAppCommand)
    /// Whether the system itself uses the keys, in System Settings > Keyboard > Keyboard Shortcuts.
    func isTakenBySystem(_ shortcut: Shortcut) -> Bool
    /// Stops every registered hot key from answering while a field is waiting for a key press, and starts them again.
    func setSuspended(_ suspended: Bool)
}

/// A registrar that registers nothing, for the tests, the previews and the sample library, which never take a key from the system.
struct NoHotKeys: HotKeyRegistrar {
    func register(_ shortcut: Shortcut, for command: AnyAppCommand, action: @escaping @MainActor () -> Void) -> Bool { true }
    func unregister(_ command: AnyAppCommand) {}
    func isTakenBySystem(_ shortcut: Shortcut) -> Bool { false }
    func setSuspended(_ suspended: Bool) {}
}

/// The shortcuts that work in any app, while the app is running. Every one is off until the person sets it, and is registered
/// with the system only while it is set: setting one registers it, clearing it unregisters it, and none is registered
/// before `start`. A shortcut needs ⌘ or ⌃ (`Shortcut.anyAppProblem`). They are kept in the defaults and stay on this Mac,
/// though a settings file and a restore point carry them (`PreferencesMap.inFilesOnly`).
///
/// Stored text that cannot be read is moved aside under a key of its own, kept and never removed, and every shortcut starts
/// off.
@Observable @MainActor
final class AnyAppShortcuts {
    static let defaultsKey = "anyAppShortcuts"
    static let setAsideKey = "anyAppShortcutsSetAside"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let registrar: any HotKeyRegistrar
    /// What a pressed shortcut does, given by the app, which knows the front window.
    @ObservationIgnored var perform: (AnyAppCommand) -> Void
    private var chosen: [AnyAppCommand: Shortcut]
    @ObservationIgnored private var isStarted = false

    init(defaults: UserDefaults = .standard, registrar: any HotKeyRegistrar, perform: @escaping (AnyAppCommand) -> Void = { _ in }) {
        self.defaults = defaults
        self.registrar = registrar
        self.perform = perform
        chosen = [:]
        reload()
    }

    /// Reads the stored value again, as after an import or a restore has written the defaults (`PreferencesSync`), and
    /// once the shortcuts have started, registers each one set that is not registered, a refused one again too. A
    /// shortcut the system refuses is kept and listed in `refused`, so an import can count it as skipped.
    func reload() {
        read()
        guard isStarted else { return }
        for (command, shortcut) in registered where chosen[command] != shortcut {
            registrar.unregister(command)
            registered[command] = nil
        }
        for (command, shortcut) in chosen where registered[command] != shortcut { _ = register(shortcut, for: command) }
    }

    /// The commands whose shortcut is set but not registered, as the system refused it because another app holds the keys.
    var refused: Set<AnyAppCommand> {
        guard isStarted else { return [] }
        return Set(chosen.compactMap { command, shortcut in registered[command] == shortcut ? nil : command })
    }

    /// What the system holds for each command, as the registrar last answered.
    @ObservationIgnored private var registered: [AnyAppCommand: Shortcut] = [:]

    private func read() {
        unknown = [:]
        guard let saved = defaults.data(forKey: Self.defaultsKey) else {
            chosen = [:]
            return
        }
        if let stored = try? JSONDecoder().decode([String: Shortcut].self, from: saved) {
            // A command a later version of the app added is ignored here and kept in the stored text, which `save` rewrites whole.
            chosen = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in AnyAppCommand(rawValue: key).map { ($0, value) } })
            unknown = stored.filter { AnyAppCommand(rawValue: $0.key) == nil }
        } else {
            chosen = [:]
            defaults.set((defaults.array(forKey: Self.setAsideKey) as? [Data] ?? []) + [saved], forKey: Self.setAsideKey)
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    @ObservationIgnored private var unknown: [String: Shortcut] = [:]

    /// Registers every shortcut that is set. Called once, as the app launches.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        for (command, shortcut) in chosen { _ = register(shortcut, for: command) }
    }

    func shortcut(for command: AnyAppCommand) -> Shortcut? { chosen[command] }

    /// The command that already has `shortcut`, besides `command`.
    func holder(of shortcut: Shortcut, besides command: AnyAppCommand) -> AnyAppCommand? {
        AnyAppCommand.allCases.first { $0 != command && chosen[$0] == shortcut }
    }

    /// What is wrong with giving `command` `shortcut`, or nil. A shortcut another of these holds is a problem of its own,
    /// since the system keeps one app of its hot key.
    enum Refusal: Equatable {
        case unfit(Shortcut.Problem)
        case taken(by: AnyAppCommand)
        /// The system's own command has the keys, which no shortcut of the app's can take.
        case system(String)
        /// The system refused the hot key when it was registered, since another app holds it.
        case unavailable
    }

    func refusal(of shortcut: Shortcut, for command: AnyAppCommand) -> Refusal? {
        if let problem = shortcut.anyAppProblem { return .unfit(problem) }
        if let holder = holder(of: shortcut, besides: command) { return .taken(by: holder) }
        if let owner = SystemShortcuts.owner(of: shortcut) { return .system(owner) }
        if registrar.isTakenBySystem(shortcut) { return .system(String(localized: "macOS")) }
        return nil
    }

    /// Sets, or with nil clears, the shortcut. A shortcut `refusal` names, or that the system will not register because
    /// another app holds it, is not set and not kept, and the answer says why. The command keeps what it had.
    @discardableResult
    func set(_ shortcut: Shortcut?, for command: AnyAppCommand) -> Refusal? {
        if let shortcut {
            if let refusal = refusal(of: shortcut, for: command) { return refusal }
            if registered[command] == shortcut, isStarted { return nil }
            if isStarted, !register(shortcut, for: command) { return .unavailable }
            chosen[command] = shortcut
        } else {
            chosen.removeValue(forKey: command)
            if isStarted { registrar.unregister(command) }
            registered[command] = nil
        }
        save()
        return nil
    }

    /// Clears every shortcut, which unregisters them all.
    func clearAll() {
        for command in registered.keys { registrar.unregister(command) }
        registered = [:]
        chosen = [:]
        save()
    }

    /// The shortcuts as they are, for Export.
    var current: [String: Shortcut] { Dictionary(uniqueKeysWithValues: chosen.map { ($0.key.rawValue, $0.value) }) }

    /// Takes a file's shortcuts, leaving out any that is unfit, that another command or the system holds, or that the
    /// system will not register, and returns how many it took and how many it left out. A command the file does not name
    /// keeps its shortcut.
    func apply(_ shortcuts: [String: Shortcut]) -> (applied: Int, skipped: Int) {
        var applied = 0
        var skipped = 0
        for (key, shortcut) in shortcuts.sorted(by: { $0.key < $1.key }) {
            guard let command = AnyAppCommand(rawValue: key), set(shortcut, for: command) == nil else {
                skipped += 1
                continue
            }
            applied += 1
        }
        return (applied, skipped)
    }

    /// Stops the hot keys from answering while a field waits for a key press, so a key such as ⌃⌘K reaches the field and
    /// does not run its command. Called with false when the wait ends, however it ends.
    func setSuspended(_ suspended: Bool) { registrar.setSuspended(suspended) }

    /// A refusal leaves the command with what the system held before.
    private func register(_ shortcut: Shortcut, for command: AnyAppCommand) -> Bool {
        guard registrar.register(shortcut, for: command, action: { [weak self] in self?.perform(command) }) else { return false }
        registered[command] = shortcut
        return true
    }

    private func save() {
        let all = unknown.merging(current) { _, new in new }
        if all.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
