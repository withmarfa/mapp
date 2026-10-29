import Foundation

/// What the command palette lists apart from its commands, worked out once for each revision of the library and not
/// for each keystroke: the places it can open, and every item most recently edited first.
struct PaletteIndex {
    struct Place {
        let item: SidebarItem
        let icon: RowIcon
        /// Nil where the library names the place itself (`ItemLibrary.name(of:)`).
        let title: String?
    }

    let places: [Place]
    /// The active items, most recently edited first.
    let recent: [Item]
}

struct PaletteIndexKey: Equatable {
    let library: ObjectIdentifier
    let content: Int
    let membership: Int
    let views: [LibraryView]
}

extension Browser {
    /// The palette's places and items, kept until the library's items, catalogue or views change. Reading it observes
    /// those revisions, so a palette that is out is told of the next change.
    func paletteIndex(in library: any ItemLibrary) -> PaletteIndex {
        let key = PaletteIndexKey(
            library: ObjectIdentifier(library), content: library.contentRevision, membership: library.membershipRevision,
            views: library.views)
        if let held = paletteMemo, held.key == key { return held.index }
        let index = Cost.measure(.paletteIndex) { Self.makePaletteIndex(in: library) }
        paletteMemo = (key, index)
        return index
    }

    private static func makePaletteIndex(in library: any ItemLibrary) -> PaletteIndex {
        var places: [PaletteIndex.Place] = (SidebarPlace.destinations + SidebarPlace.builtInViews).compactMap { place in
            place.item.flatMap { item in place.symbol.map { PaletteIndex.Place(item: item, icon: .symbol($0), title: nil) } }
        }
        places.append(.init(item: .recentlyDeleted, icon: .symbol("trash"), title: nil))
        places += library.sourceCounts.map {
            .init(item: .source($0.name), icon: .symbol("antenna.radiowaves.left.and.right"), title: $0.name)
        }
        places += library.collections.map {
            .init(item: .collection($0.id), icon: .type(library.catalogue.icon(for: $0.type)), title: $0.title)
        }
        // The types the sidebar shows, under the names it gives them.
        places += library.itemTypeCounts.map { .init(item: .itemType($0.id.rawValue), icon: .type($0.icon), title: $0.label) }
        places += library.views.map { .init(item: .view($0.id), icon: .symbol(SidebarPlace.viewSymbol), title: $0.title) }
        return PaletteIndex(places: places, recent: library.items(in: .allNotes).sorted { $0.modified > $1.modified })
    }
}
