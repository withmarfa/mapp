import Foundation
import Marfa

extension ValueEditModel {
    /// The collections the panel lists now, whose member counts it shows beside them.
    var listedCollections: [ItemID] {
        guard kind == .collections else { return [] }
        return rows.compactMap { $0.id.hasPrefix(Self.collectionPrefix) ? ItemID(String($0.id.dropFirst(Self.collectionPrefix.count))) : nil }
    }

    /// The count beside a collection's row, or nil until Marfa has answered, so the row draws nothing in its place.
    func countText(of row: ValueListRow) -> String? {
        guard kind == .collections, row.id.hasPrefix(Self.collectionPrefix) else { return nil }
        let id = ItemID(String(row.id.dropFirst(Self.collectionPrefix.count)))
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
}
