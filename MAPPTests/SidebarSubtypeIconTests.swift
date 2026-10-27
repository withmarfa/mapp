import Foundation
import Testing
@testable import MAPP

/// Which sidebar rows keep their mark, and how a subtype's name steps in from its parent's.
@MainActor
struct SidebarSubtypeIconTests {
    func node(_ id: String, opens: Bool = true, _ children: [TypeNode] = []) -> TypeNode {
        TypeNode(id: id, type: opens ? TypeID(id) : nil, label: id, symbol: "doc", count: opens ? 1 : 0, total: 1, children: children)
    }

    func rows(_ nodes: [TypeNode], depth: Int = 0) -> [SidebarPlan.TypeRow] {
        nodes.flatMap { [SidebarPlan.TypeRow(node: $0, depth: depth, isExpanded: true)] + rows($0.children, depth: depth + 1) }
    }

    @Test func onlySubtypesLoseTheirMarkAndOnlyWhileTheSettingIsOff() {
        // a (a1 (a1x), group (g1)), with `group` a fold-only row.
        let listed = rows([node("a", [node("a1", [node("a1x")]), node("group", opens: false, [node("g1")])])])
        #expect(listed.map(\.id) == ["a", "a1", "a1x", "group", "g1"])
        #expect(listed.map { SidebarTypeRow.showsIcon($0, subtypeIcons: false) } == [true, false, false, true, false])
        #expect(listed.map { SidebarTypeRow.showsIcon($0, subtypeIcons: true) } == [true, true, true, true, true])
    }

    @Test func aColumnStepsInOnlyWhereItsParentHasNoMark() {
        let listed = rows([node("a", [node("a1", [node("a1x")]), node("group", opens: false, [node("g1")])])])
        let indent = SidebarTypeRow.indent

        let bare = SidebarTypeRow.steps(for: listed, subtypeIcons: false)
        #expect(bare[0].isEmpty)
        // a1 has no mark, and its name starts where a's does.
        #expect(bare[1] == [.init(continues: true, bends: true, spansParentMark: true, extra: 0)])
        // a1x has no mark under a1, which has none either: a step alone, since there is no mark to leave from.
        #expect(
            bare[2] == [
                .init(continues: true, bends: false, spansParentMark: true, extra: 0),
                .init(continues: false, bends: true, spansParentMark: false, extra: indent),
            ])
        // g1 has no mark under a group that keeps its own.
        #expect(bare[4].last == .init(continues: false, bends: true, spansParentMark: true, extra: 0))

        // With marks, every row sits under its parent's name: no step beyond the parent's mark.
        let marked = SidebarTypeRow.steps(for: listed, subtypeIcons: true)
        #expect(marked.flatMap { $0 }.allSatisfy { $0.spansParentMark && $0.extra == 0 })
    }
}
