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

    @Test func aPersonsPhoneNumberIsANumberToCall() {
        let item = Self.item("core.entity.person", title: "Ruth Okonjo", ["phone": .string("+44 20 7946 0000")])
        let lead = PageHeaderLead(for: item, kind: .person, body: nil, now: .now)
        let rows = [PropertyRow(id: "phone", label: "Phone", value: .text("+44 20 7946 0000")), PropertyRow(id: "x", label: "X", value: .text("1"))]
        #expect(lead.refine(rows).map(\.value) == [.phone("+44 20 7946 0000"), .text("1")])
        #expect(lead.consumed == PersonHeader.keys)
        let general = PageHeaderLead(for: item, kind: .general, body: nil, now: .now)
        #expect(general.refine(rows) == rows)
    }

    // MARK: Reading

    @Test func readingTimeIsCountedFromTheWordsOfTheBody() {
        #expect(ReadingHeader.minutes(words: 1) == 1)
        #expect(ReadingHeader.minutes(words: 220) == 1)
        #expect(ReadingHeader.minutes(words: 221) == 2)
        #expect(ReadingHeader.minutes(words: 1_320) == 6)
        let body = "# Title\n\nSome **words** and a [link](https://example.com/a/very/long/address) and ![alt](img.png) <b>bold</b> --- 42"
        // Title, Some, words, and, a, link, and, bold, 42 (the rule and the addresses are not words).
        #expect(ReadingHeader.words(in: body) == 10 - 1)
        // Markup is read as it is written: an image's label can run over lines, a link's text stays, and what never
        // closes is text.
        #expect(ReadingHeader.words(in: "![a label\nover lines](img.png)") == 0)
        #expect(ReadingHeader.words(in: "[one](a)two [three](b)") == 3)
        #expect(ReadingHeader.words(in: "<p class=\"x\">text</p>") == 1)
        #expect(ReadingHeader.words(in: "unclosed <tag and ](x and ![y](z") == 6)
        #expect(ReadingHeader.words(in: "Caf\u{E9} \u{1F600} 42") == 2)
    }

    @Test func aShortClippingHasNoReadingTime() {
        let item = Self.item("core.bookmark", ["url": .string("https://www.ycombinator.com/blog/x")])
        #expect(ReadingHeader(item: item, body: "A few words.").byline.detail == nil)
        let long = String(repeating: "word ", count: 1_320)
        #expect(ReadingHeader(item: item, body: long, locale: Locale(identifier: "en_GB")).byline.detail == "6 min read")
        #expect(ReadingHeader(item: item, body: nil).byline.detail == nil)
    }

    @Test func theSourceIsNamedBeforeThePublisherBeforeTheHost() {
        let url: [String: PropertyValue] = ["url": .string("https://www.ycombinator.com/blog/x")]
        #expect(ReadingHeader(item: Self.item("core.bookmark", url), body: nil).byline.source == "ycombinator.com")
        #expect(ReadingHeader(item: Self.item("core.bookmark", url.merging(["publisher": .string("YC")]) { $1 }), body: nil).byline.source == "YC")
        let both = url.merging(["publisher": .string("YC"), "source_title": .string("Y Combinator Blog")]) { $1 }
        #expect(ReadingHeader(item: Self.item("core.bookmark", both), body: nil).byline.source == "Y Combinator Blog")
    }

    @Test func thePublishedDateAndTheDekComeFromTheItem() {
        let item = Self.item("core.bookmark", [
            "published_at": .string("2025-10-02"), "description": .string("  Why startups fail  "), "url": .string("https://example.com")
        ])
        let reading = ReadingHeader(item: item, body: nil, locale: Locale(identifier: "en_GB"), calendar: Self.utc)
        #expect(reading.byline.date == "2 Oct 2025")
        #expect(reading.dek == "Why startups fail")
        #expect(PageHeaderLead(for: item, kind: .reading, body: nil, now: .now).showsType == false)
    }

    @Test func onlyAWebAddressCanBeOpened() {
        #expect(ReadingHeader.webAddress("https://example.com/a")?.host() == "example.com")
        #expect(ReadingHeader.webAddress("javascript:alert(1)") == nil)
        #expect(ReadingHeader.webAddress("file:///etc/passwd") == nil)
        #expect(ReadingHeader.webAddress("not a url") == nil)
        #expect(ReadingHeader.webAddress(nil) == nil)
    }

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
