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

    @Test func backAndForwardAreListedWithTheirKeysWhateverHadTheKeyboard() {
        // While the page has the keyboard the menu items carry no key, yet the keys are theirs.
        func bare(_ title: String) -> NSMenuItem { NSMenuItem(title: title, action: nil, keyEquivalent: "") }
        let menu = NSMenu(title: "View")
        [bare(String(localized: "Back to Table")), bare(HistoryKeys.forwardTitle), bare("Reader")].forEach(menu.addItem)
        let top = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        top.submenu = menu
        let bar = NSMenu()
        bar.addItem(top)

        let rows = KeyboardShortcutList(menuBar: bar).sections.first?.rows
        #expect(rows?.map(\.keys) == ["⌘[", "⌘]"])
        #expect(rows?.map(\.title) == [String(localized: "Back to Table"), HistoryKeys.forwardTitle])
    }

    @Test func aWindowWithNoBrowserLeavesTheCapturedListAlone() {
        func bar(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "n")
            let menu = NSMenu(title: "File")
            menu.addItem(item)
            let top = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            top.submenu = menu
            let bar = NSMenu()
            bar.addItem(top)
            return bar
        }
        let model = KeyboardShortcutsModel()
        model.capture(from: Browser(), menuBar: bar("New Item"))
        model.capture(from: nil, menuBar: bar("Poorer"))
        #expect(model.list.sections.first?.rows.map(\.title) == ["New Item"])
    }
}
