import Foundation
import os

/// Bringing a window back, by the identifiers of what it showed, when the app opens again.
extension Browser {
    /// What a window brings back when the app opens again, by the identifiers of what it showed, which last from
    /// one launch to the next. A snapshot in any other form reads as none.
    struct Snapshot: Codable, Equatable {
        var place: PlaceView
        var selection: [ItemID]
        var viewMode: ItemViewMode = .list
        /// An item was open from the table or the gallery, not the table or gallery itself.
        var opensItem: Bool?
        /// How far the list, table or gallery was scrolled.
        var scrollOffset: Double?
        /// The window was left in Files, which is no place now. Never stored.
        var leftFiles = false
    }

    /// The most items of a selection a window keeps for the next launch. A selection larger than this is kept as
    /// none, and the list opens at its first rows: saving every id on each change of selection held the main thread
    /// for a selection of thousands, and a restored selection of an arbitrary part of it would mean nothing.
    static let restoredSelectionLimit = 200

    func snapshot() -> Snapshot {
        let kept = selection.count > Self.restoredSelectionLimit ? [] : selection.sorted { $0.rawValue < $1.rawValue }
        return Snapshot(
            place: shown, selection: kept, viewMode: viewMode, opensItem: isCollectionItemPresented,
            scrollOffset: listMemory.scrollOffset.map(Double.init))
    }

    /// Updates the stored window only after its new snapshot encodes successfully.
    func saveSnapshot(_ store: (Data) -> Void) {
        do {
            store(try JSONEncoder().encode(snapshot()))
        } catch {
            Telemetry.logger(.navigation).error("Could not encode the window snapshot")
        }
    }

    /// What a snapshot is made of, as it stands, so a window notices a change without sorting a selection that may
    /// hold every item.
    struct SnapshotParts: Equatable {
        var place: PlaceView
        var selection: Set<ItemID>
        var viewMode: ItemViewMode
        var opensItem: Bool
    }

    var snapshotParts: SnapshotParts {
        SnapshotParts(place: shown, selection: selection, viewMode: viewMode, opensItem: isCollectionItemPresented)
    }

    /// Restores a window from what it kept. A snapshot that does not read, one kept in an earlier form say,
    /// leaves the window at the place Settings > General > Start With names, or its default.
    func restore(from data: Data?, in library: any ItemLibrary, order: ItemOrder, start: PlaceView? = nil) {
        let snapshot = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let startKeys = [StartWith.key, StartWith.lastPlaceKey].compactMap { defaults.string(forKey: $0) }
        if snapshot?.leftFiles == true || (snapshot == nil && startKeys.contains { EarlierPlace.read(key: $0) == .files }) {
            EarlierPlace.tellFilesOnce(library.notices, in: defaults)
        }
        if let snapshot {
            restore(snapshot, in: library, order: order)
        } else if let start {
            restore(Snapshot(place: start, selection: []), in: library, order: order)
        } else {
            selectFirstItem(in: library, order: order)
        }
    }

    /// Restores what still exists: a place gone since gives way to the Library, and items no longer in the list are
    /// dropped, leaving the top row selected if none remain. A saved view opens at its home as it is now.
    func restore(_ snapshot: Snapshot, in library: any ItemLibrary, order: ItemOrder) {
        set(layout: snapshot.viewMode)
        var place = snapshot.place
        if let id = place.savedView {
            place = library.views.contains { $0.id == id } ? .saved(id, in: library) : .library
        }
        switch place.place {
        case .collection(let id): if library.item(id) == nil { place = .library }
        case .type(let type): if !library.itemTypeCounts.contains(where: { $0.id == type }) { place = .library }
        default: break
        }
        showing = place
        let ids = Set(snapshot.selection)
        selectAutomatically(Set(items(in: library).map(\.id).filter(ids.contains)))
        let keptSelection = !selection.isEmpty
        if selection.isEmpty { selectFirstItem(in: library, order: order) }
        // Only where the window is back in the place it was left, and not with another item chosen in its stead.
        guard shown == place else { return }
        if snapshot.opensItem == true, keptSelection, selection.count == 1, usesCollection {
            isCollectionItemPresented = true
        }
        if let offset = snapshot.scrollOffset, offset > 0 { listMemory.restore(to: CGFloat(offset)) }
    }
}

extension Browser.Snapshot {
    private enum CodingKeys: String, CodingKey {
        case place, selection, viewMode, opensItem, scrollOffset
    }

    /// A place an earlier copy kept reads as the one that stands for it now (`EarlierPlace`), one favorite as the
    /// Library with that item chosen, and Files as the Library. Recently Deleted, once a place of the sidebar and now a
    /// page of Settings, reads as the Library. A place read so keeps the window's selection and view, but not its scroll
    /// offset or open item, which belonged to the old list. Any other place this build cannot read fails the decoding,
    /// so the window opens at its default.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var selection = try values.decode([ItemID].self, forKey: .selection)
        let earlier: Bool
        if let place = try? values.decode(PlaceView.self, forKey: .place) {
            self.place = place
            earlier = false
        } else {
            let object = try values.decode([String: [String: String]].self, forKey: .place)
            guard object.count == 1, let (name, value) = object.first else { throw DecodingError.dataCorruptedError(
                forKey: .place, in: values, debugDescription: "Unknown place") }
            switch name == "recentlyDeleted" ? .place(.library) : EarlierPlace.read(name: name, value: value["_0"]) {
            case .place(let place, let chosen)?:
                self.place = place
                if let chosen { selection = [chosen] }
            case .files?:
                self.place = .library
                leftFiles = true
            case nil:
                throw DecodingError.dataCorruptedError(forKey: .place, in: values, debugDescription: "Unknown place")
            }
            earlier = true
        }
        self.selection = selection
        viewMode = try values.decodeIfPresent(ItemViewMode.self, forKey: .viewMode) ?? .list
        opensItem = earlier ? nil : try values.decodeIfPresent(Bool.self, forKey: .opensItem)
        scrollOffset = earlier ? nil : try values.decodeIfPresent(Double.self, forKey: .scrollOffset)
    }
}
