import Foundation
import Marfa
import Testing
@testable import MarfaMac

struct PageHeaderKindTests {
    // MARK: Person

    private static func item(_ type: String, title: String = "Title", _ properties: [String: PropertyValue] = [:]) -> MarfaMac.Item {
        MarfaMac.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID(type), title: title, titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .distantPast, modified: .distantPast)
    }

    @Test func aPersonsNumberToCallIsALinkWhateverTheFieldIsCalled() {
        let item = Self.item("core.entity.person", title: "Ruth Okonjo", [:])
        let lead = PageHeaderLead(for: item, kind: .person, now: .now)
        let rows = [
            PropertyRow(id: "mobiles", label: "Mobiles", value: .text("+44 20 7946 0000, work"), numberToCall: "+44 20 7946 0000"),
            PropertyRow(id: "mail", label: "Mail", value: .email("a@example.com")),
            // A key called "phone" is not taken for a number: only what the list's definition allows is.
            PropertyRow(id: "phone", label: "Phone", value: .text("+44 20 7946 0000")),
        ]
        #expect(lead.refine(rows).map(\.value) == [.phone("+44 20 7946 0000"), .email("a@example.com"), .text("+44 20 7946 0000")])
        let general = PageHeaderLead(for: item, kind: .general, now: .now)
        #expect(general.refine(rows) == rows)
    }

    // MARK: Reading

    @Test func onlyAWebAddressCanBeOpened() {
        #expect(ReadingHeader.webAddress("https://example.com/a")?.host() == "example.com")
        #expect(ReadingHeader.webAddress("javascript:alert(1)") == nil)
        #expect(ReadingHeader.webAddress("file:///etc/passwd") == nil)
        #expect(ReadingHeader.webAddress("not a url") == nil)
        #expect(ReadingHeader.webAddress(nil) == nil)
    }
}
