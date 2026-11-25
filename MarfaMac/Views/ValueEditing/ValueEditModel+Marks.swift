import Foundation
import Marfa

extension ValueEditModel {
    /// The mark an item has in a list of items: its status where its type has one and it holds one, a collection's the
    /// one its places wear, else its type's own.
    func mark(of item: Item) -> ValueListRow.Mark {
        if let group = library.catalogue.statusGroup(of: item) { return .status(group) }
        if library.catalogue.isCollection(item.type), let symbol = SidebarPlace.collections.symbol { return .symbol(symbol) }
        return .type(icon: library.catalogue.icon(for: item.type))
    }
}
