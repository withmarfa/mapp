import Foundation
import Testing
@testable import MarfaMac

/// Which listed items the map places and which it counts as having no location: a mistake here would hide an item.
struct MapLayoutTests {
    private static let catalogue = LookFixture.catalogue()

    private static func number(_ text: String) -> PropertyValue { .number(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!) }

    private static func item(_ id: Int, _ type: String, _ values: [String: PropertyValue] = [:]) -> Item {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return Item(
            id: ItemID("10000000-0000-0000-0000-\(String(format: "%012d", id))"), type: TypeID(type), title: "Item \(id)", name: "Item \(id)",
            titleRule: .property("title"), properties: values.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: date,
            modified: date)
    }

    @Test func onlyAnItemWithBothCoordinatesOnEarthStandsOnTheMap() {
        let items = [
            Self.item(1, "core.event", ["latitude": Self.number("51.5246"), "longitude": Self.number("-0.0788")]),
            Self.item(2, "core.event", ["latitude": Self.number("51.5246")]),
            Self.item(3, "core.event", ["latitude": Self.number("91"), "longitude": Self.number("0")]),
            Self.item(4, "core.event", ["latitude": Self.number("10"), "longitude": Self.number("181")]),
            Self.item(5, "core.event"),
            Self.item(6, "core.note"),
            Self.item(7, "core.entity.place", ["latitude": Self.number("-33.8688"), "longitude": Self.number("151.2093")]),
        ]
        let placing = MapLayout.placing(for: items, catalogue: Self.catalogue)
        #expect(placing.pins.map(\.id) == [items[0].id, items[6].id])
        // Everything else is counted, in the order listed, so the pill opens the same items it counts.
        #expect(placing.unplaced == items[1...5].map(\.id))
        #expect(placing.pins.count + placing.unplaced.count == items.count)
    }

    @Test func aPlaceOfItemsWithNoPointHasNoMapToShow() {
        let items = [Self.item(1, "core.note"), Self.item(2, "core.event")]
        #expect(!MapLayout.canPlace(types: [TypeID("core.note")], catalogue: Self.catalogue))
        #expect(MapLayout.canPlace(types: [TypeID("core.note"), TypeID("core.event")], catalogue: Self.catalogue))
        let placing = MapLayout.placing(for: items, catalogue: Self.catalogue)
        #expect(placing.pins.isEmpty && placing.unplaced.count == 2)
        #expect(placing.frame == .world)
    }
}
