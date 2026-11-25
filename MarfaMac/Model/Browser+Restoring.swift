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
        /// The place as a later copy wrote it, where this copy cannot read all of it: a place word it does not know, or
        /// a view word. Written back as it was while the window stays where it opened (`LaterPlace`).
        var laterPlace: [String: String]?

        /// Whether the place is one this copy knows, so the window can open in it.
        var knowsPlace: Bool { laterPlace?["place"].flatMap(Place.init(word:)) != nil || laterPlace == nil }
    }

    /// A place a later copy wrote that this copy reads only in part, and where the window opened for it.
    struct LaterPlace {
        var written: [String: String]
        var opened: PlaceView?
    }

    /// The most items of a selection a window keeps for the next launch. A selection larger than this is kept as
    /// none, and the list opens at its first rows: saving every id on each change of selection held the main thread
    /// for a selection of thousands, and a restored selection of an arbitrary part of it would mean nothing.
    static let restoredSelectionLimit = 200

    func snapshot() -> Snapshot {
        let kept = selection.count > Self.restoredSelectionLimit ? [] : selection.sorted { $0.rawValue < $1.rawValue }
        return Snapshot(
            place: shown, selection: kept, viewMode: viewMode, opensItem: isCollectionItemPresented,
            scrollOffset: listMemory.scrollOffset.map(Double.init), laterPlace: keptLaterPlace)
    }

    /// The place a later copy wrote, while the window is still where it opened for it.
    var keptLaterPlace: [String: String]? {
        guard let laterPlace, laterPlace.opened == showing else { return nil }
        return laterPlace.written
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
    func restore(
        from data: Data?, in library: any ItemLibrary, order: ItemOrder, start: (place: PlaceView, selecting: ItemID?)? = nil
    ) {
        let snapshot = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let startKeys = [StartWith.earlierKey, StartWith.earlierLastPlaceKey].compactMap { defaults.string(forKey: $0) }
        if snapshot?.leftFiles == true || (snapshot == nil && startKeys.contains { EarlierPlace.read(key: $0) == .files }) {
            EarlierPlace.tellFilesOnce(library.notices, in: defaults)
        }
        let opening = start.map { Snapshot(place: $0.place, selection: $0.selecting.map { [$0] } ?? []) }
        if var snapshot {
            // A place this copy does not know opens where a new window would, and is written back as it was.
            if !snapshot.knowsPlace {
                snapshot.place = opening?.place ?? .library
                (snapshot.opensItem, snapshot.scrollOffset) = (nil, nil)
            }
            restore(snapshot, in: library, order: order)
            laterPlace = snapshot.laterPlace.map { LaterPlace(written: $0, opened: showing) }
        } else if let opening {
            restore(opening, in: library, order: order)
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
    /// page of Settings, reads as the Library. Where one earlier place stands for the new one, the window keeps its open
    /// item and scroll offset; Recents, one favorite, Files and Recently Deleted listed other items, so they keep only the
    /// selection and view. A place a later copy wrote is kept as written (`laterPlace`). Any other place fails the
    /// decoding, so the window opens at its default.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var selection = try values.decode([ItemID].self, forKey: .selection)
        var keepsPosition = true
        if let words = try? values.decode([String: String].self, forKey: .place), let placeWord = words["place"] {
            let viewWord = words["view"] ?? ViewChoice.own.word
            let view = ViewChoice(word: viewWord)
            if let known = Place(word: placeWord) {
                place = PlaceView(known, view)
                if view.word != viewWord { laterPlace = words }
            } else {
                place = .library
                laterPlace = words
            }
        } else {
            let object = try values.decode([String: [String: String]].self, forKey: .place)
            guard object.count == 1, let (name, value) = object.first else { throw DecodingError.dataCorruptedError(
                forKey: .place, in: values, debugDescription: "Unknown place") }
            switch name == "recentlyDeleted" ? .place(.library) : EarlierPlace.read(name: name, value: value["_0"]) {
            case .place(let place, let chosen)?:
                self.place = place
                if let chosen { selection = [chosen] }
                keepsPosition = chosen == nil && !["recents", "recentlyDeleted"].contains(name)
            case .files?:
                self.place = .library
                leftFiles = true
                keepsPosition = false
            case nil:
                throw DecodingError.dataCorruptedError(forKey: .place, in: values, debugDescription: "Unknown place")
            }
        }
        self.selection = selection
        viewMode = try values.decodeIfPresent(ItemViewMode.self, forKey: .viewMode) ?? .list
        opensItem = keepsPosition ? try values.decodeIfPresent(Bool.self, forKey: .opensItem) : nil
        scrollOffset = keepsPosition ? try values.decodeIfPresent(Double.self, forKey: .scrollOffset) : nil
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        if let laterPlace { try values.encode(laterPlace, forKey: .place) } else { try values.encode(place, forKey: .place) }
        try values.encode(selection, forKey: .selection)
        try values.encode(viewMode, forKey: .viewMode)
        try values.encodeIfPresent(opensItem, forKey: .opensItem)
        try values.encodeIfPresent(scrollOffset, forKey: .scrollOffset)
    }
}
