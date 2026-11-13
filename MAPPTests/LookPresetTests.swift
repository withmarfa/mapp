import Foundation
import Testing
@testable import MAPP

/// Which preset a type's fields suggest, and the look a preset gives a type from the fields it has.
struct LookPresetTests {
    private let catalogue = LookFixture.catalogue()
    private func field(_ key: String, _ kind: ItemTypeInfo.Field.Kind = .text, format: ItemTypeInfo.Field.TextFormat? = nil) -> ItemTypeInfo.Field {
        LookFixture.field(key, kind, format: format)
    }

    @Test(arguments: [
        ("core.task", LookPreset.task), ("core.event", .event), ("core.entity.person", .person), ("core.entity", .person),
        ("core.entity.place", .place), ("core.file.image", .media), ("core.file.webpage", .media), ("core.bookmark", .media),
        ("core.media.book", .media), ("core.media", .media), ("core.highlight", .quote), ("core.message", .message),
        ("core.note", .note), ("aic.ticket.task", .task), ("aic.ticket", .task), ("aic.agent.session", .event),
        ("aic.decision", .note),
    ])
    func aCoreTypeAndTheTypesBuiltOnItGetThePresetItsFieldsSuggest(type: String, preset: LookPreset) {
        #expect(LookPreset.suggested(for: TypeID(type), in: catalogue) == preset)
    }

    @Test func aPlaceGetsPlaceNotItsParentsPerson() {
        // The place carries the entity's emails and phones, which alone suggest Person.
        let place = TypeID("core.entity.place")
        #expect(catalogue.itemTypes[place]?.declares("emails") == true)
        #expect(LookPreset.suggested(for: place, in: catalogue) == .place)
    }

    @Test func mediaWithAProgressStatusIsMediaNotTask() {
        #expect(catalogue.itemTypes[TypeID("core.media")]?.statusField != nil)
        #expect(LookPreset.suggested(for: TypeID("core.media"), in: catalogue) == .media)
    }

    @Test func aTypeNoShippedTypeMatchesStillGetsItsPresetFromItsFields() {
        let clip = LookFixture.catalogue([LookFixture.make("acme.clip", [field("source_app"), field("copied_at", LookFixture.date)])])
        #expect(LookPreset.suggested(for: TypeID("acme.clip"), in: clip) == .clip)
        let invoice = LookFixture.catalogue([LookFixture.make("acme.invoice", [field("amount", .number), field("currency", format: .currency)])])
        #expect(LookPreset.suggested(for: TypeID("acme.invoice"), in: invoice) == .record)
        let workout = LookFixture.catalogue([LookFixture.make("acme.workout", [field("occurred_at", LookFixture.date), field("distance", .number)])])
        #expect(LookPreset.suggested(for: TypeID("acme.workout"), in: workout) == .record)
        let contact = LookFixture.catalogue([LookFixture.make("acme.contact", [field("emails", LookFixture.list)])])
        #expect(LookPreset.suggested(for: TypeID("acme.contact"), in: contact) == .person)
        let ticket = LookFixture.catalogue([LookFixture.make("acme.ticket", [field("state", LookFixture.status), field("project")])])
        #expect(LookPreset.suggested(for: TypeID("acme.ticket"), in: ticket) == .task)
    }

    @Test func aCurrencyAloneIsNotARecordAndNeitherIsANumberAlone() {
        let currencyOnly = LookFixture.catalogue([LookFixture.make("acme.price", [field("currency", format: .currency)])])
        #expect(LookPreset.suggested(for: TypeID("acme.price"), in: currencyOnly) == .note)
        let numberOnly = LookFixture.catalogue([LookFixture.make("acme.score", [field("points", .number)])])
        #expect(LookPreset.suggested(for: TypeID("acme.score"), in: numberOnly) == .note)
    }

    // MARK: What each preset fills

    private func look(_ type: String) -> TypeLook { catalogue.look(of: TypeID(type)) }

    @Test func eachCoreTypeFillsOnlyThePlacesItHasFieldsFor() {
        #expect(look("core.note") == TypeLook(date: .edited, secondary: [.opening], facts: [.tags]))
        #expect(look("core.message") == TypeLook(date: .created, secondary: [.field("from")], facts: []))
        #expect(look("core.task") == TypeLook(date: .field("due_at"), secondary: [], facts: [.field("priority"), .field("assignees")]))
        #expect(look("core.event") == TypeLook(
            date: .field("starts_at"), secondary: [.field("starts_at"), .field("place")], facts: [.field("attendees")]))
        #expect(look("core.entity.person") == TypeLook(
            date: .off, secondary: [.field("job_title"), .field("organization")], facts: [.field("emails")]))
        #expect(look("core.entity") == TypeLook(date: .off, secondary: [], facts: [.field("emails")]))
        #expect(look("core.entity.place") == TypeLook(
            date: .off, secondary: [.field("street_address"), .field("locality")], facts: []))
        #expect(look("core.bookmark") == TypeLook(date: .field("published_at"), secondary: [.site, .field("author")], facts: []))
        #expect(look("core.media.book") == TypeLook(date: .field("published_at"), secondary: [.site, .field("author")], facts: []))
        #expect(look("core.file.image") == TypeLook(date: .created, secondary: [.file, .field("author")], facts: []))
        #expect(look("core.file.video") == TypeLook(date: .created, secondary: [.file, .field("author")], facts: [.field("duration")]))
        #expect(look("core.highlight") == TypeLook(date: .created, secondary: [.field("text")], facts: [.field("start_location")]))
    }

    @Test func aTasksProjectOrRepositoryIsItsSecondaryLine() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.issue", [
            field("state", LookFixture.status), field("repository"), field("due_at", LookFixture.date), field("priority", .choice(["p1"])),
        ])])
        #expect(catalogue.look(of: TypeID("acme.issue")) == TypeLook(
            date: .field("due_at"), secondary: [.field("repository")], facts: [.field("priority")]))
    }

    @Test func aPersonReachedByEmailOrElseByPhone() {
        let phoneOnly = LookFixture.catalogue([LookFixture.make("acme.contact", [field("phones", LookFixture.list)])])
        #expect(phoneOnly.look(of: TypeID("acme.contact")).facts == [.field("phones")])
        let both = LookFixture.catalogue([LookFixture.make("acme.contact", [field("emails", LookFixture.list), field("phones", LookFixture.list)])])
        #expect(both.look(of: TypeID("acme.contact")).facts == [.field("emails")])
    }

    @Test func aRecordShowsItsNumbersWithTheCurrencyAfterTheFirst() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.txn", [
            field("category"), field("amount", .number), field("fee", .number), field("currency", format: .currency),
            field("occurred_at", LookFixture.date),
        ])])
        #expect(catalogue.look(of: TypeID("acme.txn")) == TypeLook(
            date: .field("occurred_at"), secondary: [.field("category")],
            facts: [.field("amount"), .field("currency"), .field("fee")]))
    }

    @Test func aClipShowsWhatWasCopiedAndTheAppItCameFrom() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.clip", [field("source_app"), field("copied_at", LookFixture.date)])])
        #expect(catalogue.look(of: TypeID("acme.clip")) == TypeLook(
            date: .field("copied_at"), secondary: [.opening], facts: [.field("source_app")]))
    }

    @Test func aDateFieldIsOnlyUsedWhereTheTypeKeepsADateInIt() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.task", [
            field("state", LookFixture.status), field("due_at", .text),
        ])])
        #expect(catalogue.look(of: TypeID("acme.task")).date == .edited)
    }

    // MARK: Ordinary failures

    @Test func aTypeWithNoneOfTheFieldsItsPresetExpectsHasEmptyPlacesNotPlaceholders() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.thing", [field("state", LookFixture.status)])])
        #expect(catalogue.look(of: TypeID("acme.thing")) == TypeLook(date: .edited, secondary: [], facts: []))
        let person = LookFixture.catalogue([LookFixture.make("acme.contact", [field("emails", LookFixture.list)])])
        #expect(person.look(of: TypeID("acme.contact")) == TypeLook(date: .off, secondary: [], facts: [.field("emails")]))
    }

    @Test func aTypeWithNoFieldsAtAllAndATypeTheCatalogueLacksTakeTheNoteLook() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.bare")])
        let note = TypeLook(date: .edited, secondary: [.opening], facts: [.tags])
        #expect(catalogue.look(of: TypeID("acme.bare")) == note)
        #expect(catalogue.look(of: TypeID("acme.unknown")) == note)
        #expect(Catalogue().look(of: TypeID("acme.unknown")) == note)
    }

    @Test func aSecondaryLineHasAtMostTwoParts() {
        let look = TypeLook(date: .off, secondary: [.opening, .site, .file], facts: [])
        #expect(look.secondary == [.opening, .site])
        #expect(TypeLookChoice(secondary: [.opening, .site, .file]).secondary == [.opening, .site])
    }
}
