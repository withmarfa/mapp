import Foundation
import Observation

/// What a shortcut that works in any app does. Each brings MAPP forward and does its action in the window that was in
/// front, until a palette can be shown over another app.
nonisolated enum AnyAppCommand: String, CaseIterable, Sendable {
    case commandPalette, searchItems, quickAdd

    var title: String {
        switch self {
        case .commandPalette: String(localized: "Show Command Palette")
        case .searchItems: String(localized: "Search Items")
        case .quickAdd: String(localized: "Quick Add")
        }
    }

    /// The line under the title.
    var line: String? {
        switch self {
        case .commandPalette: String(localized: "Brings MAPP forward with the palette open.")
        case .searchItems: nil
        case .quickAdd: String(localized: "Brings MAPP forward to add an item.")
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

/// The shortcuts that work in any app, while MAPP is running. Every one is off until the person sets it, and is registered
/// with the system only while it is set: setting one registers it, clearing it unregisters it, and none is registered
/// before `start`. A shortcut needs ⌘ or ⌃ (`Shortcut.anyAppProblem`). They are kept in the defaults and sync through the connected Marfa (`PreferencesMap`).
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

    /// Reads the stored value again, as when another Mac's change has reached the defaults (`PreferencesSync`), and
    /// registers what changed once the shortcuts have started.
    func reload() {
        let before = chosen
        read()
        guard isStarted else { return }
        for (command, shortcut) in before where chosen[command] != shortcut { registrar.unregister(command) }
        for (command, shortcut) in chosen where before[command] != shortcut { _ = register(shortcut, for: command) }
    }

    private func read() {
        unknown = [:]
        guard let saved = defaults.data(forKey: Self.defaultsKey) else {
            chosen = [:]
            return
        }
        if let stored = try? JSONDecoder().decode([String: Shortcut].self, from: saved) {
            // A command a later MAPP added is ignored here and kept in the stored text, which `save` rewrites whole.
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
        /// The system's own command has the keys, which no shortcut of MAPP's can take.
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
            if chosen[command] == shortcut, isStarted { return nil }
            if isStarted, !register(shortcut, for: command) { return .unavailable }
            chosen[command] = shortcut
        } else {
            chosen.removeValue(forKey: command)
            if isStarted { registrar.unregister(command) }
        }
        save()
        return nil
    }

    /// Clears every shortcut, which unregisters them all.
    func clearAll() {
        for command in chosen.keys where isStarted { registrar.unregister(command) }
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

    private func register(_ shortcut: Shortcut, for command: AnyAppCommand) -> Bool {
        registrar.register(shortcut, for: command) { [weak self] in self?.perform(command) }
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
