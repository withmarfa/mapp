import AppKit
import Observation

/// What the Keyboard page does with the keys the person presses: records a shortcut for a command, refuses one that does not
/// fit or that another command holds, and works out which rows a search leaves. It holds no view, so the rules can be tried
/// without one.
@Observable @MainActor
final class KeyboardPageModel {
    /// A row's shortcut: a menu command's, or one that works in any app.
    enum Target: Hashable {
        case menu(ShortcutCommand)
        case anyApp(AnyAppCommand)
    }

    /// Why a shortcut was not given, kept until the person decides or records again. The row shows it as the red ring and one
    /// line under its title.
    struct Refusal: Equatable {
        enum Reason: Equatable {
            case needsModifier
            case needsCommandOrControl
            case unknownKey
            /// Another command has the keys. `canReplace` is false for one of the system's, which MAPP's commands cannot take.
            case taken(by: String, canReplace: Bool)
        }

        let target: Target
        let shortcut: Shortcut
        let reason: Reason

        /// The one line under the row's title.
        var line: String {
            switch reason {
            case .needsModifier: String(localized: "Include ⌘, ⌃, or ⌥.")
            case .needsCommandOrControl: String(localized: "Include ⌘ or ⌃.")
            case .unknownKey: String(localized: "That key can’t be used.")
            case .taken(let holder, _): String(localized: "\(shortcut.display) is \(holder)’s.")
            }
        }

        var canReplace: Bool {
            if case .taken(_, let canReplace) = reason { canReplace } else { false }
        }
    }

    let bindings: ShortcutBindings
    let anyApp: AnyAppShortcuts

    /// The row waiting for a key press, at most one.
    var recording: Target?
    var refusal: Refusal?
    var search = ""
    /// Whether the search is of the keys pressed and not of the words typed.
    var searchesByKeys = false
    var pressed: Shortcut?

    init(bindings: ShortcutBindings, anyApp: AnyAppShortcuts) {
        self.bindings = bindings
        self.anyApp = anyApp
    }

    // MARK: Rows

    func shortcut(for target: Target) -> Shortcut? {
        switch target {
        case .menu(let command): bindings.shortcut(for: command)
        case .anyApp(let command): anyApp.shortcut(for: command)
        }
    }

    /// The red line of a row, or nil for a row nothing was refused for.
    func error(for target: Target) -> String? {
        refusal?.target == target ? refusal?.line : nil
    }

    /// The keys a row shows: the ones refused while it is refused, so the person sees what was pressed.
    func keys(for target: Target) -> String? {
        refusal?.target == target ? refusal?.shortcut.display : shortcut(for: target)?.display
    }

    // MARK: Recording

    func startRecording(_ target: Target) {
        refusal = nil
        recording = target
    }

    func stopRecording() { recording = nil }

    /// Gives the recorded row the shortcut, or says why not. A shortcut another command holds waits for the person to
    /// replace it or cancel.
    func record(_ shortcut: Shortcut) {
        guard let target = recording else { return }
        recording = nil
        refusal = nil
        switch target {
        case .menu(let command):
            if shortcut.menuProblem != nil {
                refusal = Refusal(target: target, shortcut: shortcut, reason: .needsModifier)
            } else if let holder = bindings.holder(of: shortcut, besides: command) {
                var canReplace = true
                if case .system = holder { canReplace = false }
                refusal = Refusal(target: target, shortcut: shortcut, reason: .taken(by: holder.name, canReplace: canReplace))
            } else {
                bindings.set(shortcut, for: command)
            }
        case .anyApp(let command):
            switch anyApp.refusal(of: shortcut, for: command) {
            case nil: anyApp.set(shortcut, for: command)
            case .unfit(.needsCommandOrControl)?: refusal = Refusal(target: target, shortcut: shortcut, reason: .needsCommandOrControl)
            case .unfit?: refusal = Refusal(target: target, shortcut: shortcut, reason: .unknownKey)
            case .taken(let other)?: refusal = Refusal(target: target, shortcut: shortcut, reason: .taken(by: other.title, canReplace: true))
            }
        }
    }

    /// Takes the keys from the command that holds them and gives them to the refused row.
    func replace() {
        guard let refusal, refusal.canReplace else { return }
        self.refusal = nil
        switch refusal.target {
        case .menu(let command): bindings.replace(refusal.shortcut, for: command)
        case .anyApp(let command):
            if let holder = anyApp.holder(of: refusal.shortcut, besides: command) { anyApp.set(nil, for: holder) }
            anyApp.set(refusal.shortcut, for: command)
        }
    }

    /// Leaves the row as it was.
    func cancelRefusal() { refusal = nil }

    func clear(_ target: Target) {
        refusal = nil
        switch target {
        case .menu(let command): bindings.set(nil, for: command)
        case .anyApp(let command): anyApp.set(nil, for: command)
        }
    }

    /// Puts every command back to its default and turns every shortcut that works in any app off.
    func restoreDefaults() {
        refusal = nil
        recording = nil
        bindings.restoreDefaults()
        anyApp.clearAll()
    }

    // MARK: Search

    /// Whether the search leaves a row: by name, the words typed are in its title; by keys, it has the keys pressed last,
    /// and a search with nothing pressed leaves every row.
    func matches(_ title: String, _ target: Target) -> Bool {
        if searchesByKeys {
            guard let pressed else { return true }
            return shortcut(for: target) == pressed
        }
        let words = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty || title.localizedStandardContains(words)
    }

    /// The menus that have a row the search leaves, in menu order, with those rows.
    var sections: [(menu: ShortcutMenu, commands: [ShortcutCommand])] {
        ShortcutMenu.allCases.compactMap { menu in
            let commands = bindings.commands.filter { $0.menu == menu && matches($0.title, .menu($0)) }
            return commands.isEmpty ? nil : (menu, commands)
        }
    }

    var anyAppCommands: [AnyAppCommand] {
        AnyAppCommand.allCases.filter { matches($0.title, .anyApp($0)) }
    }

    var hasResults: Bool { !sections.isEmpty || !anyAppCommands.isEmpty }

    /// Says how many of a section's commands have the keys pressed, under its name while searching by keys.
    func line(forCount count: Int) -> String? {
        guard searchesByKeys, let pressed else { return nil }
        return count == 1 ? String(localized: "One command uses \(pressed.display).") : String(localized: "\(count) commands use \(pressed.display).")
    }
}
