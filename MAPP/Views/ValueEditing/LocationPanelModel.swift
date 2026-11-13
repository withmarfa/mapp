import Foundation
import MapKit
import Marfa
import Observation

/// A place a search found. It lives only while the results are on show and is never stored, written or put in a log:
/// Apple's terms for its map data (Developer Program License Agreement, Attachment 6, section 2.5) allow it to be kept
/// only for a moment. Choosing one moves the map and nothing else.
struct LocationSearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let point: LocationPoint
}

/// What the Location panel holds: the item's point and name as the library has them, what is typed, and a search that
/// only moves the map. The person puts the pin on the map themselves, so the only things written are the latitude and
/// longitude of a point they chose and a name they typed (`ItemLocation`).
@MainActor @Observable
final class LocationPanelModel {
    enum Search: Equatable {
        case idle
        case searching
        case found([LocationSearchResult])
        case noResults
        case failed
    }

    /// What a write on its way will make the point, until the library's copy shows it.
    private enum Pending {
        case point(LocationPoint)
        case cleared
    }

    let spec: ItemLocation
    let itemID: ItemID
    @ObservationIgnored private let library: any ItemLibrary
    @ObservationIgnored private let undoManager: UndoManager?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored private var nameBase = ""
    /// The map's view as it last settled, so a search looks near where the person is looking.
    @ObservationIgnored var visibleRegion: MKCoordinateRegion?
    /// Counts the panel's writes, so the view redraws when one is made, before the copy shows it.
    private var writes = 0

    var query = ""
    private(set) var search = Search.idle
    var notice: String?
    private var typedName = ""
    private var isNameDirty = false
    private(set) var hasNameConflict = false

    init(spec: ItemLocation, item: ItemID, library: any ItemLibrary, undoManager: UndoManager?) {
        self.spec = spec
        itemID = item
        self.library = library
        self.undoManager = undoManager
    }

    // MARK: Item

    private var item: Item? { library.item(itemID) }

    /// Whether the person can change the item's Location. An item that cannot be edited shows its point and nothing more.
    var canEdit: Bool { item?.isEditable ?? false }

    var reading: ItemLocation.Reading { item.map(spec.reading(of:)) ?? .none }

    /// The point on the map: the one the panel wrote while the library still has it on its way, else the item's own.
    var point: LocationPoint? {
        _ = writes
        if let pending, library.isWritingProperties(of: itemID) {
            switch pending {
            case .point(let point): return point
            case .cleared: return nil
            }
        }
        if case .point(let point) = reading { return point }
        return nil
    }

    /// Whether there is a Location to clear: a point, or numbers that are no point.
    var hasLocation: Bool {
        _ = writes
        if let pending, library.isWritingProperties(of: itemID) {
            if case .point = pending { return true } else { return false }
        }
        if case .none = reading { return false }
        return true
    }

    /// Why the panel cannot draw what the item holds, or nil.
    var problem: String? { item.flatMap(spec.problem(of:)) }

    var hasNameField: Bool { spec.hasNameField }

    /// Where the map first looks: the item's own point, else round the places the person's other items hold, else the world.
    var startFrame: LocationFrame {
        if let point { return .around(point) }
        return .start(point: nil, others: othersPoints())
    }

    private func othersPoints() -> [LocationPoint] {
        var specs: [TypeID: ItemLocation] = [:]
        var without: Set<TypeID> = []
        var points: [(date: Date, point: LocationPoint)] = []
        for other in library.items(in: .allNotes) where other.id != itemID {
            let type = other.type
            if without.contains(type) { continue }
            if specs[type] == nil {
                guard let found = ItemLocation.of(library.catalogue.itemTypes[type]) else {
                    without.insert(type)
                    continue
                }
                specs[type] = found
            }
            if let known = specs[type], case .point(let point) = known.reading(of: other) { points.append((other.modified, point)) }
        }
        return points.sorted { $0.date > $1.date }.prefix(Self.nearbyLimit).map(\.point)
    }

    /// The most recent places the opening view is made to cover, so a library of thousands is not scanned past its latest.
    static let nearbyLimit = 25

    // MARK: Name

    private var heldName: String {
        guard let item, let key = spec.nameKey else { return "" }
        return item.value(of: key)?.string ?? ""
    }

    /// The name in the field: what the person is typing, else what the item holds, which follows a change made elsewhere.
    var name: String {
        get { isNameDirty ? typedName : heldName }
        set {
            guard newValue != name else { return }
            if !isNameDirty { nameBase = heldName }
            typedName = newValue
            isNameDirty = true
            hasNameConflict = false
            notice = nil
        }
    }

    /// Writes the name that was typed. A name the item changed under the text waits for the person to say which they mean.
    func commitName(overwriting: Bool = false) {
        guard isNameDirty, let item else { return }
        guard canEdit else { return }
        guard let changes = spec.naming(typedName, in: item) else {
            isNameDirty = false
            return
        }
        if !overwriting, heldName != nameBase {
            hasNameConflict = true
            notice = String(localized: "This name changed while you were editing. Your edit hasn’t been saved.")
            return
        }
        if write(changes) {
            isNameDirty = false
            hasNameConflict = false
        }
    }

    func keepName() { commitName(overwriting: true) }

    func useHeldName() {
        isNameDirty = false
        hasNameConflict = false
        notice = nil
    }

    // MARK: Writing

    /// Puts the point on the map: both numbers, and the name where one was typed, in one edit and one undo step.
    func place(_ point: LocationPoint) {
        guard canEdit, let item else { return }
        let typed = isNameDirty && !hasNameConflict ? typedName : nil
        let changes = spec.placing(point, name: typed, in: item)
        if write(changes) {
            pending = .point(point)
            if typed != nil { isNameDirty = false }
        }
    }

    /// Takes both numbers away, and leaves the name, which is the person's own words.
    func clear() {
        guard canEdit, let item else { return }
        if write(spec.clearing(item)) { pending = .cleared }
    }

    private func write(_ changes: [String: PropertyValue?]) -> Bool {
        guard !changes.isEmpty else { return true }
        let taken = library.setItemProperties(
            itemID, changes: changes, actionName: String(localized: "Edit Location"), undoManager: undoManager)
        if taken {
            notice = nil
            writes += 1
        } else {
            notice = canEdit ? String(localized: "The location couldn’t be saved.") : PropertyLoss.notEditable.reason
        }
        return taken
    }

    /// The panel is ending. A name that was typed is written unless the person cancelled it; a point is already written.
    func finish(cancelled: Bool) {
        searchTask?.cancel()
        if !cancelled { commitName() }
    }

    // MARK: Search

    /// Looks for places near where the map is, a moment after the person stops typing. The answer only moves the map.
    func queryChanged() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            search = .idle
            return
        }
        search = .searching
        let region = visibleRegion
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            if let region { request.region = region }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                let results = response.mapItems.compactMap(Self.result(of:))
                self?.search = results.isEmpty ? .noResults : .found(results)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.search = .failed
            }
        }
    }

    private static func result(of mapItem: MKMapItem) -> LocationSearchResult? {
        let coordinate = mapItem.location.coordinate
        guard let point = LocationPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return nil }
        let title = mapItem.name ?? mapItem.address?.shortAddress ?? ""
        guard !title.isEmpty else { return nil }
        let address = mapItem.address?.shortAddress ?? ""
        return LocationSearchResult(title: title, subtitle: address == title ? "" : address, point: point)
    }

    /// Where the map goes for a chosen result. Nothing is written: the person places the pin.
    func choose(_ result: LocationSearchResult) -> LocationFrame {
        search = .idle
        return .around(result.point, span: 0.02)
    }
}

extension LocationFrame {
    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan))
    }
}

extension LocationPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
