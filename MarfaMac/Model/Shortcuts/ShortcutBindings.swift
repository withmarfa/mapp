import Foundation
import Observation

/// The shortcut each menu command has: the one the person chose, or its default. Only what was chosen is stored, so a
/// better default reaches every command nobody changed; a command the person cleared is stored as cleared. Shortcuts sync
/// through the connected Marfa (`PreferencesMap`).
///
/// A stored command that the app no longer has is ignored and kept, in case it returns. A stored shortcut this version cannot
/// read stays as stored until the person sets that command's shortcut, and is moved aside under a key of its own first.
/// Stored text that is no map of shortcuts is moved aside whole, kept and never removed, and the commands start from their
/// defaults.
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
    /// The commands whose stored shortcut this version cannot read, as stored.
    @ObservationIgnored private var unread: [String: StoredJSON] = [:]

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
            unread = [:]
            return
        }
        if let shortcuts = ((try? JSONSerialization.jsonObject(with: saved)) as? [String: Any])?["shortcuts"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: shortcuts),
           let (readable, unread) = StoredEntries.decode(data, as: Shortcut?.self)
        {
            chosen = readable
            self.unread = unread
        } else {
            chosen = [:]
            unread = [:]
            defaults.removeObject(forKey: Self.defaultsKey)
            PreferenceHolds.setAside(saved, under: Self.setAsideKey, of: Self.defaultsKey, keys: nil, in: defaults)
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

    /// Puts every command back to its default. A stored command the app no longer has stays as it was.
    func restoreDefaults() {
        for command in commands { chosen.removeValue(forKey: command.id) }
        save()
    }

    private func setWithoutSaving(_ shortcut: Shortcut?, for command: ShortcutCommand) {
        displace(command.id)
        if shortcut == command.defaultShortcut {
            chosen.removeValue(forKey: command.id)
        } else {
            chosen[command.id] = .some(shortcut)
        }
    }

    /// Sets aside the stored shortcut of `command` this version cannot read, which the person's choice replaces.
    private func displace(_ command: String) {
        guard let kept = unread.removeValue(forKey: command) else { return }
        defaults.set((defaults.array(forKey: Self.setAsideKey) as? [Data] ?? []) + [Data(kept.text.utf8)], forKey: Self.setAsideKey)
    }

    private func save() {
        if chosen.isEmpty, unread.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else if let entries = StoredEntries.encode(chosen, keeping: unread) {
            defaults.set(Data(#"{"shortcuts":"#.utf8) + entries + Data("}".utf8), forKey: Self.defaultsKey)
        }
    }

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
        var taken: [Shortcut: String] = [:]
        for command in commands where shortcuts[command.id] == nil {
            if let shortcut = shortcut(for: command) { taken[shortcut] = command.id }
        }
        var next = chosen
        for command in commands {
            guard let entry = shortcuts[command.id] else { continue }
            if let shortcut = entry, taken[shortcut] != nil || SystemShortcuts.owner(of: shortcut) != nil || shortcut.menuProblem != nil {
                result.skipped += 1
                if let kept = self.shortcut(for: command), taken[kept] == nil { taken[kept] = command.id }
                continue
            }
            result.applied += 1
            displace(command.id)
            if let entry { taken[entry] = command.id }
            if entry != command.defaultShortcut { next[command.id] = .some(entry) } else { next.removeValue(forKey: command.id) }
        }
        chosen = next
        save()
        return result
    }
}
