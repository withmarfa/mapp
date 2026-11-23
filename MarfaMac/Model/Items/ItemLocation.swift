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
/// MAPP writes only what the person gave it: a point they put on the map and a name they typed. Nothing that a map
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

    /// Whether the item holds anything Location draws: a number or a typed name.
    func hasValue(in item: Item) -> Bool {
        keys.contains { InspectorFields.hasValue(item.value(of: $0)) }
    }

    /// Whether a list of the item's properties shows its Location: the item holds something it draws, or the person
    /// just added it (`revealed` holds `rowID`).
    func isListed(in item: Item, revealed: Set<String> = []) -> Bool {
        hasValue(in: item) || (item.isEditable && revealed.contains(Self.rowID))
    }

    // MARK: Reading

    /// What the item's two numbers say.
    enum Reading: Hashable, Sendable {
        /// Neither number is set.
        case none
        /// Only one is set, so there is no point to draw. The text says what is held.
        case partial(String)
        case point(LocationPoint)
        /// Both are set and are no place on Earth, or are not numbers. The text says what is held.
        case unplaceable(String)
    }

    func reading(of item: Item) -> Reading {
        let north = item.value(of: latitude.key), east = item.value(of: longitude.key)
        let hasNorth = InspectorFields.hasValue(north), hasEast = InspectorFields.hasValue(east)
        guard hasNorth || hasEast else { return .none }
        func text(_ value: PropertyValue?) -> String { InspectorFields.hasValue(value) ? value.map(ItemValueText.string) ?? "–" : "–" }
        let held = "\(text(north)), \(text(east))"
        guard hasNorth, hasEast else { return .partial(held) }
        if case .number(let degreesNorth)? = north, case .number(let degreesEast)? = east,
           let point = LocationPoint(latitude: degreesNorth.nearestDouble, longitude: degreesEast.nearestDouble) {
            return .point(point)
        }
        return .unplaceable(held)
    }

    /// The name the item holds for the place, or nil where the type has none or it is empty. A place shows its own name
    /// only once it has a point, since a name with nowhere to point is the page's title and not a place.
    func name(of item: Item) -> String? {
        switch name {
        case .typed(let field):
            return Self.firstLine(item.value(of: field.key)?.string)
        case .itemName:
            guard case .point = reading(of: item) else { return nil }
            return Self.firstLine(item.name ?? item.title)
        case .none:
            return nil
        }
    }

    private static func firstLine(_ text: String?) -> String? {
        guard let line = text?.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces), !line.isEmpty else { return nil }
        return line
    }

    /// What the Location row reads, or nil where the item has no Location to show. A point with no name reads Map; a
    /// pair that cannot be drawn reads as it is stored, so what the item holds is never hidden.
    func summary(of item: Item) -> String? {
        let name = name(of: item)
        switch reading(of: item) {
        case .point: return name ?? String(localized: "Map")
        case .partial(let held), .unplaceable(let held): return name ?? held
        case .none: return name
        }
    }

    /// Whether the panel has something to show an item that cannot be edited: a point on the map.
    func hasPoint(_ item: Item) -> Bool {
        if case .point = reading(of: item) { true } else { false }
    }

    /// Why the panel cannot draw what the item holds, or nil where it can.
    func problem(of item: Item) -> String? {
        switch reading(of: item) {
        case .partial: String(localized: "Only one of the two coordinates is set, so there is no point to show.")
        case .unplaceable: String(localized: "These coordinates are not a place on Earth, so they cannot be shown on the map.")
        case .none, .point: nil
        }
    }

    /// Whether the panel offers a field to name the place.
    var hasNameField: Bool { nameKey != nil }

    // MARK: Row

    /// The row for the property block and the pins, or nil where there is nothing to show and nothing to offer. A value
    /// the item does not have yet is an Empty row that opens the panel (`offersEmpty`), as every value the page sets is. An
    /// item that cannot be edited still opens the panel where it has a point, which then only shows it.
    func row(of item: Item, offersEmpty: Bool) -> PropertyRow? {
        let label = String(localized: "Location")
        if let summary = summary(of: item) {
            return PropertyRow(
                id: Self.rowID, label: label, value: .text(summary), editable: item.isEditable || hasPoint(item), symbol: Self.symbol)
        }
        guard offersEmpty, item.isEditable else { return nil }
        return PropertyRow(id: Self.rowID, label: label, value: .empty(symbol: Self.symbol), editable: true)
    }

    // MARK: Writing

    /// What putting the point on the map writes: both numbers, and the name where it was typed and differs from what the
    /// item holds. Only what changes is listed, so a point put where it already is writes nothing.
    func placing(_ point: LocationPoint, name typed: String? = nil, in item: Item) -> [String: PropertyValue?] {
        var changes: [String: PropertyValue?] = [:]
        for (field, degrees) in [(latitude, point.latitude), (longitude, point.longitude)] {
            let value = LocationPoint.stored(degrees)
            if item.value(of: field.key) != value { changes.updateValue(value, forKey: field.key) }
        }
        if let typed, let naming = naming(typed, in: item) { changes.merge(naming) { first, _ in first } }
        return changes
    }

    /// What typing a name writes, or nil where the type has no name to type or the text is what the item holds. An empty
    /// name takes the field's value away.
    func naming(_ text: String, in item: Item) -> [String: PropertyValue?]? {
        guard case .typed(let field) = name else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let new: PropertyValue? = trimmed.isEmpty ? nil : .string(trimmed)
        let held = item.value(of: field.key)
        guard InspectorFields.hasValue(held) || new != nil, held != new else { return nil }
        return [field.key: new]
    }

    /// What clearing the Location writes: both numbers taken away, and the name left, which is the person's own words.
    func clearing(_ item: Item) -> [String: PropertyValue?] {
        var changes: [String: PropertyValue?] = [:]
        for field in [latitude, longitude] where InspectorFields.hasValue(item.value(of: field.key)) {
            changes.updateValue(nil, forKey: field.key)
        }
        return changes
    }

    // MARK: Listing

    /// One entry of a list of an item's fields, where Location stands in for some of them.
    enum Entry: Identifiable, Hashable, Sendable {
        case field(ItemTypeInfo.Field)
        case location(ItemLocation)

        var id: String {
            switch self {
            case .field(let field): field.key
            case .location: ItemLocation.rowID
            }
        }
    }

    /// `fields` with the ones Location owns taken out and Location put where the first of them was, or at the end where
    /// none was. Nothing is added where `listsLocation` is false.
    func folding(_ fields: [ItemTypeInfo.Field], showingCoordinates: Bool, listsLocation: Bool) -> [Entry] {
        let owned = ownedKeys(showingCoordinates: showingCoordinates)
        let own = keys
        var entries: [Entry] = []
        var placed = false
        for field in fields {
            if own.contains(field.key) {
                if listsLocation, !placed {
                    entries.append(.location(self))
                    placed = true
                }
                if !owned.contains(field.key) { entries.append(.field(field)) }
            } else {
                entries.append(.field(field))
            }
        }
        if listsLocation, !placed { entries.append(.location(self)) }
        return entries
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
