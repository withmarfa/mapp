import Foundation

/// The menu a command is in, which names the section it is listed under in Settings.
nonisolated enum ShortcutMenu: Int, CaseIterable, Comparable, Sendable {
    case app, file, edit, view, format

    var title: String {
        switch self {
        case .app: String(localized: "MAPP")
        case .file: String(localized: "File")
        case .edit: String(localized: "Edit")
        case .view: String(localized: "View")
        case .format: String(localized: "Format")
        }
    }

    static func < (left: Self, right: Self) -> Bool { left.rawValue < right.rawValue }
}

/// A menu command MAPP adds, which a person can give a shortcut of their own. `id` never changes once shipped, since a
/// stored or exported shortcut names the command by it.
nonisolated struct ShortcutCommand: Hashable, Identifiable, Sendable {
    let id: String
    let menu: ShortcutMenu
    let title: String
    let defaultShortcut: Shortcut?

    init(_ id: String, in menu: ShortcutMenu, _ title: String, _ key: String? = nil, _ modifiers: ShortcutModifiers = .command) {
        self.id = id
        self.menu = menu
        self.title = title
        defaultShortcut = key.map { Shortcut(key: $0, modifiers: modifiers) }
    }
}

/// The keys of the system's own commands that MAPP does not add, which no command of MAPP's can take.
nonisolated enum SystemShortcuts {
    /// The command a shortcut belongs to in the system's menus, or nil if it is free.
    static func owner(of shortcut: Shortcut) -> String? { reserved[shortcut] }

    private static let reserved: [Shortcut: String] = {
        func entry(_ key: String, _ modifiers: ShortcutModifiers, _ title: String) -> (Shortcut, String) {
            (Shortcut(key: key, modifiers: modifiers), title)
        }
        return Dictionary(uniqueKeysWithValues: [
            entry("q", .command, String(localized: "Quit")), entry("h", .command, String(localized: "Hide")),
            entry("h", [.command, .option], String(localized: "Hide Others")), entry("m", .command, String(localized: "Minimize")),
            entry("w", .command, String(localized: "Close")), entry("z", .command, String(localized: "Undo")),
            entry("z", [.command, .shift], String(localized: "Redo")), entry("x", .command, String(localized: "Cut")),
            entry("c", .command, String(localized: "Copy")), entry("v", .command, String(localized: "Paste")),
            entry("a", .command, String(localized: "Select All")), entry("`", .command, String(localized: "Move Between Windows")),
            entry(" ", .command, String(localized: "Spotlight")),
            entry("f", [.control, .command], String(localized: "Enter Full Screen")),
            entry("w", [.option, .command], String(localized: "Close All")),
            entry("m", [.option, .command], String(localized: "Minimize All")),
            entry(" ", [.control, .command], String(localized: "Emoji & Symbols")),
            entry("/", [.shift, .command], String(localized: "Help")),
            entry("v", [.option, .shift, .command], String(localized: "Paste and Match Style")),
            entry("\\", [.shift, .command], String(localized: "Show All Tabs")),
            entry(";", .command, String(localized: "Check Document Now")),
            entry(";", [.shift, .command], String(localized: "Show Spelling and Grammar")),
            entry("`", [.shift, .command], String(localized: "Move Between Windows")),
            // The View menu's, which every window with a toolbar gets from the system.
            entry("t", [.option, .command], String(localized: "Show Toolbar")),
        ])
    }()
}
