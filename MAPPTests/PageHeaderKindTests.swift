import Foundation
import Marfa
import Testing
@testable import MAPP

struct PageHeaderKindTests {
    private static func type(_ id: String, parent: String? = nil) -> ItemTypeInfo {
        ItemTypeInfo(id: TypeID(id), label: id, fields: [], titleField: "title", bodyField: "body", parent: parent.map { TypeID($0) })
    }

    private static let catalogue = Catalogue(itemTypes: [
        type("core.note"), type("core.event"), type("core.entity.person"), type("core.bookmark"), type("core.media"),
        type("core.task"), type("core.file"), type("core.file.webpage", parent: "core.file"),
        type("aic.report", parent: "core.file.webpage"),
        type("aic.meeting", parent: "core.event"), type("aic.standup", parent: "aic.meeting"),
        type("aic.colleague", parent: "core.entity.person"), type("aic.clipping", parent: "core.bookmark"),
        type("aic.loop-a", parent: "aic.loop-b"), type("aic.loop-b", parent: "aic.loop-a"),
        type("aic.plain"),
    ])

    @Test func theCoreTypesChooseTheirHeaders() {
        func kind(_ id: String) -> PageHeaderKind { .of(TypeID(id), in: Self.catalogue) }
        #expect(kind("core.event") == .event)
        #expect(kind("core.entity.person") == .person)
        #expect(kind("core.bookmark") == .reading)
        #expect(kind("core.media") == .reading)
        #expect(kind("core.note") == .general)
        #expect(kind("core.task") == .general)
    }

    @Test func aWebPageAndTheTypesBuiltOnItHaveTheirOwnPage() {
        func kind(_ id: String) -> PageHeaderKind { .of(TypeID(id), in: Self.catalogue) }
        #expect(kind("core.file.webpage") == .webpage)
        #expect(kind("aic.report") == .webpage)
        #expect(kind("core.file") == .general)
    }

    @Test func aTypeTakesTheHeaderOfTheCoreTypeItBuildsOn() {
        func kind(_ id: String) -> PageHeaderKind { .of(TypeID(id), in: Self.catalogue) }
        #expect(kind("aic.meeting") == .event)
        #expect(kind("aic.standup") == .event)
        #expect(kind("aic.colleague") == .person)
        #expect(kind("aic.clipping") == .reading)
        #expect(kind("aic.plain") == .general)
    }

    @Test func aTypeNobodyKnowsAndALoopOfParentsAreGeneral() {
        #expect(PageHeaderKind.of(TypeID("aic.missing"), in: Self.catalogue) == .general)
        #expect(PageHeaderKind.of(TypeID("aic.loop-a"), in: Self.catalogue) == .general)
    }

    // MARK: Person

    private static func item(_ type: String, title: String = "Title", _ properties: [String: PropertyValue] = [:]) -> MAPP.Item {
        MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID(type), title: title, titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .distantPast, modified: .distantPast)
    }

    @Test func initialsComeFromTheFirstAndLastName() {
        #expect(PersonHeader.initials(of: ["Ruth", "Okonjo"]) == "RO")
        #expect(PersonHeader.initials(of: ["Cher"]) == "C")
        #expect(PersonHeader.initials(of: ["ada", "king", "lovelace"]) == "AL")
        #expect(PersonHeader.initials(of: []) == "")
        #expect(PersonHeader.initials(of: ["(", "Ruth"]) == "R")
    }

    @Test func aPersonHasInitialsASubtitleAndAPictureOnlyIfItIsInline() {
        let person = PersonHeader(item: Self.item("core.entity.person", title: "Ruth Okonjo", [
            "job_title": .string("Editor"), "organization": .string("Okonjo Press"), "thumbnail": .string("data:image/png;base64,AA==")
        ]))
        #expect(person.initials == "RO")
        #expect(person.subtitle == "Editor, Okonjo Press")
        #expect(person.photo == "data:image/png;base64,AA==")

        let remote = PersonHeader(item: Self.item("core.entity.person", title: "Ruth Okonjo", [
            "thumbnail": .string("https://example.com/ruth.png")
        ]))
        #expect(remote.photo == nil)
        #expect(remote.subtitle == nil)

        let named = PersonHeader(item: Self.item("core.entity.person", title: "Someone", [
            "given_name": .string("Ruth"), "family_name": .string("Okonjo"), "organization": .string("Okonjo Press")
        ]))
        #expect(named.initials == "RO")
        #expect(named.subtitle == "Okonjo Press")
    }

    @Test func aPersonsNumberToCallIsALinkWhateverTheFieldIsCalled() {
        let item = Self.item("core.entity.person", title: "Ruth Okonjo", [:])
        let lead = PageHeaderLead(for: item, kind: .person, now: .now, format: .automatic)
        let rows = [
            PropertyRow(id: "mobiles", label: "Mobiles", value: .text("+44 20 7946 0000, work"), numberToCall: "+44 20 7946 0000"),
            PropertyRow(id: "mail", label: "Mail", value: .email("a@example.com")),
            // A key called "phone" is not taken for a number: only what the list's definition allows is.
            PropertyRow(id: "phone", label: "Phone", value: .text("+44 20 7946 0000")),
        ]
        #expect(lead.refine(rows).map(\.value) == [.phone("+44 20 7946 0000"), .email("a@example.com"), .text("+44 20 7946 0000")])
        let general = PageHeaderLead(for: item, kind: .general, now: .now, format: .automatic)
        #expect(general.refine(rows) == rows)
    }

    // MARK: Reading

    @Test func aReadingItemsDescriptionIsItsDekAndTheSourceAndTheDayAreLeftAsProperties() {
        let item = Self.item("core.bookmark", [
            "published_at": .string("2025-10-02"), "description": .string("  Why startups fail  "), "url": .string("https://example.com"),
            "publisher": .string("YC"), "source_title": .string("Y Combinator Blog"), "image_url": .string("https://example.com/a.png"),
        ])
        let lead = PageHeaderLead(for: item, kind: .reading, now: .now, format: .automatic)
        #expect(lead.subtitle == "Why startups fail")
        // The page draws the description, and loads no picture; every other property is a property.
        #expect(lead.consumed == ["description", "image_url"])
    }

    @Test func aPinNeverRepeatsWhatTheHeaderDrawsItself() {
        func consumed(_ type: String, _ kind: PageHeaderKind, _ properties: [String: PropertyValue] = [:]) -> Set<String> {
            PageHeaderLead(for: Self.item(type, properties), kind: kind, now: .now, format: .automatic).consumed
        }
        // A general page draws nothing of its own, so every pin shows.
        #expect(consumed("aic.plain", .general).isEmpty)
        // An event draws its time, and a person their work: each says only what it draws.
        #expect(consumed("core.event", .event, ["starts_at": .string("2026-10-29T10:00:00Z")]) == EventHeader.keys)
        #expect(consumed("core.entity.person", .person) == PersonHeader.keys)
        // A page for reading names its type, source and last edit like any other page.
        #expect(consumed("core.bookmark", .reading) == ReadingHeader.keys)
    }

    @Test func onlyAWebAddressCanBeOpened() {
        #expect(ReadingHeader.webAddress("https://example.com/a")?.host() == "example.com")
        #expect(ReadingHeader.webAddress("javascript:alert(1)") == nil)
        #expect(ReadingHeader.webAddress("file:///etc/passwd") == nil)
        #expect(ReadingHeader.webAddress("not a url") == nil)
        #expect(ReadingHeader.webAddress(nil) == nil)
    }
}
