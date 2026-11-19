import AppKit

/// The keys the menu bar binds, grouped by menu, read from the menu bar itself, so the list is the keys that work and
/// no second list can fall out of step with the menus.
nonisolated struct KeyboardShortcutList: Equatable {
    struct Section: Equatable, Identifiable {
        let title: String
        let rows: [Row]

        var id: String { title }
    }

    struct Row: Equatable, Identifiable {
        let title: String
        let keys: String

        var id: String { title + keys }
    }

    var sections: [Section] = []

    var isEmpty: Bool { sections.isEmpty }

    /// Every menu's commands that have a key, in the menu's order. A command in a submenu is named after it.
    @MainActor
    init(menuBar: NSMenu?) {
        sections = (menuBar?.items ?? []).compactMap { top in
            guard let menu = top.submenu, !top.isHidden else { return nil }
            let rows = Self.rows(in: menu, prefix: "")
            return rows.isEmpty ? nil : Section(title: menu.title.isEmpty ? top.title : menu.title, rows: rows)
        }
    }

    init(sections: [Section] = []) {
        self.sections = sections
    }

    @MainActor
    private static func rows(in menu: NSMenu, prefix: String) -> [Row] {
        var rows: [Row] = []
        for item in menu.items where !item.isSeparatorItem && !item.isHidden {
            let title = prefix + item.title
            if let submenu = item.submenu {
                rows += Self.rows(in: submenu, prefix: title + " > ")
            } else if let keys = Self.keys(of: item), !title.isEmpty {
                let row = Row(title: title, keys: keys)
                if !rows.contains(row) { rows.append(row) }
            }
        }
        return rows
    }

    /// The key of a menu item. Back and Forward give ⌘[ and ⌘] up while the page has the keyboard, but the keys are still
    /// theirs, so the list names them whatever had the keyboard when it was read.
    @MainActor
    private static func keys(of item: NSMenuItem) -> String? {
        if let keys = keys(keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask) { return keys }
        if HistoryKeys.backTitles.contains(item.title) { return keys(keyEquivalent: HistoryKeys.back, modifiers: .command) }
        if item.title == HistoryKeys.forwardTitle { return keys(keyEquivalent: HistoryKeys.forward, modifiers: .command) }
        return nil
    }

    /// A key as the menus write it, modifiers first in the system's order, or nil for none.
    nonisolated static func keys(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> String? {
        guard !keyEquivalent.isEmpty else { return nil }
        var modifiers = modifiers.intersection([.control, .option, .shift, .command])
        // A capital letter stands for Shift with it.
        if keyEquivalent.count == 1, keyEquivalent != keyEquivalent.lowercased() { modifiers.insert(.shift) }
        let key = Self.named[keyEquivalent] ?? keyEquivalent.uppercased()
        return (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "") + key
    }

    private static let named: [String: String] = [
        String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑", String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓",
        String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←", String(UnicodeScalar(NSRightArrowFunctionKey)!): "→",
        String(UnicodeScalar(NSDeleteFunctionKey)!): "⌦", "\u{8}": "⌫", "\u{7F}": "⌫",
        "\r": "↩", "\u{3}": "⌤", "\t": "⇥", "\u{1B}": "⎋", " ": "Space",
    ]
}

/// The keys of Back and Forward, which the View menu gives up while the page has the keyboard (the page uses them to
/// outdent and indent a list item and to move between table cells).
nonisolated enum HistoryKeys {
    static let back = "["
    static let forward = "]"
    static let forwardTitle = String(localized: "Forward")
    /// Back reads Back to Table and the like where an item opened from a view that spans the window.
    static let backTitles = Set(ItemViewMode.allCases.map { String(localized: $0.backTitle) })
}

/// What the Keyboard Shortcuts window shows. It is read from the menu bar when a window with a browser asks for it, the
/// window the person was in, since the menus of a window with nothing to act on leave commands out. Asked from any other
/// window (the shortcuts window itself, an item's window), it keeps the list it has.
@MainActor @Observable
final class KeyboardShortcutsModel {
    private(set) var list = KeyboardShortcutList()

    func capture(from browser: Browser?, menuBar: NSMenu? = NSApp.mainMenu) {
        guard browser != nil else { return }
        list = KeyboardShortcutList(menuBar: menuBar)
    }
}
