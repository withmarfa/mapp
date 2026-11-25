import Foundation
import Marfa
import Testing
@testable import MarfaMac

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

    @Test func anArrayOfStringsIsAListOfWordsAndOneOfAnythingElseIsLeftAlone() {
        let tags = TypeField(name: "tags", type: "array", declaredBy: "t", definition: ["items_type": "string"])
        #expect(MarfaMapping.itemType(ItemType(id: "t", label: "T", fields: [tags])).fields.first?.kind == .words)
        let numbers = TypeField(name: "sizes", type: "array", declaredBy: "t", definition: ["items_type": "number"])
        #expect(MarfaMapping.itemType(ItemType(id: "t", label: "T", fields: [numbers])).fields.first?.kind == .other)
    }

    @Test func aListFieldCarriesItsLimitAndTakesNoMoreThanItDeclares() throws {
        let tags = TypeField(name: "sites", type: "array", declaredBy: "t", definition: ["items_type": "url", "maxItems": 2])
        let field = try #require(MarfaMapping.itemType(ItemType(id: "t", label: "T", fields: [tags])).fields.first)
        #expect(field.maxItems == 2)
        #expect(field.accepts(.array([.string("a"), .string("b")])))
        #expect(!field.accepts(.array([.string("a"), .string("b"), .string("c")])))
        let free = TypeField(name: "sites", type: "array", declaredBy: "t", definition: ["items_type": "url"])
        #expect(MarfaMapping.itemType(ItemType(id: "t", label: "T", fields: [free])).fields.first?.maxItems == nil)
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
        // Marfa refuses a stored entry that lacks a required member, so the app does not take it either.
        #expect(!shape.accepts(Self.entry(["label": .string("work")])))
    }

    @Test func aMemberTheListDoesNotDeclareIsRefusedByName() throws {
        let shape = try Self.shape(Self.emails)
        let refusal = try #require(shape.refusal(of: ["value": .string("a@example.com"), "kind": .string("x")]))
        #expect(refusal.contains("kind"))
    }

    @Test func anEntryBeingAddedIsRefusedForABadValueButNotForWhatIsNotYetFilledIn() throws {
        let scores = try Self.shape(Self.scores)
        #expect(scores.refusal(of: [:], ignoringMissingRequired: true) == nil)
        #expect(scores.refusal(of: ["points": .number(9)], ignoringMissingRequired: true) == "Enter a whole number from 1 to 5.")
        let emails = try Self.shape(Self.emails)
        #expect(emails.refusal(of: ["label": .string("work")], ignoringMissingRequired: true) == nil)
        #expect(emails.refusal(of: ["label": .string("work")]) != nil)
    }

    @Test func aStoredListMarfaRefusesIsCountedAndFlagged() throws {
        let shape = try Self.shape(Self.emails)
        let good = Self.entry(["value": .string("a@example.com")])
        #expect(shape.faults(in: [good]) == 0)
        #expect(shape.faults(in: [good, .string("b@example.com")]) == 1)
        #expect(shape.faults(in: [Self.entry(["value": .string("a@example.com"), "kind": .string("x"), "extra": .bool(true)])]) == 2)
        #expect(shape.faults(in: [Self.entry(["label": .string("work")])]) == 1)
        #expect(shape.fault(of: .string("b@example.com")) != nil)
        #expect(shape.fault(of: good) == nil)
        // The row's "Unrecognized value" check reads the field's acceptance.
        let field = try #require(MarfaMapping.itemType(ItemType(id: "t", label: "T", fields: [Self.emails])).fields.first)
        #expect(field.accepts(.array([good])))
        #expect(!field.accepts(.array([good, .string("b@example.com")])))
        #expect(!field.accepts(.array([Self.entry(["value": .string("a@example.com"), "kind": .string("x")])])))
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

    /// A number beyond Decimal's range is judged as the Double it is stored as, against the same bounds.
    @Test func aNumberBeyondDecimalsRangeIsJudgedByTheFieldsBounds() {
        let rating = ItemTypeInfo.Field(
            key: "rating", label: "Rating", kind: .number, declaredBy: TypeID("core.media"), isInteger: true,
            minimum: 1, maximum: 5)
        #expect(!rating.accepts(.double(1e200)))
        #expect(!rating.accepts(.double(1e-200)))
        let open = NumberRule(minimum: 0)
        #expect(open.allows(stored: 1e200) && open.allows(stored: 1e-200) && !open.allows(stored: -1e200))
        #expect(NumberRule(integer: true).allows(stored: 1e200) && !NumberRule(integer: true).allows(stored: 1e-200))
    }

    @Test func aTypeChangeKeepsOnlyANumberTheNewFieldTakes() {
        let rating = ItemTypeInfo.Field(
            key: "rating", label: "Rating", kind: .number, declaredBy: TypeID("core.media"), isInteger: true,
            minimum: 1, maximum: 5)
        #expect(rating.accepts(.number(4)))
        #expect(!rating.accepts(.number(9)))
        #expect(!rating.accepts(.number(Decimal(string: "2.5")!)))
    }

    // MARK: Page

    private static func personItem(_ properties: [String: PropertyValue]) -> MarfaMac.Item {
        MarfaMac.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID("core.entity.person"), title: "Ruth", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .now, modified: .now)
    }

    @Test func aLabelledNumberIsStillANumberToCall() {
        let item = Self.personItem(["phones": .array([Self.entry(["value": .string("+44 20 7946 0000"), "label": .string("work")])])])
        let rows = PropertyRow.candidates(
            of: item, type: Self.person, hidden: ["title"], links: [], format: .standard, tags: [], icon: { _ in nil }, isPerson: { _ in false })
        #expect(rows.first { $0.id == "phones" }?.value == .phone("+44 20 7946 0000"))
    }

    @Test func anAddressOfOnlyAPostcodeIsNeverANumberToCall() throws {
        let postcodes = Self.listField("addresses", ["label": ["type": "string"], "postal_code": ["type": "string"]])
        let person = MarfaMapping.itemType(ItemType(
            id: "core.entity.person", label: "Person", fields: [TypeField(name: "title", type: "string", declaredBy: "core.entity"), postcodes],
            titleField: "title"))
        let item = Self.personItem(["addresses": .array([Self.entry(["postal_code": .string("90210 12345")])])])
        let rows = PropertyRow.candidates(
            of: item, type: person, hidden: ["title"], links: [], format: .standard, tags: [], icon: { _ in nil }, isPerson: { _ in false })
        #expect(rows.first?.value == .text("90210 12345"))
        // Only a list whose first member is required plain text holds a number to call, and only in that member.
        #expect(try Self.shape(postcodes).numberToCall(in: ["postal_code": .string("90210 12345")]) == nil)
        #expect(try Self.shape(Self.phones).numberToCall(in: ["value": .string("Reception"), "label": .string("0207 946 0000")]) == nil)
        #expect(try Self.shape(Self.emails).numberToCall(in: ["value": .string("12345@example.com")]) == nil)
    }

    // MARK: People

    private static let assignees = listField("assignees", ["name": ["type": "string"], "email": ["type": "email"]])

    @Test func aDialableNumberIsToldFromOtherText() {
        for text in ["+44 20 7946 0000", "(555) 010-0199", "020.7946.0000"] { #expect(ListShape.isDialable(text), "\(text)") }
        for text in ["1 High Street", "a@example.com", "12", "Room 4B 12345", "https://example.com/12345"] { #expect(!ListShape.isDialable(text), "\(text)") }
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
