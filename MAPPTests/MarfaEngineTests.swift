import Foundation
import Marfa
import Testing
@testable import MAPP

struct MarfaEngineTests {
    private static let catalogue = MarfaMapping.catalogue(
        itemTypes: [
            ItemType(
                id: "core.note", label: "Note",
                fields: [
                    TypeField(name: "title", type: "string", declaredBy: "core.note"),
                    TypeField(name: "body", type: "string", declaredBy: "core.note")
                ],
                titleField: "title", bodyField: "body"),
            ItemType(id: "core.entity", label: "Entity", fields: [TypeField(name: "name", type: "string", declaredBy: "core.entity")], titleField: "name")
        ],
        edgeTypes: [])

    private static func row(_ type: String, _ properties: JSONObject) -> Marfa.Item {
        Marfa.Item(
            id: "i", type: type, properties: properties, state: .active, tier: .library, version: 1, schemaVersion: 1,
            source: "test", sourceId: nil, occurredAt: "2026-10-06T00:00:00Z", createdAt: "2026-10-06T00:00:00Z",
            updatedAt: "2026-10-06T00:00:00Z", tags: [])
    }

    /// Text read on this device's own create before the server answered it is version 1 once the copy holds the
    /// answer; any other version read stays as it is.
    @Test(arguments: [(Int64(0), Int64(0), Int64(0)), (0, 1, 1), (0, 3, 1), (2, 3, 2), (3, 3, 3)])
    func textReadOnACreateGoesOnTheVersionItsAnswerMade(read: Int64, held: Int64, expected: Int64) {
        #expect(MarfaEngine.version(read: read, holding: held) == expected)
    }

    @Test func onlyTextThatCanLinkOrEmbedIsAskedForItsLinks() {
        func asks(_ body: String, type: String = "core.note") -> Bool {
            MarfaEngine.mayName(Self.row(type, ["title": "T", "body": .string(body)]), catalogue: Self.catalogue)
        }
        #expect(asks("See [[Plan]]"))
        #expect(asks("A photo: ![[cat.png]]"))
        #expect(asks("A photo: ![cat](cat.png)"))
        #expect(!asks("A list\n- [ ] with a box\n- [x] and a tick"))
        #expect(!asks("[a link](https://example.com) is no edge of Marfa's"))
        #expect(!asks(""))
        // A type with no text has none to ask about, and a type the catalogue lacks is read as having none.
        #expect(!asks("[[Plan]]", type: "core.entity"))
        #expect(!asks("[[Plan]]", type: "aic.unknown"))
    }

    // MARK: Editing properties

    @Test func aPropertyGivenAValueIsSentAndNothingElseIsNamed() {
        let edit = MarfaEngine.propertyEdit(["b": .string("2"), "a": .number(1)])
        #expect(edit.properties == ["a": .integer(1), "b": .string("2")], "in key order, so the same change is the same write")
        #expect(edit.clearing.isEmpty)
    }

    @Test func takingAPropertyAwayNamesItAndNothingElse() {
        let cleared = MarfaEngine.propertyEdit(["status": nil, "title": .string("New")])
        #expect(cleared.properties == ["title": "New"], "the properties the edit does not name are not sent, so the server keeps them")
        #expect(cleared.clearing == ["status"])

        // A null clears nothing on its own, so it is taken as taking the property away.
        let nulled = MarfaEngine.propertyEdit(["status": .null])
        #expect(nulled.properties.isEmpty)
        #expect(nulled.clearing == ["status"])
    }

    @Test func anEmbedIsReadBackAsTheNameTheFileWasGiven() {
        #expect(MarfaEngine.embeddedName("![[photo.png]]") == "photo.png")
        #expect(MarfaEngine.embeddedName("![[Photo 2.png]]") == "Photo 2.png")
        #expect(MarfaEngine.embeddedName("![[]]") == nil)
        #expect(MarfaEngine.embeddedName("[[photo.png]]") == nil)
        #expect(MarfaEngine.embeddedName("![](photo.png)") == nil)
    }

    @Test func thePageWritesTheNameAsADestinationTheCoreReadsBack() {
        #expect(MarfaEngine.link(to: "photo.png") == "photo.png")
        #expect(MarfaEngine.link(to: "Photo 2.png") == "Photo%202.png")
        #expect(MarfaEngine.link(to: "100% sure.png").contains("%25"))
        #expect(MarfaEngine.link(to: "image (1).png") == "image%20%281%29.png")
        #expect(MarfaEngine.embeddable("Plan #2 [draft] | v^1.png") == "Plan -2 -draft- - v-1.png")
        #expect(MarfaEngine.embeddable("photo.png") == "photo.png")
    }
}
