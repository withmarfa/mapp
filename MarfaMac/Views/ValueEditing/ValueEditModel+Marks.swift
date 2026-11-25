import Foundation
import Marfa

extension ValueEditModel {
    /// The mark an item has in a list of items: its status where its type has one and it holds one, else its type's own.
    func mark(of item: Item) -> ValueListRow.Mark {
        if let group = library.catalogue.statusGroup(of: item) { return .status(group) }
        return .type(icon: library.catalogue.icon(for: item.type))
    }

    /// The parent panel's rows with each item's mark in place of the words of its type.
    func marked(parentRows rows: [ValueListRow]) -> [ValueListRow] {
        let candidates = Dictionary(parentCandidates.map { ("parent:" + $0.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.map { row in
            guard let item = candidates[row.id] else { return row }
            var row = row
            row.mark = mark(of: item)
            row.detail = nil
            return row
        }
    }
}
