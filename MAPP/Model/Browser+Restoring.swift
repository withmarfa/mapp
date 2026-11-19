import Foundation

/// Bringing a window back, by the identifiers of what it showed, when the app opens again.
extension Browser {
    /// What a window brings back when the app opens again, by the identifiers of what it showed, which last from
    /// one launch to the next. A snapshot in any other form reads as none.
    struct Snapshot: Codable, Equatable {
        var place: SidebarItem
        var selection: [ItemID]
        var viewMode: ItemViewMode = .list
        /// An item was open from the table or the gallery, not the table or gallery itself.
        var opensItem: Bool?
        /// How far the list, table or gallery was scrolled.
        var scrollOffset: Double?
    }

    /// The most items of a selection a window keeps for the next launch. A selection larger than this is kept as
    /// none, and the list opens at its first rows: saving every id on each change of selection held the main thread
    /// for a selection of thousands, and a restored selection of an arbitrary part of it would mean nothing.
    static let restoredSelectionLimit = 200

    func snapshot() -> Snapshot {
        let kept = selection.count > Self.restoredSelectionLimit ? [] : selection.sorted { $0.rawValue < $1.rawValue }
        return Snapshot(
            place: item, selection: kept, viewMode: viewMode, opensItem: isCollectionItemPresented,
            scrollOffset: listMemory.scrollOffset.map(Double.init))
    }

    /// What a snapshot is made of, as it stands, so a window notices a change without sorting a selection that may
    /// hold every item.
    struct SnapshotParts: Equatable {
        var place: SidebarItem
        var selection: Set<ItemID>
        var viewMode: ItemViewMode
        var opensItem: Bool
    }

    var snapshotParts: SnapshotParts {
        SnapshotParts(place: item, selection: selection, viewMode: viewMode, opensItem: isCollectionItemPresented)
    }

    /// Restores a window from what it kept. A snapshot that does not read, one kept in an earlier form say,
    /// leaves the window at its default.
    func restore(from data: Data?, in library: any ItemLibrary, order: ItemOrder) {
        if let data, let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            restore(snapshot, in: library, order: order)
        } else {
            selectFirstItem(in: library, order: order)
        }
    }

    /// Restores what still exists: a place gone since gives way to All Items, or Favorites for a favorite, and
    /// items no longer in the list are dropped, leaving the top row selected if none remain.
    func restore(_ snapshot: Snapshot, in library: any ItemLibrary, order: ItemOrder) {
        set(layout: snapshot.viewMode)
        let place = snapshot.place
        sidebarItem = switch snapshot.place {
        case .favoriteItem(let id):
            library.item(id).flatMap { $0.isFavorite && $0.state == .active ? snapshot.place : nil } ?? .favorites
        case .collection(let id): library.item(id).map { _ in snapshot.place } ?? .allItems
        case .itemType(let type):
            library.itemTypeCounts.contains { $0.id.rawValue == type } ? snapshot.place : .allItems
        case .view(let id): library.views.contains { $0.id == id } ? snapshot.place : .allItems
        case .inbox, .recents, .allItems, .favorites, .files, .sources, .source, .collections: snapshot.place
        }
        let ids = Set(snapshot.selection)
        selectAutomatically(Set(items(in: library).map(\.id).filter(ids.contains)))
        let keptSelection = !selection.isEmpty
        if selection.isEmpty { selectFirstItem(in: library, order: order) }
        // Only where the window is back in the place it was left, and not with another item chosen in its stead.
        guard item == place else { return }
        if snapshot.opensItem == true, keptSelection, selection.count == 1, usesCollection {
            isCollectionItemPresented = true
        }
        if let offset = snapshot.scrollOffset, offset > 0 { listMemory.restore(to: CGFloat(offset)) }
    }
}

extension Browser.Snapshot {
    /// Recently Deleted, once a place of the sidebar and now a page of Settings, reads as Items with the window's
    /// selection and view kept, and with no scroll offset or open item, which belonged to the old list. Any other place
    /// this build cannot read fails the decoding, so the window opens at its default.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let removedPlace: Bool
        do {
            place = try values.decode(SidebarItem.self, forKey: .place)
            removedPlace = false
        } catch {
            guard let kinds = try? values.nestedContainer(keyedBy: RemovedPlace.self, forKey: .place),
                  kinds.contains(.recentlyDeleted) else { throw error }
            place = .allItems
            removedPlace = true
        }
        selection = try values.decode([ItemID].self, forKey: .selection)
        viewMode = try values.decodeIfPresent(ItemViewMode.self, forKey: .viewMode) ?? .list
        opensItem = removedPlace ? nil : try values.decodeIfPresent(Bool.self, forKey: .opensItem)
        scrollOffset = removedPlace ? nil : try values.decodeIfPresent(Double.self, forKey: .scrollOffset)
    }

    private enum RemovedPlace: String, CodingKey { case recentlyDeleted }
}
