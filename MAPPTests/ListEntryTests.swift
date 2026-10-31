import Foundation
import Marfa
import Testing
@testable import MAPP

struct ListEntryTests {
    private static func listField(_ name: String, _ members: JSONObject) -> TypeField {
        TypeField(name: name, type: "array", declaredBy: "core.entity", definition: ["items_type": "object", "items_fields": .object(members)])
    }

    private static let emails = listField("emails", ["value": ["type": "email", "required": true], "label": ["type": "string"]])
    private static let phones = listField("phones", ["value": ["type": "string", "required": true], "label": ["type": "string"]])
    private static let addresses = listField("addresses", [
        "label": ["type": "string"], "street_address": ["type": "string"], "locality": ["type": "string"],
    ])
    private static let attendees = listField("attendees", [
        "name": ["type": "string"], "email": ["type": "email"],
        "response": ["type": "enum", "enum_values": ["needs_action", "accepted", "declined", "tentative"]],
    ])
    private static let scores = listField("scores", ["points": ["type": "integer", "minimum": 1, "maximum": 5]])

    private static let person = MarfaMapping.itemType(ItemType(
        id: "core.entity.person", label: "Person", fields: [
            TypeField(name: "title", type: "string", declaredBy: "core.entity"), emails, phones, addresses,
        ], titleField: "title"))

    private static func shape(_ field: TypeField) throws -> ListShape {
        let mapped = try #require(MarfaMapping.itemType(ItemType(id: "t", label: "T", fields: [field])).fields.first)
        guard case .list(let shape) = mapped.kind else { Issue.record("not a list: \(mapped.kind)"); throw CancellationError() }
        return shape
    }

    private static func entry(_ pairs: KeyValuePairs<String, PropertyValue>) -> PropertyValue {
        .object(Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value) }))
    }

    // MARK: Mapping

    @Test func aListOfEntriesMapsToAListKindWithItsMembersInDeclaredOrder() throws {
        let shape = try Self.shape(Self.attendees)
        #expect(shape.members.map(\.key) == ["name", "email", "response"])
        #expect(shape.member("email")?.kind == .text(.email))
        #expect(shape.member("response")?.kind == .choice(["needs_action", "accepted", "declined", "tentative"]))
        let required = try Self.shape(Self.emails)
        #expect(required.member("value")?.required == true)
        #expect(required.member("label")?.required == false)
    }

    @Test func anArrayWithNoMembersIsNotAList() {
        let tags = TypeField(name: "tags", type: "array", declaredBy: "t", definition: ["items_type": "string"])
        let mapped = MarfaMapping.itemType(ItemType(id: "t", label: "T", fields: [tags])).fields.first
        #expect(mapped?.kind == .other)
    }

    @Test func aMemberTheAppCannotReadLeavesTheListUntouchedRatherThanEditedBlind() {
        let odd = Self.listField("odd", ["value": ["type": "string"], "blob": ["type": "geometry"]])
        let mapped = MarfaMapping.itemType(ItemType(id: "t", label: "T", fields: [odd])).fields.first
        #expect(mapped?.kind == .other)
    }

    @Test func aNumberFieldCarriesItsBounds() throws {
        let rating = TypeField(name: "rating", type: "integer", declaredBy: "core.media", definition: ["minimum": 1, "maximum": 5])
        let field = try #require(MarfaMapping.itemType(ItemType(id: "core.media", label: "Media", fields: [rating])).fields.first)
        #expect(field.numberRule == NumberRule(integer: true, minimum: 1, maximum: 5))
        let members = try Self.shape(Self.scores)
        #expect(members.member("points")?.kind == .number(NumberRule(integer: true, minimum: 1, maximum: 5)))
    }

    // MARK: Editing

    @Test func editingOneMemberWritesTheWholeListWithTheOthersUnchanged() {
        let first = Self.entry(["value": .string("a@example.com"), "label": .string("work")])
        let second = Self.entry(["value": .string("b@example.com")])
        let third = Self.entry(["value": .string("c@example.com"), "label": .string("home")])
        let list = PropertyValue.array([first, second, third])
        let edited = ListEntries.setting("label", to: .string("old"), at: 1, in: list)
        #expect(edited == .array([first, Self.entry(["value": .string("b@example.com"), "label": .string("old")]), third]))
        // Clearing a member removes only it.
        #expect(ListEntries.setting("label", to: nil, at: 0, in: list) == .array([Self.entry(["value": .string("a@example.com")]), second, third]))
    }

    @Test func anEntryTheAppCannotReadIsCarriedAlong() {
        let odd = PropertyValue.string("a@example.com")
        let list = PropertyValue.array([odd, Self.entry(["value": .string("b@example.com")])])
        let edited = ListEntries.setting("label", to: .string("x"), at: 1, in: list)
        #expect(ListEntries.entries(of: edited).first == odd)
        // Editing the entry it cannot read changes nothing.
        #expect(ListEntries.setting("label", to: .string("x"), at: 0, in: list) == list)
    }

    @Test func addingRemovingAndReorderingKeepTheRest() {
        let a = Self.entry(["value": .string("a")]), b = Self.entry(["value": .string("b")]), c = Self.entry(["value": .string("c")])
        let list = PropertyValue.array([a, b])
        guard case .object(let added) = c else { return }
        #expect(ListEntries.appending(added, to: list) == .array([a, b, c]))
        #expect(ListEntries.appending(added, to: nil) == .array([c]))
        #expect(ListEntries.removing(at: 0, from: .array([a, b, c])) == .array([b, c]))
        #expect(ListEntries.removing(at: 0, from: .array([a])) == nil)
        #expect(ListEntries.moving(from: 2, to: 0, in: .array([a, b, c])) == .array([c, a, b]))
        #expect(ListEntries.makingMain(1, in: .array([a, b, c])) == .array([b, a, c]))
        #expect(ListEntries.makingMain(0, in: .array([a, b])) == .array([a, b]))
    }

    @Test func theFirstEntryIsTheMainOne() {
        let list = PropertyValue.array([Self.entry(["value": .string("a")]), Self.entry(["value": .string("b")])])
        #expect(ListEntries.main(of: list)?["value"] == .string("a"))
        #expect(ListEntries.main(of: ListEntries.makingMain(1, in: list))?["value"] == .string("b"))
        #expect(ListEntries.main(of: nil) == nil)
    }

    // MARK: Refusing

    @Test func anEntryNeedsItsRequiredMembersAndAtLeastOneValue() throws {
        let shape = try Self.shape(Self.emails)
        #expect(shape.refusal(of: ["value": .string("a@example.com")]) == nil)
        #expect(shape.refusal(of: ["label": .string("work")]) != nil)
        #expect(shape.refusal(of: [:]) != nil)
        #expect(shape.accepts(Self.entry(["value": .string("a@example.com")])))
        #expect(!shape.accepts(Self.entry(["nope": .string("a")])))
        #expect(!shape.accepts(.string("a")))
    }

    @Test func aNumberMemberRefusesWhatIsOutOfRange() throws {
        let shape = try Self.shape(Self.scores)
        #expect(shape.refusal(of: ["points": .number(3)]) == nil)
        #expect(shape.refusal(of: ["points": .number(6)]) != nil)
        #expect(shape.refusal(of: ["points": .number(0)]) != nil)
        #expect(shape.refusal(of: ["points": .number(Decimal(string: "2.5")!)]) != nil)
    }

    @Test func aNumberFieldRefusesWhatIsOutOfRangeAtInput() {
        let rule = NumberRule(integer: true, minimum: 1, maximum: 5)
        let english = Locale(identifier: "en_US")
        #expect(PropertyNumber.parse("3", rule: rule, locale: english) == 3)
        #expect(PropertyNumber.parse("6", rule: rule, locale: english) == nil)
        #expect(PropertyNumber.parse("0", rule: rule, locale: english) == nil)
        #expect(PropertyNumber.parse("1.5", rule: rule, locale: english) == nil)
        let draft = ItemPropertyDraft()
        draft.base = "3"
        draft.text = "9"
        draft.isDirty = true
        #expect(draft.commit(as: .number, rule: rule, current: "3", locale: english) == .outOfRange)
        #expect(draft.loss(as: .number, rule: rule, current: "3", isEditable: true, locale: english) == .outOfRange)
        draft.text = "4"
        #expect(draft.commit(as: .number, rule: rule, current: "3", locale: english) == .write(.number(4)))
        let open = NumberRule(minimum: 0)
        #expect(open.allows(0) && !open.allows(-1) && open.allows(1_000_000))
    }

    @Test func aTypeChangeKeepsOnlyANumberTheNewFieldTakes() {
        let rating = ItemTypeInfo.Field(
            key: "rating", label: "Rating", kind: .number, declaredBy: TypeID("core.media"), isInteger: true,
            minimum: 1, maximum: 5)
        #expect(rating.accepts(.number(4)))
        #expect(!rating.accepts(.number(9)))
        #expect(!rating.accepts(.number(Decimal(string: "2.5")!)))
    }

    // MARK: Reading

    @Test func anEntryIsSummarisedByItsContentThenItsQualifiers() throws {
        let emails = try Self.shape(Self.emails)
        #expect(emails.summary(of: ["value": .string("a@example.com"), "label": .string("work")]) == "a@example.com (work)")
        let attendees = try Self.shape(Self.attendees)
        // A name, or the email where there is none; the response follows.
        #expect(attendees.summary(of: ["name": .string("Ruth"), "email": .string("r@example.com"), "response": .string("accepted")]) == "Ruth (Accepted)")
        #expect(attendees.summary(of: ["email": .string("r@example.com")]) == "r@example.com")
        let addresses = try Self.shape(Self.addresses)
        #expect(addresses.summary(of: ["label": .string("home"), "street_address": .string("1 High Street"), "locality": .string("London")])
                == "1 High Street, London (home)")
    }

    @Test func aTableCellShowsTheMainEntryAndHowManyMore() throws {
        let emails = try Self.shape(Self.emails)
        let list = PropertyValue.array([
            Self.entry(["value": .string("a@example.com")]), Self.entry(["value": .string("b@example.com")]),
            Self.entry(["value": .string("c@example.com")]),
        ])
        #expect(emails.display(of: list) == "a@example.com +2")
        #expect(emails.display(of: .array([Self.entry(["value": .string("a@example.com")])])) == "a@example.com")
    }

    // MARK: Page

    private static func personItem(_ properties: [String: PropertyValue]) -> MAPP.Item {
        MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID("core.entity.person"), title: "Ruth", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .now, modified: .now)
    }

    @Test func aPersonsPageShowsTheMainEmailPhoneAndAddress() {
        let item = Self.personItem([
            "emails": .array([Self.entry(["value": .string("main@example.com"), "label": .string("work")]), Self.entry(["value": .string("two@example.com")])]),
            "phones": .array([Self.entry(["value": .string("+44 20 7946 0000")])]),
            "addresses": .array([Self.entry(["label": .string("home"), "street_address": .string("1 High Street"), "locality": .string("London")])]),
        ])
        let lead = PageHeaderLead(for: item, kind: .person, body: nil, now: .now)
        let rows = lead.refine(PropertyRow.rows(
            of: item, type: Self.person, hidden: ["title"], relationships: [], parentField: "child-of", tags: []))
        #expect(rows.map(\.id) == ["emails", "phones", "addresses"])
        #expect(rows.map(\.value) == [.email("main@example.com"), .phone("+44 20 7946 0000"), .text("1 High Street, London (home)")])
    }

    @Test func aPersonWithNoEntriesHasNoRows() {
        let item = Self.personItem(["emails": .array([])])
        let rows = PropertyRow.rows(of: item, type: Self.person, hidden: ["title"], relationships: [], parentField: "child-of", tags: [])
        #expect(rows.isEmpty)
    }

    @Test func aDialableNumberIsToldFromOtherText() {
        for text in ["+44 20 7946 0000", "(555) 010-0199", "020.7946.0000"] { #expect(PageHeaderLead.isDialable(text), "\(text)") }
        for text in ["1 High Street", "a@example.com", "12", "Room 4B 12345", "https://example.com/12345"] { #expect(!PageHeaderLead.isDialable(text), "\(text)") }
    }

    // MARK: Media

    @Test func aMediaProgressIsAStatusAndItsRatingAFiveStepNumber() throws {
        let media = MarfaMapping.itemType(ItemType(
            id: "core.media", label: "Media",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: "core.media"),
                TypeField(name: "progress", type: "status", declaredBy: "core.media", definition: ["status_values": [
                    ["value": "wishlist", "group": "not_started"], ["value": "in_progress", "group": "in_progress"],
                    ["value": "finished", "group": "completed"],
                ]]),
                TypeField(name: "rating", type: "integer", declaredBy: "core.media", definition: ["minimum": 1, "maximum": 5]),
                TypeField(name: "kind", type: "enum", declaredBy: "core.media", definition: ["enum_values": ["book", "film", "game"]]),
            ], titleField: "title"))
        #expect(media.statusField?.key == "progress")
        #expect(media.statusField?.statusGroup(of: "finished") == .completed)
        let rating = try #require(media.fields.first { $0.key == "rating" })
        #expect(rating.numberRule.allows(5) && !rating.numberRule.allows(6))
        #expect(media.fields.first { $0.key == "kind" }?.kind == .choice(["book", "film", "game"]))
    }
}
