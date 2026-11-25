import Foundation
import Marfa

extension ValueEditModel {
    /// The collections the panel lists now, whose member counts it shows beside them.
    var listedCollections: [ItemID] {
        guard case .relation = kind else { return [] }
        return rows.compactMap { row in linkTarget(of: row.id).flatMap { isCollection($0) ? $0 : nil } }
    }

    /// The count beside a collection's row, or nil until Marfa has answered, so the row draws nothing in its place.
    func countText(of row: ValueListRow) -> String? {
        guard case .relation = kind, let id = linkTarget(of: row.id), isCollection(id) else { return nil }
        return library.counts.answer(of: id, .members).map { $0.total.formatted() }
    }

    /// Asks for the counts of `ids` and lets go of those no longer listed. The panel's view calls it when the rows
    /// change, never while it draws (`ItemCounts.want`).
    func wantCounts(of ids: [ItemID]) {
        guard !isFinished else { return }
        let now = Set(ids)
        library.counts.release(countedCollections.subtracting(now), .members)
        library.counts.want(now.subtracting(countedCollections), .members)
        countedCollections = now
    }

    /// Lets go of every count the panel asked for.
    func releaseCounts() {
        library.counts.release(countedCollections, .members)
        countedCollections = []
    }

    private func isCollection(_ id: ItemID) -> Bool {
        library.item(id).map { library.catalogue.isCollection($0.type) } ?? false
    }
}
