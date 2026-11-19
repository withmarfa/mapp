import AppKit
import Testing
@testable import MAPP

@MainActor
struct KeyboardShortcutListTests {
    @Test func keysAreWrittenWithTheirModifiersInTheSystemsOrder() {
        #expect(KeyboardShortcutList.keys(keyEquivalent: "n", modifiers: [.command]) == "⌘N")
        #expect(KeyboardShortcutList.keys(keyEquivalent: "n", modifiers: [.command, .option]) == "⌥⌘N")
        #expect(KeyboardShortcutList.keys(keyEquivalent: "p", modifiers: [.shift, .command]) == "⇧⌘P")
        #expect(KeyboardShortcutList.keys(keyEquivalent: "K", modifiers: [.command]) == "⇧⌘K")
        #expect(KeyboardShortcutList.keys(keyEquivalent: "\u{7F}", modifiers: [.command]) == "⌘⌫")
        #expect(KeyboardShortcutList.keys(keyEquivalent: "", modifiers: [.command]) == nil)
    }

    @Test func menusAreGroupedByTitleAndOnlyCommandsWithAKeyAreListed() {
        func item(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        func top(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = menu
            return top
        }
        let hidden = item("Hidden", "h")
        hidden.isHidden = true
        let bar = NSMenu()
        bar.addItem(top("File", [item("New Item", "n"), item("Share"), .separator(), item("Close", "w")]))
        bar.addItem(top("Go", [item("Items")]))
        bar.addItem(top("View", [hidden, top("Sort", [item("By Title", "t", [.control])]), item("Zoom In", "+")]))

        let list = KeyboardShortcutList(menuBar: bar)
        #expect(list.sections.map(\.title) == ["File", "View"])
        #expect(list.sections[0].rows.map(\.title) == ["New Item", "Close"])
        #expect(list.sections[0].rows.map(\.keys) == ["⌘N", "⌘W"])
        #expect(list.sections[1].rows.map(\.title) == ["Sort > By Title", "Zoom In"])
        #expect(list.sections[1].rows.first?.keys == "⌃T")
        #expect(KeyboardShortcutList(menuBar: nil).isEmpty)
    }
}
