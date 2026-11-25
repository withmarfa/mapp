import Foundation
import Marfa

extension ValueEditModel {
    /// The collections every item the panel is for is in, which it shows as chips.
    var heldCollections: [Item] {
        let members = library.collectionMembers(request.targets).compactMap(library.item)
        guard let first = members.first else { return [] }
        let common = members.dropFirst().reduce(Set(first.collectionIDs)) { $0.intersection($1.collectionIDs) }
        return library.joinableCollections.filter { common.contains($0.id) }
    }

    static let collectionPrefix = "collection:"

    var collectionRows: [ValueListRow] {
        let held = Set(heldCollections.map(\.id))
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.joinableCollections
            .filter { !held.contains($0.id) && (typed.isEmpty || $0.displayTitle.localizedStandardContains(typed)) }
            .prefix(Self.parentLimit)
            .map {
                ValueListRow(
                    id: Self.collectionPrefix + $0.id.rawValue, role: .option, title: $0.displayTitle,
                    detail: $0.state == .archived ? String(localized: "Archived") : nil,
                    mark: .type(icon: library.catalogue.icon(for: $0.type)))
            }
    }

    /// Files every item the panel is for in the collection. The library tells the person which items it left alone.
    func activateCollection(_ id: String) {
        guard id.hasPrefix(Self.collectionPrefix) else { return }
        let collection = ItemID(String(id.dropFirst(Self.collectionPrefix.count)))
        if library.addToCollection(request.targets, collection, undoManager: request.undoManager) {
            query = ""
            highlight = nil
        }
    }
}
