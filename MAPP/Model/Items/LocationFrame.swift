import Foundation

/// The stretch of the world a Location map first shows: a centre and how far it reaches each way, in degrees. Pure, so
/// where the map opens is decided and tested apart from the map.
nonisolated struct LocationFrame: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var latitudeSpan: Double
    var longitudeSpan: Double

    /// The whole world, which a map opens on where the person has no place of their own to start from.
    static let world = LocationFrame(latitude: 20, longitude: 0, latitudeSpan: 140, longitudeSpan: 360)

    /// A street-scale view of `point`: about a kilometre across.
    static func around(_ point: LocationPoint, span: Double = 0.01) -> LocationFrame {
        LocationFrame(latitude: point.latitude, longitude: point.longitude, latitudeSpan: span, longitudeSpan: span)
    }

    /// The view that holds all of `points` with some room round them, never closer than a few kilometres. Nil where there are
    /// none, or where they are so far apart that the world is the honest view.
    static func covering(_ points: [LocationPoint]) -> LocationFrame? {
        guard let first = points.first else { return nil }
        var (south, north, west, east) = (first.latitude, first.latitude, first.longitude, first.longitude)
        for point in points.dropFirst() {
            south = min(south, point.latitude)
            north = max(north, point.latitude)
            west = min(west, point.longitude)
            east = max(east, point.longitude)
        }
        let room = 1.4, least = 0.05
        let (latitudeSpan, longitudeSpan) = (max((north - south) * room, least), max((east - west) * room, least))
        guard latitudeSpan < 120, longitudeSpan < 180 else { return nil }
        return LocationFrame(
            latitude: (south + north) / 2, longitude: (west + east) / 2, latitudeSpan: latitudeSpan, longitudeSpan: longitudeSpan)
    }

    /// Where a map opens: on the item's own point, else round the places the person's other items hold, else the world.
    static func start(point: LocationPoint?, others: [LocationPoint]) -> LocationFrame {
        if let point { return .around(point) }
        return covering(others) ?? .world
    }
}
