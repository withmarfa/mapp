import AppKit
import MapKit

/// A place's map as its page draws it: a still picture of Apple's map at the place's point, with the point marked, made
/// once for each appearance so a change of appearance needs no new one. The page is a web view, which cannot hold a live
/// map, and the picture is the map's only use here: nothing on it moves or is clicked, and the corner's Open takes the
/// person to Maps. A map is asked of MapKit once for a point and kept.
@MainActor
final class PlaceMapImages {
    static let shared = PlaceMapImages()

    /// The two pictures, as the web page reads them.
    struct Pictures: Equatable, Sendable {
        let light: String
        let dark: String
    }

    /// The pictures' size in points. The page fits them to its column.
    static let size = CGSize(width: 680, height: 260)
    /// How much of the world the picture shows, across its width.
    private static let span: CLLocationDistance = 500

    private var held: [LocationPoint: Pictures] = [:]
    private var waiting: [LocationPoint: [@MainActor () -> Void]] = [:]

    /// The pictures for `point` if they are made. Otherwise nil, and `whenMade` is called once they are, or never if
    /// MapKit has no map to give.
    func pictures(for point: LocationPoint, whenMade: @escaping @MainActor () -> Void) -> Pictures? {
        if let pictures = held[point] { return pictures }
        if waiting[point] != nil {
            waiting[point]?.append(whenMade)
            return nil
        }
        waiting[point] = [whenMade]
        Task {
            async let light = Self.render(point, dark: false)
            async let dark = Self.render(point, dark: true)
            let made = await (light, dark)
            let callbacks = waiting.removeValue(forKey: point) ?? []
            guard let light = made.0, let dark = made.1 else { return }
            held[point] = Pictures(light: light, dark: dark)
            for callback in callbacks { callback() }
        }
        return nil
    }

    private static func render(_ point: LocationPoint, dark: Bool) async -> String? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
            latitudinalMeters: span * size.height / size.width, longitudinalMeters: span)
        options.size = size
        options.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Points, as the snapshot and the pin are drawn in.
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let rect = CGRect(origin: .zero, size: size)
        snapshot.image.draw(in: rect)
        // The snapshot answers a point in the picture's own top-left coordinates; this context is bottom-left.
        let at = snapshot.point(for: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        let tip = CGPoint(x: at.x, y: size.height - at.y)
        let pin = NSImage(systemSymbolName: "mappin", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 40, weight: .regular).applying(.init(paletteColors: [.systemRed])))
        if let pin {
            pin.draw(in: CGRect(x: tip.x - pin.size.width / 2, y: tip.y, width: pin.size.width, height: pin.size.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
