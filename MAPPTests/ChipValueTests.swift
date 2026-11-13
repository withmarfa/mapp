import Foundation
import Marfa
import Testing
@testable import MAPP

struct ChipValueTests {
    // MARK: Option colors

    /// The values are FNV-1a over the UTF-8 bytes, taken modulo the palette's nine tones, worked out apart from the code.
    @Test func anOptionKeepsItsColorAcrossLaunchesAndMachines() {
        #expect(OptionTone.tone(for: "High") == .pink)
        #expect(OptionTone.tone(for: "Low") == .purple)
        #expect(OptionTone.tone(for: "performance") == .green)
        #expect(OptionTone.tone(for: "editor") == .purple)
        #expect(OptionTone.tone(for: "bug") == .green)
        #expect(OptionTone.tone(for: "performance") == OptionTone.tone(for: "performance"))
    }

    @Test func noOptionTakesTheNeutralTone() {
        for word in ["a", "b", "c", "alpha", "beta", "in review", "Ünïcode", "🚀"] {
            #expect(OptionTone.tone(for: word) != .gray)
        }
        #expect(OptionTone.palette.contains(.gray) == false)
    }

    // MARK: Initials

    @Test(arguments: [
        ("Mira", "M"), ("Mira Castell", "MC"), ("mira castell", "MC"), ("Mira Jane Castell", "MC"),
        ("  Mira   Castell  ", "MC"), ("Émile Zola", "ÉZ"), ("🚀 Rocket", "🚀R"), ("👩‍👩‍👧 Family", "👩‍👩‍👧F"),
    ])
    func initialsTakeTheFirstAndLastWordByCharacter(name: String, initials: String) {
        #expect(PersonInitials.of(name) == initials)
    }

    @Test func aNameWithNothingInItHasNoInitials() {
        #expect(PersonInitials.of("") == nil)
        #expect(PersonInitials.of("   \n ") == nil)
    }

    @Test func anEmailAddressGivesOneInitialFromItsFirstLetter() {
        #expect(PersonInitials.of("mira@example.com") == "M")
    }

    @Test func anAccentedLetterWrittenAsTwoScalarsIsOneInitial() {
        #expect(PersonInitials.of("e\u{301}mile") == "E\u{301}")
    }

    // MARK: What a row carries

    private static let ticket = MarfaMapping.itemType(ItemType(
        id: "aic.ticket", label: "Ticket",
        fields: [
            TypeField(name: "title", label: nil, type: "string", description: nil, declaredBy: "aic.ticket", definition: [:]),
            TypeField(name: "priority", label: nil, type: "enum", description: nil, declaredBy: "aic.ticket", definition: ["enum_values": ["low", "high"]]),
            TypeField(name: "labels", label: nil, type: "array", description: nil, declaredBy: "aic.ticket", definition: [:]),
        ],
        titleField: "title", bodyField: nil))

    private static func rows(
        _ properties: [String: PropertyValue], relationships: [ItemRelationship] = [], tags: [String] = [],
        person: @escaping (ItemID) -> Bool = { _ in false }
    ) -> [PropertyRow] {
        let item = MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID("aic.ticket"), title: "Title", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .now, modified: .now)
        return PropertyRow.rows(
            of: item, type: Self.ticket, hidden: ["title"], relationships: relationships, parentField: "child-of", format: .automatic,
            tags: tags, icon: { _ in "lucide:book-open" }, isPerson: person)
    }

    private static func link(_ titles: [(String, String)]) -> ItemRelationship {
        ItemRelationship(
            field: "about", label: "About",
            targets: titles.map { ItemRelationshipTarget(title: $0.0, itemID: ItemID($0.1), resolution: .resolved(ItemID($0.1))) },
            isEditable: true, allowsMultiple: true)
    }

    private func encoded(_ row: PropertyRow) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
    }

    @Test func aChoiceAndAListOfWordsAreOptionsAndMarfasTagsAreTags() throws {
        let rows = Self.rows(["priority": .string("high"), "labels": .array([.string("bug"), .string("editor")])], tags: ["kitchen"])
        #expect(rows.first { $0.id == "priority" }?.value == .options(["High"]))
        #expect(rows.first { $0.id == "labels" }?.value == .options(["bug", "editor"]))
        #expect(rows.last?.value == .tags(["kitchen"]))
        let sent = try encoded(try #require(rows.first { $0.id == "labels" }))
        #expect(sent["kind"] as? String == "options")
        let options = try #require(sent["options"] as? [[String: Any]])
        #expect(options.map { $0["label"] as? String } == ["bug", "editor"])
        #expect(options.allSatisfy { $0["tone"] != nil })
        #expect(try encoded(try #require(rows.last))["kind"] as? String == "tags")
    }

    @Test func aLinkedItemCarriesItsOwnTypeIconAndTone() throws {
        let rows = Self.rows([:], relationships: [Self.link([("Garden beds", "a")])])
        let row = try #require(rows.first { $0.id == "about" })
        let sent = try encoded(row)
        #expect(sent["kind"] as? String == "items")
        let item = try #require((sent["items"] as? [[String: Any]])?.first)
        #expect(item["kind"] as? String == "link")
        #expect(item["symbol"] as? String == TypeIconKey.value(for: "lucide:book-open"))
        #expect(item["tone"] as? String == "orange")
    }

    @Test func aPersonCarriesInitialsAndNoTone() throws {
        let rows = Self.rows([:], relationships: [Self.link([("Mira Castell", "a"), ("  ", "b")])], person: { _ in true })
        let sent = try encoded(try #require(rows.first { $0.id == "about" }))
        let items = try #require(sent["items"] as? [[String: Any]])
        #expect(items.map { $0["kind"] as? String } == ["person", "person"])
        #expect(items[0]["initials"] as? String == "MC")
        #expect(items[1]["initials"] == nil)
        #expect(items[0]["tone"] == nil)
    }

    @Test func thePeopleAListNamesAreSentWithInitialsAndNoItemToOpen() throws {
        let row = PropertyRow(id: "assignees", label: "Assignees", value: .people(["Mira Castell", "r@example.com", "   "]))
        let sent = try encoded(row)
        #expect(sent["kind"] as? String == "people")
        #expect(sent["symbol"] as? String == "person.2")
        #expect(PropertyRow.Value.symbols.contains("person.2"))
        let people = try #require(sent["people"] as? [[String: Any]])
        #expect(people.map { $0["title"] as? String } == ["Mira Castell", "r@example.com", "   "])
        #expect(people.map { $0["initials"] as? String } == ["MC", "R", nil])
        #expect(people.allSatisfy { $0["item"] == nil })
    }
}
