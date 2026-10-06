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

    @Test func aWriteOnlyFilesMakeIsRefusedInPlainWords() {
        #expect(MarfaEngine.filesOnly == String(localized: "This change can’t be made in a Marfa library."))
    }
}
