import Foundation

/// Where files dropped on a place are added, and what the pill over the place says before they are (`docs/editing.md`).
/// It is fixed when the files are dropped, since the person may move on while they are read and sent.
nonisolated struct FileDropTarget: Equatable, Sendable {
    /// The place the items are made in, which decides their tier: the Feed for the Feed, else the Library.
    let place: Place
    /// The collection the items join: the place's own, or the one the drop was on.
    let collection: ItemID?
    /// What the place is called in the pill: its title, or "the Library" where the place cannot take files.
    let name: String
    /// What the window showed when the files were dropped.
    let shown: PlaceView
    /// Whether the drop was on a collection's row or card, rather than on the list.
    var isOnCollection = false

    /// What the pill says while `count` files are held over the place; Add Files where the count is not known.
    func pill(count: Int) -> String {
        count > 0
            ? AttributedString(localized: "^[Add \(count) File](inflect: true) to \(name)").text
            : String(localized: "Add Files to \(name)")
    }
}

extension Browser {
    /// Where files dropped on the list go. A collection takes them as members, the Feed keeps them in the Feed, and a
    /// type whose items are files lists them. A place that cannot take files, such as a type of notes, a source or the
    /// Archive, adds them to the Library, and the pill says so.
    func fileDropTarget(in library: any ItemLibrary) -> FileDropTarget {
        let place = shown.place
        let inLibrary = FileDropTarget(place: .library, collection: nil, name: String(localized: "the Library"), shown: shown)
        switch place {
        case .feed:
            return FileDropTarget(place: .feed, collection: nil, name: String(localized: "the Feed"), shown: shown)
        case .collection(let id):
            guard let item = library.item(id), item.state != .trashed, library.catalogue.isCollection(item.type) else { return inLibrary }
            return FileDropTarget(place: .library, collection: id, name: item.displayTitle, shown: shown)
        case .type(let type) where library.catalogue.isFileType(type):
            return FileDropTarget(place: .library, collection: nil, name: library.name(of: place), shown: shown)
        default:
            return inLibrary
        }
    }

    /// Where files dropped on the collection `id`'s row or card go, wherever the window is.
    func fileDropTarget(onCollection id: ItemID, in library: any ItemLibrary) -> FileDropTarget {
        FileDropTarget(
            place: .library, collection: id, name: library.item(id)?.displayTitle ?? "", shown: shown, isOnCollection: true)
    }
}
