import Foundation
import Marfa

extension ValueEditModel {
    /// The mark an item has in a list of items: its status where its type has one and it holds one, else its type's own.
    func mark(of item: Item) -> ValueListRow.Mark {
        if let group = library.catalogue.statusGroup(of: item) { return .status(group) }
        return .type(icon: library.catalogue.icon(for: item.type))
    }
}
