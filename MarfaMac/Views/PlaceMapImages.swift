import AppKit
import MapKit

/// A place's map as its page draws it: a still picture of Apple's map at the place's point, with the point marked, made
/// once for each appearance so a change of appearance needs no new one. The page is a web view, which cannot hold a live
/// map, and the picture is the map's only use here: nothing on it moves or is clicked, and the corner's Open takes the
/// person to Maps. MapKit draws no attribution into a snapshot, so the page draws Apple Maps and a Legal link over it.
/// The last few points' pictures are kept, and nothing is stored.
@MainActor
final class PlaceMapImages {
    static let shared = PlaceMapImages()

    /// The two pictures, as the web page reads them.
    final class Pictures: Equatable, Sendable {
        let light: String
        let dark: String
        init(light: String, dark: String) {
            self.light = light
            self.dark = dark
        }
        static func == (lhs: Pictures, rhs: Pictures) -> Bool { lhs.light == rhs.light && lhs.dark == rhs.dark }
    }

    /// What a request for a point gives.
    enum Answer: Equatable {
        /// Being made; `whenMade` is called once it is.
        case waiting
        case made(Pictures)
        /// MapKit has no map to give, as offline: the page draws no box.
        case unavailable
    }

    /// The pictures' size in points. The page fits them to its column.
    nonisolated static let size = CGSize(width: 680, height: 260)
    /// How much of the world the picture shows, across its width.
    private nonisolated static let span: CLLocationDistance = 500
    /// How many points' pictures are kept; each is about a quarter of a megabyte.
    private static let kept = 6

    private let held: NSCache<NSString, Pictures> = {
        let cache = NSCache<NSString, Pictures>()
        cache.countLimit = PlaceMapImages.kept
        return cache
    }()
    /// When each point's last failure was, so a map is asked for again once the network may be back.
    private var failed: [LocationPoint: Date] = [:]
    private static let retryAfter: TimeInterval = 30
    private var waiting: [LocationPoint: [@MainActor () -> Void]] = [:]

    private func key(_ point: LocationPoint) -> NSString { "\(point.latitude),\(point.longitude)" as NSString }

    /// The pictures for `point` if they are made. A failure is remembered for a short while, so a page drawn again does
    /// not ask again at once, and the page draws no box.
    func pictures(for point: LocationPoint, whenMade: @escaping @MainActor () -> Void) -> Answer {
        if let pictures = held.object(forKey: key(point)) { return .made(pictures) }
        if let at = failed[point], Date.now.timeIntervalSince(at) < Self.retryAfter { return .unavailable }
        if waiting[point] != nil {
            waiting[point]?.append(whenMade)
            return .waiting
        }
        waiting[point] = [whenMade]
        Task {
            async let light = Self.render(point, dark: false)
            async let dark = Self.render(point, dark: true)
            let made = await (light, dark)
            let callbacks = waiting.removeValue(forKey: point) ?? []
            if let light = made.0, let dark = made.1 {
                held.setObject(Pictures(light: light, dark: dark), forKey: key(point))
            } else {
                failed = failed.filter { Date.now.timeIntervalSince($0.value) < Self.retryAfter }
                failed[point] = .now
            }
            for callback in callbacks { callback() }
        }
        return .waiting
    }

    /// Off the main actor: the snapshot, the drawing and the encoding.
    @concurrent
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
