import Foundation
import Observation

/// The shortcut each menu command has: the one the person chose, or its default. Only what was chosen is stored, so a
/// better default reaches every command nobody changed; a command the person cleared is stored as cleared. Shortcuts sync
/// through the connected Marfa (`PreferencesMap`).
///
/// A stored command that the app no longer has is ignored and kept, in case it returns. Stored text that cannot be read is
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
        /// One of the system's own commands, which a command of the app's cannot take.
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
        chosen = [:]
        reload()
    }

    /// Reads the stored value again, as when another Mac's change has reached the defaults (`PreferencesSync`).
    func reload() {
        guard let saved = defaults.data(forKey: Self.defaultsKey) else {
            chosen = [:]
            return
        }
        if let stored = try? JSONDecoder().decode(Stored.self, from: saved) {
            chosen = stored.shortcuts
        } else {
            chosen = [:]
            defaults.set((defaults.array(forKey: Self.setAsideKey) as? [Data] ?? []) + [saved], forKey: Self.setAsideKey)
            PreferenceHolds.willWrite(nil, forKey: Self.defaultsKey, in: defaults, by: .store)
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    // MARK: Reading

    /// The shortcut `command` has now: the person's choice, which may be none, or the default. A default never takes a
    /// key the person gave another command, so a command added later starts with none where its key is already theirs.
    func shortcut(for command: ShortcutCommand) -> Shortcut? {
        if let choice = chosen[command.id] { return choice }
        guard let standard = command.defaultShortcut, !isChosenByAnother(standard, besides: command) else { return nil }
        return standard
    }

    private func isChosenByAnother(_ shortcut: Shortcut, besides command: ShortcutCommand) -> Bool {
        commands.contains { other in
            guard other.id != command.id, case .some(.some(let choice)) = chosen[other.id] else { return false }
            return choice == shortcut
        }
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
        save(addressing: [command.id])
    }

    /// Gives `command` the shortcut and takes it from the command that held it, which is left with none.
    func replace(_ shortcut: Shortcut, for command: ShortcutCommand) {
        var addressed: Set<String> = [command.id]
        if case .command(let holder)? = holder(of: shortcut, besides: command) {
            setWithoutSaving(nil, for: holder)
            addressed.insert(holder.id)
        }
        setWithoutSaving(shortcut, for: command)
        save(addressing: addressed)
    }

    /// Puts every command back to its default. A stored command the app no longer has stays as it was.
    func restoreDefaults() {
        for command in commands { chosen.removeValue(forKey: command.id) }
        save(addressing: Set(commands.map(\.id)))
    }

    private func setWithoutSaving(_ shortcut: Shortcut?, for command: ShortcutCommand) {
        if shortcut == command.defaultShortcut {
            chosen.removeValue(forKey: command.id)
        } else {
            chosen[command.id] = .some(shortcut)
        }
    }

    /// Keeps the person's change, which set or reset the shortcuts of the commands `addressed` names.
    private func save(addressing addressed: Set<String>) {
        let writer = PreferenceHolds.Writer.person(dropped: .nothing, addressed: addressed)
        if chosen.isEmpty {
            PreferenceHolds.willWrite(nil, forKey: Self.defaultsKey, in: defaults, by: writer)
            defaults.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? Self.encoder.encode(Stored(shortcuts: chosen)) {
            PreferenceHolds.willWrite(data, forKey: Self.defaultsKey, in: defaults, by: writer)
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
        /// The file's commands the app no longer has, and the shortcuts left out because another command already holds the
        /// same keys, the system does, or they do not fit a menu. Such a command keeps what it had.
        var skipped = 0
    }

    /// Takes the file's shortcuts and leaves every command it does not name as it was. A command the app does not have is
    /// skipped and counted, and a shortcut that a command the file does not name, an earlier one, or the system already
    /// holds is left out and counted, so what results never gives two commands one key.
    func apply(_ shortcuts: [String: Shortcut?]) -> Applied {
        var result = Applied()
        let known = Set(commands.map(\.id))
        result.skipped += shortcuts.keys.filter { !known.contains($0) }.count
        let before = current
        var accepted = shortcuts.filter { known.contains($0.key) }
        for (id, entry) in accepted {
            if let entry, SystemShortcuts.owner(of: entry) != nil || entry.menuProblem != nil {
                accepted.removeValue(forKey: id)
                result.skipped += 1
            }
        }
        // An unchanged or refused command keeps its keys. Refusing one move can block another,
        // while a pair of commands that genuinely swap keys can move together.
        var refused: [String]
        repeat {
            var taken: Set<Shortcut> = []
            for command in commands where accepted[command.id] == nil || accepted[command.id] == before[command.id] {
                if let kept = before[command.id] ?? nil { taken.insert(kept) }
            }
            refused = commands.compactMap { command in
                guard let entry = accepted[command.id], let key = entry, entry != (before[command.id] ?? nil) else { return nil }
                return taken.insert(key).inserted ? nil : command.id
            }
            for id in refused { accepted.removeValue(forKey: id) }
            result.skipped += refused.count
        } while !refused.isEmpty
        for command in commands {
            if let entry = accepted[command.id] { setWithoutSaving(entry, for: command) }
        }
        result.applied = accepted.count
        save(addressing: Set(accepted.keys))
        return result
    }
}
