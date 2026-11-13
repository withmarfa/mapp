import Foundation
import Testing
@testable import MAPP

/// Where Location stands on the page and in the property block: one row in place of the numbers, and the numbers back
/// as rows of their own with Show Coordinates on.
struct LocationPageTests {
    private static let catalogue = LookFixture.catalogue()
    private static let now = Date(timeIntervalSince1970: 1_700_100_000)

    private static func item(_ type: String, _ values: [String: PropertyValue]) -> Item {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID(type), title: "Brat", name: "Brat", titleRule: .property("title"),
            properties: values.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: date, modified: date)
    }

    private static let london: [String: PropertyValue] = [
        "latitude": .number(Decimal(string: "51.5246", locale: Locale(identifier: "en_US_POSIX"))!),
        "longitude": .number(Decimal(string: "-0.0788", locale: Locale(identifier: "en_US_POSIX"))!),
        "place": .string("Brat"),
    ]

    private static func candidates(_ item: Item, showsCoordinates: Bool = false, offersEmpty: Bool = false) -> [PropertyRow] {
        PropertyRow.candidates(
            of: item, type: catalogue.itemTypes[item.type], hidden: ["title", "body"], relationships: [], parentField: "child-of",
            format: .automatic, tags: [], typeLabel: nil, typeIcon: nil, sourceName: nil, now: now, calendar: .current,
            locale: Locale(identifier: "en_GB"), offersEmpty: offersEmpty, showsCoordinates: showsCoordinates, icon: { _ in nil },
            isPerson: { _ in false })
    }

    @Test func theNumbersAndThePlaceAreOneLocationRow() throws {
        let rows = Self.candidates(Self.item("core.event", Self.london))
        #expect(!rows.contains { ["latitude", "longitude", "place"].contains($0.id) })
        let location = try #require(rows.first { $0.id == "#location" })
        #expect(location.value == .text("Brat"))
        #expect(location.symbolName == ItemLocation.symbol)
        #expect(location.editable)
    }

    @Test func showCoordinatesBringsTheNumbersBackAsRowsOfTheirOwn() {
        let rows = Self.candidates(Self.item("core.event", Self.london), showsCoordinates: true)
        #expect(rows.contains { $0.id == "latitude" } && rows.contains { $0.id == "longitude" })
        #expect(rows.contains { $0.id == "#location" })
        #expect(!rows.contains { $0.id == "place" })
    }

    @Test func anItemWithNoLocationHasNoRowUnlessTheEmptyOneIsOffered() {
        let item = Self.item("core.event", [:])
        #expect(!Self.candidates(item).contains { $0.id == "#location" })
        #expect(Self.candidates(item, offersEmpty: true).contains { $0.id == "#location" })
    }

    @Test func aTypeWithOneNumberKeepsItAsAnOrdinaryRow() {
        let rows = Self.candidates(Self.item("core.file.video", ["latitude": .number(5)]))
        #expect(rows.contains { $0.id == "latitude" })
        #expect(!rows.contains { $0.id == "#location" })
    }

    @Test func customizeLayoutOffersOneLocationInPlaceOfTheNumbers() throws {
        let item = Self.item("core.event", Self.london)
        let type = Self.catalogue.itemTypes[item.type]
        let hidden = PageLayout.rows(of: item, type: type, hidden: [], relationships: [], catalogue: Self.catalogue).map(\.id)
        #expect(hidden.filter { $0 == "#location" }.count == 1)
        #expect(!hidden.contains("latitude") && !hidden.contains("longitude") && !hidden.contains("place"))
        let shown = PageLayout.rows(of: item, type: type, hidden: [], relationships: [], catalogue: Self.catalogue, showsCoordinates: true).map(\.id)
        #expect(shown.contains("latitude") && shown.contains("longitude") && shown.contains("#location"))
    }

    @MainActor @Test func showCoordinatesIsOffUntilTheStoredSettingSaysOtherwise() throws {
        let suite = "LocationPageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!ShowsCoordinates.stored(in: defaults))
        defaults.set(true, forKey: PageKey.showsCoordinates)
        #expect(ShowsCoordinates.stored(in: defaults))
    }
}
