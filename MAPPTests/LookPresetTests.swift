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
        ("aic.decision", .note), ("acme.repository", .note),
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

    @Test func aChildOfAnEntityThatOnlyInheritsEmailsAndPhonesIsNotAPerson() {
        let repository = TypeID("acme.repository")
        let info = catalogue.itemTypes[repository]
        #expect(info?.declares("emails") == true)
        #expect(info?.fields.first { $0.key == "emails" }?.declaredBy == TypeID("core.entity"))
        #expect(LookPreset.suggested(for: repository, in: catalogue) == .note)
        #expect(LookPreset.suggested(for: TypeID("core.entity.place"), in: catalogue) == .place)
        // The organization declares them itself.
        #expect(catalogue.itemTypes[TypeID("core.entity")]?.fields.first { $0.key == "emails" }?.declaredBy == TypeID("core.entity"))
        #expect(LookPreset.suggested(for: TypeID("core.entity"), in: catalogue) == .person)
    }

    @Test func aChildThatDeclaresItsOwnEmailsOrPhonesIsAPerson() {
        for key in ["emails", "phones"] {
            let catalogue = LookFixture.catalogue([
                LookFixture.make("acme.org", [field("name")]),
                LookFixture.make("acme.org.team", parent: "acme.org", [field(key, LookFixture.list)]),
            ])
            #expect(LookPreset.suggested(for: TypeID("acme.org.team"), in: catalogue) == .person)
            #expect(LookPreset.suggested(for: TypeID("acme.org"), in: catalogue) == .note)
        }
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
        let contact = LookFixture.catalogue([LookFixture.make("acme.contact", [field("emails", LookFixture.list)])])
        #expect(LookPreset.suggested(for: TypeID("acme.contact"), in: contact) == .person)
        let ticket = LookFixture.catalogue([LookFixture.make("acme.ticket", [field("state", LookFixture.status), field("project")])])
        #expect(LookPreset.suggested(for: TypeID("acme.ticket"), in: ticket) == .task)
    }

    @Test func aRecordIsToldByItsCurrencyNumberAlone() {
        // `occurred_at` is Marfa's own on every item, so a type cannot declare it and it tells nothing.
        let workout = LookFixture.catalogue([LookFixture.make("acme.workout", [field("occurred_at", LookFixture.date), field("distance", .number)])])
        #expect(LookPreset.suggested(for: TypeID("acme.workout"), in: workout) == .note)
    }

    @Test func aCurrencyAloneIsNotARecordAndNeitherIsANumberAlone() {
        let currencyOnly = LookFixture.catalogue([LookFixture.make("acme.price", [field("currency", format: .currency)])])
        #expect(LookPreset.suggested(for: TypeID("acme.price"), in: currencyOnly) == .note)
        let numberOnly = LookFixture.catalogue([LookFixture.make("acme.score", [field("points", .number)])])
        #expect(LookPreset.suggested(for: TypeID("acme.score"), in: numberOnly) == .note)
    }

    // MARK: What each preset fills

    private func look(_ type: String) -> TypeLook { LookFixture.look(type, in: catalogue) }

    @Test func eachCoreTypeFillsOnlyThePlacesItHasFieldsFor() {
        #expect(look("core.note") == TypeLook(date: .edited, secondary: [.opening], facts: [.tags]))
        #expect(look("core.message") == TypeLook(date: .occurred, secondary: [.field("from")], facts: []))
        #expect(look("core.task") == TypeLook(date: .field("due_at"), secondary: [], facts: [.field("priority"), .field("assignees")]))
        #expect(look("core.event") == TypeLook(
            date: .field("starts_at"), secondary: [.time("starts_at"), .field("place")], facts: [.field("attendees")]))
        #expect(look("core.entity.person") == TypeLook(
            date: .off, secondary: [.field("job_title"), .field("organization")], facts: [.field("emails")]))
        #expect(look("core.entity") == TypeLook(date: .off, secondary: [], facts: [.field("emails")]))
        #expect(look("core.entity.place") == TypeLook(
            date: .off, secondary: [.field("street_address"), .field("locality")], facts: []))
        #expect(look("core.bookmark") == TypeLook(date: .field("published_at"), secondary: [.site, .field("author")], facts: []))
        #expect(look("core.media.book") == TypeLook(date: .field("published_at"), secondary: [.site, .field("author")], facts: []))
        #expect(look("core.file.image") == TypeLook(date: .created, secondary: [.file, .field("author")], facts: []))
        #expect(look("core.file.video") == TypeLook(date: .created, secondary: [.file, .field("author")], facts: [.field("duration")]))
        #expect(look("core.highlight") == TypeLook(date: .occurred, secondary: [.field("text")], facts: [.field("start_location")]))
        #expect(look("acme.repository") == TypeLook(date: .edited, secondary: [.opening], facts: [.tags]))
    }

    @Test func aTasksProjectOrRepositoryIsItsSecondaryLine() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.issue", [
            field("state", LookFixture.status), field("repository"), field("due_at", LookFixture.date), field("priority", .choice(["p1"])),
        ])])
        #expect(LookFixture.look("acme.issue", in: catalogue) == TypeLook(
            date: .field("due_at"), secondary: [.field("repository")], facts: [.field("priority")]))
    }

    @Test func aPersonReachedByEmailOrElseByPhone() {
        let phoneOnly = LookFixture.catalogue([LookFixture.make("acme.contact", [field("phones", LookFixture.list)])])
        #expect(LookFixture.look("acme.contact", in: phoneOnly).facts == [.field("phones")])
        let both = LookFixture.catalogue([LookFixture.make("acme.contact", [field("emails", LookFixture.list), field("phones", LookFixture.list)])])
        #expect(LookFixture.look("acme.contact", in: both).facts == [.field("emails")])
    }

    @Test func aRecordShowsItsNumbersWithTheCurrencyAfterTheFirst() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.txn", [
            field("category"), field("amount", .number), field("fee", .number), field("currency", format: .currency),
        ])])
        #expect(LookFixture.look("acme.txn", in: catalogue) == TypeLook(
            date: .occurred, secondary: [.field("category")],
            facts: [.field("amount"), .field("currency"), .field("fee")]))
    }

    @Test func aClipShowsWhatWasCopiedAndTheAppItCameFrom() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.clip", [field("source_app"), field("copied_at", LookFixture.date)])])
        #expect(LookFixture.look("acme.clip", in: catalogue) == TypeLook(
            date: .occurred, secondary: [.opening], facts: [.field("source_app")]))
    }

    @Test func aDateFieldIsOnlyUsedWhereTheTypeKeepsADateInIt() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.task", [
            field("state", LookFixture.status), field("due_at", .text),
        ])])
        #expect(LookFixture.look("acme.task", in: catalogue).date == .edited)
    }

    // MARK: Ordinary failures

    @Test func aTypeWithNoneOfTheFieldsItsPresetExpectsHasEmptyPlacesNotPlaceholders() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.thing", [field("state", LookFixture.status)])])
        #expect(LookFixture.look("acme.thing", in: catalogue) == TypeLook(date: .edited, secondary: [], facts: []))
        let person = LookFixture.catalogue([LookFixture.make("acme.contact", [field("emails", LookFixture.list)])])
        #expect(LookFixture.look("acme.contact", in: person) == TypeLook(date: .off, secondary: [], facts: [.field("emails")]))
    }

    @Test func aTypeWithNoFieldsAtAllTakesTheNoteLookAndATypeTheCatalogueLacksIsANote() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.bare")])
        let note = TypeLook(date: .edited, secondary: [.opening], facts: [.tags])
        #expect(LookFixture.look("acme.bare", in: catalogue) == note)
        #expect(LookPreset.suggested(for: TypeID("acme.unknown"), in: catalogue) == .note)
        #expect(Catalogue().looks().isEmpty, "a type the catalogue lacks has no entry")
    }

    // MARK: Dates and times

    @Test func quoteClipRecordAndMessageShowWhenTheItemHappened() {
        let catalogue = LookFixture.catalogue(LookFixture.specs + [
            LookFixture.make("acme.clip", [field("source_app")]),
            LookFixture.make("acme.txn", [field("amount", .number), field("currency", format: .currency)]),
        ])
        for type in ["acme.clip", "acme.txn", "core.message", "core.highlight"] {
            #expect(LookFixture.look(type, in: catalogue).date == .occurred, "\(type)")
        }
    }

    @Test func aTimeIsOnlyOfferedForADateFieldThatIncludesATime() {
        let catalogue = LookFixture.catalogue([LookFixture.make("acme.meeting", [
            field("starts_at", LookFixture.date), field("day", LookFixture.day), field("name"),
        ])])
        let surface = LookSurface(TypeID("acme.meeting"), in: catalogue)
        #expect(surface.offers(LookPart.time("starts_at")))
        #expect(!surface.offers(LookPart.time("day")))
        #expect(!surface.offers(LookPart.time("name")))
        #expect(!surface.offers(LookPart.time("nope")))
        let fitted = surface.fitting(
            TypeLook(date: .off, secondary: [.time("day"), .time("starts_at")], facts: []), fallback: .off)
        #expect(fitted.secondary == [.time("starts_at")])
    }

    @Test func anEventWhoseStartIsADayHasNoTimePartAndSecondaryIsItsPlace() {
        let catalogue = LookFixture.catalogue([LookFixture.make("core.event", [field("starts_at", LookFixture.day), field("place")])])
        #expect(LookFixture.look("core.event", in: catalogue) == TypeLook(
            date: .field("starts_at"), secondary: [.field("place")], facts: []))
    }

    @Test func aSecondaryLineHasAtMostTwoParts() {
        let look = TypeLook(date: .off, secondary: [.opening, .site, .file], facts: [])
        #expect(look.secondary == [.opening, .site])
        #expect(TypeLookChoice(secondary: [.opening, .site, .file]).secondary == [.opening, .site])
    }
}
