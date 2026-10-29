import AppKit
import Testing
@testable import MAPP

private let item = MenuSeparators.Entry(isSeparator: false)
private let line = MenuSeparators.Entry(isSeparator: true)
private let gone = MenuSeparators.Entry(isSeparator: false, isHidden: true)

/// The separators a menu keeps, whichever of the items around them rendered nothing.
@MainActor struct MenuSeparatorsTests {

    @Test func hidesOnlySeparatorsThatSeparateNothing() {
        let cases: [(entries: [MenuSeparators.Entry], hidden: Set<Int>)] = [
            ([item, line, item], []),
            ([item, line, line, item], [2]),
            ([item, line, line, line, item], [2, 3]),
            ([line, item], [0]),
            ([item, line], [1]),
            ([line, line, item, line, line], [0, 1, 3, 4]),
            ([], []),
            ([line], [0]),
            ([item, line, gone, line, item], [3]),
            ([item, line, gone, item], []),
            ([item, gone, line], [2]),
        ]
        for (entries, hidden) in cases {
            #expect(MenuSeparators.redundant(in: entries) == hidden, "\(entries)")
        }
    }

    private func menu(_ titles: [String?]) -> NSMenu {
        let menu = NSMenu()
        for title in titles {
            menu.addItem(title.map { NSMenuItem(title: $0, action: nil, keyEquivalent: "") } ?? .separator())
        }
        return menu
    }

    private func shown(_ menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isHidden }.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    @Test func tidiesAMenuAndItsSubmenus() {
        let inner = menu([nil, "Inner", nil, nil, "Other", nil])
        let outer = menu([nil, "Hide Toolbar", nil, nil, "Recently Deleted", nil])
        let parent = NSMenuItem(title: "Saved", action: nil, keyEquivalent: "")
        parent.submenu = inner
        outer.insertItem(parent, at: 5)
        MenuSeparatorTidy().tidy(outer)
        #expect(shown(outer) == ["Hide Toolbar", "-", "Recently Deleted", "Saved"])
        #expect(shown(inner) == ["Inner", "-", "Other"])
    }

    @Test func aSeparatorTheTidyHidBecomesVisibleWhenItsNeighborsReturn() {
        let menu = menu(["One", nil, "Two"])
        let tidy = MenuSeparatorTidy()
        menu.items[2].isHidden = true
        tidy.tidy(menu)
        #expect(shown(menu) == ["One"])
        menu.items[2].isHidden = false
        tidy.tidy(menu)
        #expect(shown(menu) == ["One", "-", "Two"])
    }

    @Test func leavesAnItemHiddenByAnotherAlone() {
        let menu = menu(["One", nil, "Two"])
        menu.items[0].isHidden = true
        let tidy = MenuSeparatorTidy()
        tidy.tidy(menu)
        tidy.tidy(menu)
        #expect(menu.items[0].isHidden)
        #expect(shown(menu) == ["Two"])
    }
}
