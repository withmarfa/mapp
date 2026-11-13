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

/// What the Location panel holds: the item's point and name as the panel last left them, what is typed, and a search that
/// only moves the map. The person puts the pin on the map themselves, so the only things written are the latitude and
/// longitude of a point they chose and a name they typed (`ItemLocation`).
///
/// A library can take a write after it is made (`MarfaLibrary` queues it), so until the copy shows the panel's last write
/// the panel shows what it wrote and builds the next change on that, never on a copy that still holds the value from
/// before. A placement then cleared, or moved back where it was, before the first lands is written, not skipped.
@MainActor @Observable
final class LocationPanelModel {
    enum Search: Equatable {
        case idle
        case searching
        case found([LocationSearchResult])
        case noResults
        case failed
    }

    let spec: ItemLocation
    let itemID: ItemID
    @ObservationIgnored private let library: any ItemLibrary
    @ObservationIgnored private let undoManager: UndoManager?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// What the panel wrote, by key, since the library last held all of it: the two numbers and the name.
    @ObservationIgnored private var written: [String: PropertyValue?] = [:]
    /// The library's mark for the panel's last write (`ItemLibrary.lastPropertyWrite`), nil where it keeps none.
    @ObservationIgnored private var writtenMark: Int?
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

    /// Whether the panel's last write is still on its way, so the library's copy may not show it yet.
    private var isWaiting: Bool {
        guard !written.isEmpty, library.isWritingProperties(of: itemID) else { return false }
        if let writtenMark, library.tookPropertyWrite(writtenMark) { return false }
        return true
    }

    /// The item as the panel last left it: the library's copy, with what the panel wrote laid over it while that is on
    /// its way. Everything the panel shows and every change it makes is read from this.
    private var item: Item? {
        _ = writes
        guard var item = library.item(itemID) else { return nil }
        guard isWaiting else { return item }
        for (key, value) in written {
            item.properties.removeAll { $0.key == key }
            if let value { item.properties.append(Property(key: key, value: value)) }
        }
        return item
    }

    /// Whether the person can change the item's Location. An item that cannot be edited shows its point and nothing more.
    var canEdit: Bool { item?.isEditable ?? false }

    var reading: ItemLocation.Reading { item.map(spec.reading(of:)) ?? .none }

    /// The point on the map, or nil where there is none to draw.
    var point: LocationPoint? {
        if case .point(let point) = reading { point } else { nil }
    }

    /// Whether there is a Location to clear: a point, or numbers that are no point.
    var hasLocation: Bool {
        if case .none = reading { false } else { true }
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

    /// The name in the field: what the person is typing, else the name as the panel last left it, which follows a change
    /// made elsewhere once nothing the panel wrote is on its way.
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
        guard isNameDirty, canEdit, let item else { return }
        guard let changes = spec.naming(typedName, in: item) else {
            isNameDirty = false
            if hasNameConflict { useHeldName() }
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
        if write(spec.placing(point, name: typed, in: item)), typed != nil { isNameDirty = false }
    }

    /// Takes both numbers away, and leaves the name, which is the person's own words.
    func clear() {
        guard canEdit, let item else { return }
        write(spec.clearing(item))
    }

    @discardableResult
    private func write(_ changes: [String: PropertyValue?]) -> Bool {
        guard !changes.isEmpty else { return true }
        // Read before the write, which the library then has on its way too.
        let wasWaiting = isWaiting
        let taken = library.setItemProperties(
            itemID, changes: changes, actionName: String(localized: "Edit Location"), undoManager: undoManager)
        if taken {
            if !wasWaiting { written = [:] }
            written.merge(changes) { _, new in new }
            writtenMark = library.lastPropertyWrite
            // A name that changed under the text keeps its choice until the person makes it.
            if !hasNameConflict { notice = nil }
            writes += 1
        } else {
            notice = canEdit ? String(localized: "The location couldn’t be saved.") : PropertyLoss.notEditable.reason
        }
        return taken
    }

    /// The panel is ending. A name that was typed is written unless the person cancelled it; one that cannot be, as it
    /// changed meanwhile or was refused, goes back to the person through `Notices.notKept`, since the panel's own notice
    /// goes with it. A point is already written.
    func finish(cancelled: Bool) {
        searchTask?.cancel()
        guard !cancelled else { return }
        commitName()
        guard isNameDirty, case .typed(let field) = spec.name else { return }
        let loss: PropertyLoss = hasNameConflict ? .conflict : canEdit ? .notSaved : .notEditable
        library.notices.notKept(String(localized: "Property Not Saved"), text: "\(field.label): \(typedName)", reason: loss.reason)
        isNameDirty = false
        hasNameConflict = false
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
