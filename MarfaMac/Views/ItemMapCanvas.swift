import AppKit
import MapKit
import SwiftUI

/// An Apple map that reports Return, Escape and Command-Delete while it has the keyboard.
final class ItemMKMapView: MKMapView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()
        case 51 where ShortcutModifiers(event.modifierFlags) == .command:
            if !event.isARepeat { onDelete?() }
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}

/// One item's marker on the map.
final class PinAnnotation: NSObject, MKAnnotation {
    let pin: MapLayout.Pin
    let coordinate: CLLocationCoordinate2D
    /// Whether the window has chosen the item, which then never joins a group, so its card always shows.
    var isChosen = false

    init(_ pin: MapLayout.Pin) {
        self.pin = pin
        coordinate = pin.point.coordinate
    }

    var title: String? { pin.title }
    var subtitle: String? { pin.subtitle }
}

/// Owns the map view for a window's Map layout and answers for it: it draws the markers and groups as images
/// (`MapArtist`), keeps the chosen marker and the window's selection as one, and opens an item on a double-click. A map
/// view groups markers that crowd (`MKClusterAnnotation`) where SwiftUI's `Map` cannot.
@MainActor
final class MapController: NSObject, MKMapViewDelegate {
    private static let markerIdentifier = "marker"
    private static let groupIdentifier = "group"
    private static let clustering = "items"

    /// Made when first asked for, since a view that holds a controller makes one each time it is built and keeps only the first.
    lazy var mapView: ItemMKMapView = {
        let mapView = ItemMKMapView()
        mapView.delegate = self
        mapView.showsCompass = false
        mapView.showsZoomControls = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.onReturn = { [weak self] in _ = self?.browser?.openSelection() }
        mapView.onEscape = { [weak self] in self?.browser?.selection = [] }
        return mapView
    }()
    private let artist = MapArtist()
    private var annotations: [ItemID: PinAnnotation] = [:]
    private var servedSerial: UUID?
    private var groups = true
    private var style: ItemMapStyle?
    private var placeToken: AnyHashable?
    private var pendingFit = false
    private var shown: MapLayout.Placing?
    private var catalogue: Catalogue?
    private var reduceMotion = false
    /// Marks a selection the map itself made, which needs no moving of the map to show.
    private var choosing = false
    private weak var browser: Browser?

    // MARK: Updating

    struct Inputs {
        let browser: Browser
        let catalogue: Catalogue
        let placing: MapLayout.Placing
        let style: ItemMapStyle
        let groups: Bool
        let placeToken: AnyHashable
        let scheme: ColorScheme
        let textSize: Int
        let reduceMotion: Bool
    }

    func update(_ inputs: Inputs) {
        browser = inputs.browser
        catalogue = inputs.catalogue
        reduceMotion = inputs.reduceMotion
        let redrawn = artist.reset(scheme: inputs.scheme, textSize: inputs.textSize, backingScale: mapView.window?.backingScaleFactor ?? 2)
        prepare(style: inputs.style)
        if placeToken != inputs.placeToken {
            placeToken = inputs.placeToken
            pendingFit = true
        }
        shown = inputs.placing
        let regroups = groups != inputs.groups
        groups = inputs.groups
        let placing = inputs.placing
        let hadPlacing = servedSerial != nil
        if pendingFit { fit(placing, animated: false) }
        if placing.serial != servedSerial || regroups { show(placing, rebuilding: regroups) }
        if redrawn, hadPlacing { redrawViews() }
        syncSelection(inputs.browser.selection)
    }

    private func prepare(style: ItemMapStyle) {
        guard self.style != style else { return }
        self.style = style
        mapView.preferredConfiguration = Self.configuration(for: style)
    }

    private static func configuration(for style: ItemMapStyle) -> MKMapConfiguration {
        switch style {
        case .standard:
            let configuration = MKStandardMapConfiguration()
            // A person cannot choose one of Apple's own points on macOS, so none is drawn.
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case .satellite:
            return MKImageryMapConfiguration()
        case .hybrid:
            let configuration = MKHybridMapConfiguration()
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        }
    }

    /// Puts the markers of `placing` on the map: only those that are new or changed are added, and those gone are taken off.
    private func show(_ placing: MapLayout.Placing, rebuilding: Bool) {
        servedSerial = placing.serial
        if rebuilding {
            mapView.removeAnnotations(Array(annotations.values))
            annotations = [:]
        }
        let gone = annotations.filter { placing.pinsByID[$0.key] != $0.value.pin }
        if !gone.isEmpty {
            mapView.removeAnnotations(Array(gone.values))
            for id in gone.keys { annotations[id] = nil }
        }
        var added: [PinAnnotation] = []
        for pin in placing.pins where annotations[pin.id] == nil {
            let annotation = PinAnnotation(pin)
            annotations[pin.id] = annotation
            added.append(annotation)
        }
        mapView.addAnnotations(added)
    }

    /// Draws every marker on show again, as a change of appearance or of text size asks.
    private func redrawViews() {
        for annotation in mapView.annotations {
            if let view = mapView.view(for: annotation) { configure(view, for: annotation) }
        }
    }

    // MARK: Fitting

    /// Fits every marker, as the Fit button and View menu ask.
    /// Zooms in (a factor under 1 of the camera's distance) or out about the map's centre, as the system's own zoom control
    /// does. MapKit's `MKZoomControl` stacks its buttons and has no way to lay them side by side.
    func zoom(by factor: Double) {
        guard let camera = mapView.camera.copy() as? MKMapCamera else { return }
        camera.centerCoordinateDistance = min(max(camera.centerCoordinateDistance * factor, Self.distances.lowerBound), Self.distances.upperBound)
        mapView.setCamera(camera, animated: !reduceMotion)
    }

    /// The nearest and farthest the camera stands from the map: a street and the whole of a continent.
    private static let distances: ClosedRange<Double> = 150...20_000_000

    func fitAll() {
        if let shown { fit(shown, animated: true) }
    }

    /// Shows every marker, with room under the top row at the head and for Apple's mark and Legal at the foot.
    private func fit(_ placing: MapLayout.Placing, animated: Bool) {
        pendingFit = false
        mapView.setVisibleMapRect(
            placing.mapRect, edgePadding: NSEdgeInsets(top: 84, left: 48, bottom: 64, right: 48), animated: animated && !reduceMotion)
    }

    // MARK: Choosing

    /// Makes the chosen marker the window's single selection, and takes it off the map where the selection is anything else.
    private func syncSelection(_ selection: Set<ItemID>) {
        let wanted: PinAnnotation? = selection.count == 1 ? selection.first.flatMap { annotations[$0] } : nil
        let current = mapView.selectedAnnotations.compactMap { $0 as? PinAnnotation }
        if current.count == 1, current.first === wanted { return }
        // A marker that was chosen and no longer is may join a group again.
        for annotation in annotations.values where annotation.isChosen && annotation !== wanted { setChosen(annotation, false) }
        if let wanted {
            setChosen(wanted, true)
            if !choosing, !mapView.visibleMapRect.contains(MKMapPoint(wanted.coordinate)) {
                mapView.setCenter(wanted.coordinate, animated: !reduceMotion)
            }
            mapView.selectAnnotation(wanted, animated: !reduceMotion)
        } else {
            for annotation in mapView.selectedAnnotations { mapView.deselectAnnotation(annotation, animated: false) }
        }
    }

    /// Marks a marker chosen or not. One inside a group is taken off the map and put back, so it stands alone.
    private func setChosen(_ annotation: PinAnnotation, _ chosen: Bool) {
        guard annotation.isChosen != chosen else { return }
        annotation.isChosen = chosen
        if let view = mapView.view(for: annotation) {
            configure(view, for: annotation)
        } else {
            mapView.removeAnnotation(annotation)
            mapView.addAnnotation(annotation)
        }
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        if let pin = view.annotation as? PinAnnotation { pin.isChosen = true }
        configure(view, for: view.annotation)
        if let pin = view.annotation as? PinAnnotation {
            guard annotations[pin.pin.id] === pin else { return }
            choosing = true
            if browser?.selection != [pin.pin.id] { browser?.selection = [pin.pin.id] }
            choosing = false
        } else if let group = view.annotation as? MKClusterAnnotation {
            mapView.deselectAnnotation(group, animated: false)
            mapView.showAnnotations(group.memberAnnotations, animated: !reduceMotion)
        }
    }

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        (view.annotation as? PinAnnotation)?.isChosen = false
        configure(view, for: view.annotation)
        guard let pin = view.annotation as? PinAnnotation else { return }
        // Moving from one marker to the next deselects the first before it selects the second.
        Task { @MainActor [weak self] in
            guard let self, self.annotations[pin.pin.id] === pin, self.mapView.selectedAnnotations.isEmpty,
                  self.browser?.selection == [pin.pin.id] else { return }
            self.browser?.selection = []
        }
    }

    // MARK: Views

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }
        let isGroup = annotation is MKClusterAnnotation
        let identifier = isGroup ? Self.groupIdentifier : Self.markerIdentifier
        let view: MKAnnotationView
        if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) {
            reused.annotation = annotation
            view = reused
        } else {
            view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            if !isGroup {
                let click = NSClickGestureRecognizer(target: self, action: #selector(opens(_:)))
                click.numberOfClicksRequired = 2
                view.addGestureRecognizer(click)
            }
        }
        configure(view, for: annotation)
        return view
    }

    func mapView(_ mapView: MKMapView, clusterAnnotationForMemberAnnotations memberAnnotations: [any MKAnnotation]) -> MKClusterAnnotation {
        let cluster = MKClusterAnnotation(memberAnnotations: memberAnnotations)
        cluster.title = String(localized: "\(memberAnnotations.count) items")
        return cluster
    }

    private func configure(_ view: MKAnnotationView, for annotation: (any MKAnnotation)?) {
        if let cluster = annotation as? MKClusterAnnotation {
            let drawn = artist.group(count: cluster.memberAnnotations.count)
            place(drawn, in: view)
            view.displayPriority = .defaultHigh
            view.zPriority = .defaultUnselected
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.button)
            view.setAccessibilityLabel(String(localized: "\(cluster.memberAnnotations.count) items"))
            view.setAccessibilityHelp(String(localized: "Zooms in on these items."))
            return
        }
        guard let annotation = annotation as? PinAnnotation, let catalogue else { return }
        let pin = annotation.pin
        let icon = catalogue.icon(for: pin.type)
        let drawn = artist.marker(
            glyph: icon, tone: TypeTone(icon: icon), title: pin.title, typeName: catalogue.label(for: pin.type), subtitle: pin.subtitle,
            isChosen: annotation.isChosen)
        place(drawn, in: view)
        view.clusteringIdentifier = groups && !annotation.isChosen ? Self.clustering : nil
        view.displayPriority = annotation.isChosen ? .required : .defaultLow
        view.zPriority = annotation.isChosen ? .max : .defaultUnselected
        view.canShowCallout = false
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(pin.title)
        view.setAccessibilityHelp(pin.subtitle ?? catalogue.label(for: pin.type))
        view.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: String(localized: "Open")) { [weak self] in
                self?.open(pin.id)
                return true
            }
        ])
    }

    /// Sets the image so the picture's tip, or a group's centre, stands on the item's point.
    private func place(_ drawn: MapArtist.Drawn, in view: MKAnnotationView) {
        view.image = drawn.image
        view.centerOffset = CGPoint(x: 0, y: drawn.tipFromFoot - drawn.image.size.height / 2)
    }

    @objc private func opens(_ recognizer: NSClickGestureRecognizer) {
        guard let view = recognizer.view as? MKAnnotationView, let pin = view.annotation as? PinAnnotation else { return }
        open(pin.pin.id)
    }

    private func open(_ id: ItemID) {
        guard let browser, annotations[id] != nil else { return }
        browser.selection = [id]
        _ = browser.open([id])
    }
}

/// The map in SwiftUI: the controller's map view, drawn from what the layout hands it.
struct ItemMapCanvas: NSViewRepresentable {
    let controller: MapController
    let inputs: MapController.Inputs
    private var delete = ChosenItemDeletion()

    init(controller: MapController, inputs: MapController.Inputs) {
        self.controller = controller
        self.inputs = inputs
    }

    func makeNSView(context: Context) -> ItemMKMapView { controller.mapView }

    func updateNSView(_ view: ItemMKMapView, context: Context) {
        controller.update(inputs)
        let delete = delete
        let place = inputs.browser.shown
        let placing = inputs.placing
        view.onDelete = { [weak browser = inputs.browser] in
            guard let browser, browser.shown == place else { return }
            delete(browser) { Set(placing.pinsByID.keys) }
        }
    }
}
