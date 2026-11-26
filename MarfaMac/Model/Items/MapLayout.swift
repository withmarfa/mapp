import Foundation
import MapKit
import Marfa

/// How an Apple map draws, as the View panel's Style chooses.
nonisolated enum ItemMapStyle: String, Codable, CaseIterable, Sendable {
    case standard, satellite, hybrid

    var title: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .satellite: String(localized: "Satellite")
        case .hybrid: String(localized: "Hybrid")
        }
    }
}

/// What a view keeps of its map: its Style and whether markers that crowd are grouped. Nil members follow the default,
/// which is the standard style with groups.
nonisolated struct MapChoices: Codable, Hashable, Sendable {
    var style: ItemMapStyle?
    var groupsNearby: Bool?

    init(style: ItemMapStyle? = nil, groupsNearby: Bool? = nil) {
        self.style = style
        self.groupsNearby = groupsNearby
    }

    /// A style a later version adds reads as the default, and never voids the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try? container.decodeIfPresent(ItemMapStyle.self, forKey: .style)
        groupsNearby = try? container.decodeIfPresent(Bool.self, forKey: .groupsNearby)
    }

    var isEmpty: Bool { self == MapChoices() }
}

/// Where a place's items stand on a map: those whose type has coordinates (`ItemLocation`) and whose two numbers name a
/// point on Earth are placed, and every other item is counted as having no location. Pure, so a large place is worked out
/// off the main actor.
nonisolated enum MapLayout {
    /// One placed item.
    struct Pin: Hashable, Sendable {
        let id: ItemID
        let type: TypeID
        let title: String
        /// The address or place name the item holds, when it holds one.
        let subtitle: String?
        let point: LocationPoint
    }

    struct Placing: Sendable {
        let pins: [Pin]
        /// The listed items the map cannot place, in the order they were listed.
        let unplaced: [ItemID]
        let pinsByID: [ItemID: Pin]
        /// Tells one answer from the next, so a view redraws the markers only for a new one.
        let serial = UUID()
        /// The stretch of the world that holds every marker: where the map opens and what Fit shows.
        let mapRect: MKMapRect

        init(pins: [Pin], unplaced: [ItemID]) {
            self.pins = pins
            self.unplaced = unplaced
            pinsByID = Dictionary(pins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            mapRect = LocationFrame.covering(pins.map(\.point)).map(MapLayout.rect(of:)) ?? .world
        }

    }

    private static func rect(of frame: LocationFrame) -> MKMapRect {
        let north = min(90, frame.latitude + frame.latitudeSpan / 2)
        let south = max(-90, frame.latitude - frame.latitudeSpan / 2)
        let west = max(-180, frame.longitude - frame.longitudeSpan / 2)
        let east = min(180, frame.longitude + frame.longitudeSpan / 2)
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        return MKMapRect(
            x: topLeft.x, y: topLeft.y, width: max(1, bottomRight.x - topLeft.x), height: max(1, bottomRight.y - topLeft.y))
    }

    /// Whether a place of items of these types can show a map: one of them has the two coordinates.
    static func canPlace(types: Set<TypeID>, catalogue: Catalogue) -> Bool {
        types.contains { ItemLocation.of(catalogue.itemTypes[$0]) != nil }
    }

    static func placing(for items: [Item], catalogue: Catalogue) -> Placing {
        var locations: [TypeID: ItemLocation?] = [:]
        var pins: [Pin] = []
        var unplaced: [ItemID] = []
        for item in items {
            let location: ItemLocation?
            if let known = locations[item.type] {
                location = known
            } else {
                location = ItemLocation.of(catalogue.itemTypes[item.type])
                locations[item.type] = .some(location)
            }
            guard let location, case .point(let point) = location.reading(of: item) else {
                unplaced.append(item.id)
                continue
            }
            pins.append(Pin(id: item.id, type: item.type, title: item.displayTitle, subtitle: subtitle(of: item, location: location), point: point))
        }
        return Placing(pins: pins, unplaced: unplaced)
    }

    /// What the card says under the title: the place's name where the type has one, else the address it holds.
    private static func subtitle(of item: Item, location: ItemLocation) -> String? {
        if case .typed = location.name { return location.name(of: item) }
        let parts = [MarfaMapping.streetAddressField, MarfaMapping.localityField, MarfaMapping.postalCodeField].compactMap { key -> String? in
            guard let text = item.value(of: key)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
