import Foundation
import Observation

/// What a shortcut that works in any app does. Each brings MAPP forward and does its action in the window that was in
/// front, until a palette can be shown over another app.
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
        case .commandPalette: String(localized: "Brings MAPP forward.")
        case .searchItems: String(localized: "Searches every item.")
        case .newItem: String(localized: "A new item, in the front window.")
        }
    }
}

/// Registers and unregisters a hot key with the system. A test gives its own.
@MainActor
protocol HotKeyRegistrar {
    func register(_ shortcut: Shortcut, for command: AnyAppCommand, action: @escaping @MainActor () -> Void)
    func unregister(_ command: AnyAppCommand)
}

/// A registrar that registers nothing, for the tests, the previews and the sample library, which never take a key from the system.
struct NoHotKeys: HotKeyRegistrar {
    func register(_ shortcut: Shortcut, for command: AnyAppCommand, action: @escaping @MainActor () -> Void) {}
    func unregister(_ command: AnyAppCommand) {}
}

/// The shortcuts that work in any app, while MAPP is running. Every one is off until the person sets it, and is registered
/// with the system only while it is set: setting one registers it, clearing it unregisters it, and none is registered
/// before `start`. A shortcut needs ⌘ or ⌃ (`Shortcut.anyAppProblem`). They stay on this Mac, in the defaults.
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
        for (command, shortcut) in chosen { register(shortcut, for: command) }
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
    }

    func refusal(of shortcut: Shortcut, for command: AnyAppCommand) -> Refusal? {
        if let problem = shortcut.anyAppProblem { return .unfit(problem) }
        if let holder = holder(of: shortcut, besides: command) { return .taken(by: holder) }
        return nil
    }

    /// Sets, or with nil clears, the shortcut. A shortcut `refusal` names is not set, and the answer says why.
    @discardableResult
    func set(_ shortcut: Shortcut?, for command: AnyAppCommand) -> Refusal? {
        if let shortcut {
            if let refusal = refusal(of: shortcut, for: command) { return refusal }
            chosen[command] = shortcut
            if isStarted { register(shortcut, for: command) }
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

    /// Takes a file's shortcuts, leaving out any that is unfit or that a command before it holds, and returns how many it
    /// took and how many it left out. A command the file does not name is cleared.
    func apply(_ shortcuts: [String: Shortcut]) -> (applied: Int, skipped: Int) {
        clearAll()
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

    private func register(_ shortcut: Shortcut, for command: AnyAppCommand) {
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
