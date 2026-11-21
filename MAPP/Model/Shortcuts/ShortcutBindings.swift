import Foundation
import Observation

/// The shortcut each menu command has: the one the person chose, or its default. Only what was chosen is stored, so a
/// better default reaches every command nobody changed; a command the person cleared is stored as cleared. Shortcuts stay on
/// this Mac and are never written to Marfa.
///
/// A stored command that MAPP no longer has is ignored and kept, in case it returns. Stored text that cannot be read is
/// moved aside under a key of its own, kept and never removed, and the commands start from their defaults.
@Observable @MainActor
final class ShortcutBindings {
    static let defaultsKey = "keyboardShortcuts"
    static let setAsideKey = "keyboardShortcutsSetAside"

    /// What the stored text holds. `shortcuts` maps a command's identifier to its chosen shortcut, or to nothing for a
    /// command whose shortcut was cleared. A new field is optional, so text saved before it existed still reads.
    struct Stored: Codable, Equatable {
        var shortcuts: [String: Shortcut?]
    }

    /// Who holds a shortcut a person tried to give a command.
    enum Holder: Equatable {
        case command(ShortcutCommand)
        /// One of the system's own commands, which a command of MAPP's cannot take.
        case system(String)

        var name: String {
            switch self {
            case .command(let command): command.title
            case .system(let title): title
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let commands: [ShortcutCommand]
    private var chosen: [String: Shortcut?]

    init(defaults: UserDefaults = .standard, commands: [ShortcutCommand] = ShortcutCommand.all) {
        self.defaults = defaults
        self.commands = commands
        guard let saved = defaults.data(forKey: Self.defaultsKey) else {
            chosen = [:]
            return
        }
        if let stored = try? JSONDecoder().decode(Stored.self, from: saved) {
            chosen = stored.shortcuts
        } else {
            chosen = [:]
            defaults.set((defaults.array(forKey: Self.setAsideKey) as? [Data] ?? []) + [saved], forKey: Self.setAsideKey)
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    // MARK: Reading

    /// The shortcut `command` has now: the person's choice, which may be none, or the default.
    func shortcut(for command: ShortcutCommand) -> Shortcut? {
        if let choice = chosen[command.id] { return choice }
        return command.defaultShortcut
    }

    func display(for command: ShortcutCommand) -> String? { shortcut(for: command)?.display }

    /// Whether the person set the command's shortcut, which differs from its default.
    func isChosen(_ command: ShortcutCommand) -> Bool { chosen[command.id] != nil }

    /// Whether any command's shortcut differs from its default, which Restore Defaults would undo.
    var hasChoices: Bool { commands.contains { isChosen($0) } }

    /// Who holds `shortcut` besides `command`, or nil if it is free.
    func holder(of shortcut: Shortcut, besides command: ShortcutCommand) -> Holder? {
        if let other = commands.first(where: { $0.id != command.id && self.shortcut(for: $0) == shortcut }) { return .command(other) }
        return SystemShortcuts.owner(of: shortcut).map(Holder.system)
    }

    // MARK: Changing

    /// Gives `command` the shortcut, or none, and keeps it. The caller has asked `holder(of:besides:)` first: a shortcut
    /// another command holds is `replace`d or not set.
    func set(_ shortcut: Shortcut?, for command: ShortcutCommand) {
        setWithoutSaving(shortcut, for: command)
        save()
    }

    /// Gives `command` the shortcut and takes it from the command that held it, which is left with none.
    func replace(_ shortcut: Shortcut, for command: ShortcutCommand) {
        if case .command(let holder)? = holder(of: shortcut, besides: command) { setWithoutSaving(nil, for: holder) }
        setWithoutSaving(shortcut, for: command)
        save()
    }

    /// Puts every command back to its default. A stored command MAPP no longer has stays as it was.
    func restoreDefaults() {
        for command in commands { chosen.removeValue(forKey: command.id) }
        save()
    }

    private func setWithoutSaving(_ shortcut: Shortcut?, for command: ShortcutCommand) {
        if shortcut == command.defaultShortcut {
            chosen.removeValue(forKey: command.id)
        } else {
            chosen[command.id] = .some(shortcut)
        }
    }

    private func save() {
        if chosen.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? Self.encoder.encode(Stored(shortcuts: chosen)) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    // MARK: Files

    /// Every command's shortcut as it is now, for Export.
    var current: [String: Shortcut?] {
        Dictionary(uniqueKeysWithValues: commands.map { ($0.id, shortcut(for: $0)) })
    }

    /// What `apply` did with a file's shortcuts.
    struct Applied: Equatable {
        /// The commands the file gave a shortcut or none.
        var applied = 0
        /// The file's commands MAPP no longer has, and the shortcuts left out because a command before it already took
        /// the same keys or the system holds them.
        var skipped = 0
    }

    /// Takes the file's shortcuts: a command the file does not name goes back to its default, a command MAPP does not
    /// have is skipped and counted, and a shortcut that an earlier command's, a default's or the system's already holds is
    /// left out and counted, so what results never gives two commands one key.
    func apply(_ shortcuts: [String: Shortcut?]) -> Applied {
        var result = Applied()
        let known = Set(commands.map(\.id))
        result.skipped += shortcuts.keys.filter { !known.contains($0) }.count
        // A command the file does not name keeps its default first, so a file never takes a key from a command it knows nothing of.
        var taken: [Shortcut: String] = [:]
        for command in commands where shortcuts[command.id] == nil {
            if let shortcut = command.defaultShortcut { taken[shortcut] = command.id }
        }
        var next: [String: Shortcut?] = chosen.filter { !known.contains($0.key) }
        for command in commands {
            guard let entry = shortcuts[command.id] else { continue }
            var wanted = entry
            result.applied += 1
            if let shortcut = wanted, taken[shortcut] != nil || SystemShortcuts.owner(of: shortcut) != nil || shortcut.menuProblem != nil {
                wanted = nil
                result.skipped += 1
                result.applied -= 1
            }
            if let shortcut = wanted { taken[shortcut] = command.id }
            if wanted != command.defaultShortcut { next[command.id] = .some(wanted) }
        }
        chosen = next
        save()
        return result
    }
}
