import Foundation
import Marfa

/// A point on Earth that a map can draw: a latitude within 90 degrees of the equator and a longitude within 180 of
/// Greenwich.
nonisolated struct LocationPoint: Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    /// Nil for a pair that is no place on Earth, such as a latitude of 91.
    init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The point a click on a map that repeats around the world names: the longitude is brought back within 180 degrees.
    /// Nil for a latitude off the map.
    init?(clicked latitude: Double, longitude: Double) {
        guard longitude.isFinite else { return nil }
        var wrapped = longitude.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { wrapped -= 360 }
        if wrapped < -180 { wrapped += 360 }
        self.init(latitude: latitude, longitude: wrapped)
    }

    /// A coordinate as Marfa stores it: to six decimal places, about a tenth of a metre, so a point that was dragged does
    /// not carry the noise of the screen.
    static func stored(_ degrees: Double) -> PropertyValue {
        let text = String(format: "%.6f", degrees)
        return .number(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(degrees))
    }
}

/// An item's Location: the point it names on a map and, where its type has one, a name for the place. It is built from
/// fields the type already has, so nothing in Marfa is added for it. Pure, with no map: the page, the sidebar and the
/// panel each ask it what to show and what an edit writes.
///
/// the app writes only what the person gave it: a point they put on the map and a name they typed. Nothing that a map
/// search returns is ever written, since Apple's terms for its map data (Developer Program License Agreement,
/// Attachment 6, section 2.5) allow it to be kept only for a moment.
nonisolated struct ItemLocation: Hashable, Sendable {
    /// Where the place's name is kept.
    enum Name: Hashable, Sendable {
        /// A text field of the type, which Location sets as well as shows: an event's `place`.
        case typed(ItemTypeInfo.Field)
        /// The item's own name, which a place is, and which Location shows and never changes.
        case itemName
        /// Nothing: a map and no name, as an image or a video has.
        case none
    }

    /// The row's identifier on the page, which stands for the whole of Location.
    static let rowID = PagePlacement.location
    /// The symbol that stands for a Location beside its label.
    static let symbol = "mappin.and.ellipse"

    let latitude: ItemTypeInfo.Field
    let longitude: ItemTypeInfo.Field
    let name: Name

    /// The Location a type has, or nil where it has not both numbers. A type with one of the two cannot place anything, so
    /// the one stays an ordinary number.
    static func of(_ type: ItemTypeInfo?) -> ItemLocation? {
        guard let type,
              let latitude = type.fields.first(where: { $0.key == MarfaMapping.latitudeField && $0.kind == .number }),
              let longitude = type.fields.first(where: { $0.key == MarfaMapping.longitudeField && $0.kind == .number })
        else { return nil }
        if let place = type.fields.first(where: { $0.key == MarfaMapping.placeField && $0.kind == .text }) {
            return ItemLocation(latitude: latitude, longitude: longitude, name: .typed(place))
        }
        return ItemLocation(latitude: latitude, longitude: longitude, name: type.isPlace ? .itemName : .none)
    }

    /// Every field Location is made of: the two numbers and the name's field.
    var keys: Set<String> {
        var keys: Set<String> = [latitude.key, longitude.key]
        if let nameKey { keys.insert(nameKey) }
        return keys
    }

    /// The fields Location draws in place of their own rows: its name, and the two numbers unless the person shows them.
    func ownedKeys(showingCoordinates: Bool) -> Set<String> {
        var keys: Set<String> = []
        if case .typed(let field) = name { keys.insert(field.key) }
        if !showingCoordinates { keys.formUnion([latitude.key, longitude.key]) }
        return keys
    }

    func clearing(_ item: Item) -> [String: PropertyValue?] {
        var changes: [String: PropertyValue?] = [:]
        for field in [latitude, longitude] where InspectorFields.hasValue(item.value(of: field.key)) {
            changes.updateValue(nil, forKey: field.key)
        }
        return changes
    }

    /// The key of the field the name is typed in.
    var nameKey: String? {
        if case .typed(let field) = name { field.key } else { nil }
    }
}

nonisolated extension ItemTypeInfo {
    /// Whether the type is a place: coordinates and an address. An event or an image has coordinates and no address, so it
    /// is not one. The rule for the Place look (`LookPreset`) and for a place's name in Location.
    var isPlace: Bool {
        let hasAddress = [MarfaMapping.streetAddressField, MarfaMapping.localityField, MarfaMapping.postalCodeField].contains(where: declares)
        return declares(MarfaMapping.latitudeField) && declares(MarfaMapping.longitudeField) && hasAddress
    }
}
