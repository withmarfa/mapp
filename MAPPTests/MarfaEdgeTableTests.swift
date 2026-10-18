import Foundation
import Marfa
import struct MarfaCore.Edge
import Testing
@testable import MAPP

struct MarfaEdgeTableTests {
    private static func edge(_ id: String, from source: String, to target: String) -> Marfa.Edge {
        Marfa.Edge(
            id: id, sourceId: source, targetId: target, edgeType: "parent-of", properties: [:], version: 1,
            createdAt: "2026-10-06T00:00:00Z", updatedAt: "2026-10-06T00:00:00Z")
    }

    @Test func anEdgeReadAtOneEndAndThenAtAnotherIsHeldOnlyAtTheLatter() {
        var table = MarfaEdgeTable()
        // The copy changed between two reads: the edge was read at A, then a move landed, then read at B.
        table.insert(Self.edge("e", from: "a", to: "child"))
        table.insert(Self.edge("e", from: "b", to: "child"))
        #expect(table["e"]?.sourceId == "b")
        #expect(table.ids(touching: "a").isEmpty, "a no longer holds an edge it let go")
        #expect(table.ids(touching: "b") == ["e"])
        #expect(table.ids(touching: "child") == ["e"])

        // An edit to A reads A's edges again, finds none, and drops what the table lists under A.
        for id in table.ids(touching: "a") { table.remove(id) }
        #expect(table["e"]?.sourceId == "b", "the child keeps the parent the copy holds")
        #expect(table.edges(touching: "child").map(\.sourceId) == ["b"])
    }

    @Test func removingAnEdgeClearsBothEndsAndAnUnknownIdChangesNothing() {
        var table = MarfaEdgeTable()
        table.insert(Self.edge("e", from: "a", to: "b"))
        table.insert(Self.edge("f", from: "a", to: "c"))
        #expect(table.remove("e")?.targetId == "b")
        #expect(table.ids(touching: "b").isEmpty)
        #expect(table.ids(touching: "a") == ["f"])
        #expect(table.remove("nope") == nil)
        table.removeAll()
        #expect(table.edges(touching: "a").isEmpty)
    }
}
