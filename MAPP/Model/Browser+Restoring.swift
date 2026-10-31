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
    func restore(from data: Data?, in library: any ItemLibrary, order: NoteOrder) {
        if let data, let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            restore(snapshot, in: library, order: order)
        } else {
            selectFirstNote(in: library, order: order)
        }
    }

    /// Restores what still exists: a place gone since gives way to All Notes, or Favorites for a favorite, and
    /// items no longer in the list are dropped, leaving the top row selected if none remain.
    func restore(_ snapshot: Snapshot, in library: any ItemLibrary, order: NoteOrder) {
        viewMode = snapshot.viewMode
        let place = snapshot.place
        sidebarItem = switch snapshot.place {
        case .favoriteItem(let id):
            library.item(id).flatMap { $0.isFavorite && $0.state == .active ? snapshot.place : nil } ?? .favorites
        case .collection(let id): library.item(id).map { _ in snapshot.place } ?? .allNotes
        case .itemType(let type):
            library.itemTypeCounts.contains { $0.id.rawValue == type } ? snapshot.place : .allNotes
        case .view(let id): library.views.contains { $0.id == id } ? snapshot.place : .allNotes
        case .inbox, .recents, .allNotes, .favorites, .files, .sources, .source, .collections, .recentlyDeleted: snapshot.place
        }
        let ids = Set(snapshot.selection)
        selectAutomatically(Set(items(in: library).map(\.id).filter(ids.contains)))
        let keptSelection = !selection.isEmpty
        if selection.isEmpty { selectFirstNote(in: library, order: order) }
        // Only where the window is back in the place it was left, and not with another item chosen in its stead.
        guard item == place else { return }
        if snapshot.opensItem == true, keptSelection, selection.count == 1, usesCollection {
            isCollectionItemPresented = true
        }
        if let offset = snapshot.scrollOffset, offset > 0 { listMemory.restore(to: CGFloat(offset)) }
    }
}
