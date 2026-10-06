import Foundation
import Observation

/// What the two views of Marfa's types share: the catalogue, the type chosen, the search, and the types shown so
/// far, which Back and Forward move through as a browser's do. The list and the page for the chosen type are views
/// of it, so it holds no view state and is tested on its own.
@Observable @MainActor
final class TypesBrowser {
    var catalogue: Catalogue {
        didSet { reconcile() }
    }
    var searchText = ""
    private(set) var selection: TypeSelection?
    /// Each type chosen, in order, with `position` at the one shown. Choosing anew drops what lay ahead.
    private var history: [TypeSelection] = []
    private var position = -1

    init(catalogue: Catalogue = Catalogue()) {
        self.catalogue = catalogue
    }

    // MARK: Choosing

    /// Chooses a type. One the catalogue lacks is ignored, and choosing the one already shown adds nothing to the
    /// history. Nil clears the choice, which the history keeps: Back returns to it.
    func select(_ new: TypeSelection?) {
        guard new != selection else { return }
        guard let new else {
            selection = nil
            return
        }
        guard contains(new) else { return }
        selection = new
        // A choice cleared and made again is the same stop, not a new one.
        if position >= 0, history[position] == new { return }
        history.removeSubrange((position + 1)...)
        history.append(new)
        position = history.count - 1
    }

    var canGoBack: Bool { selection == nil ? position >= 0 : position > 0 }
    var canGoForward: Bool { position < history.count - 1 }

    func goBack() {
        guard canGoBack else { return }
        if selection != nil { position -= 1 }
        selection = history[position]
    }

    func goForward() {
        guard canGoForward else { return }
        position += 1
        selection = history[position]
    }

    private func contains(_ selection: TypeSelection) -> Bool {
        switch selection {
        case .item(let id): catalogue.itemTypes[id] != nil
        case .edge(let id): catalogue.edgeTypes[id] != nil
        }
    }

    /// A catalogue that has changed may have lost types the history names.
    private func reconcile() {
        var kept: [TypeSelection] = []
        var newPosition = -1
        for (index, entry) in history.enumerated() {
            if contains(entry), kept.last != entry { kept.append(entry) }
            if index == position { newPosition = kept.count - 1 }
        }
        history = kept
        position = newPosition
        if let selection, !contains(selection) { self.selection = nil }
    }

    // MARK: Showing

    private var query: TypeQuery? { TypeQuery(searchText) }

    var isSearching: Bool { query != nil }

    /// The item types as a tree, narrowed to the matches and what they sit under while searching.
    var itemTree: [TypeNode] { TypeTree.nodes(in: catalogue, matching: query) }

    /// The tree in reading order, for showing it open throughout, as a search does.
    var itemRows: [TypeNode] { TypeTree.flattened(itemTree) }

    var edgeTypes: [EdgeTypeInfo] {
        let all = TypeTree.ordered(Array(catalogue.edgeTypes.values))
        guard let query else { return all }
        return all.filter(query.matches)
    }

    var hasResults: Bool { !itemTree.isEmpty || !edgeTypes.isEmpty }

    var selectedItemType: ItemTypeDetail? {
        guard case .item(let id) = selection, let type = catalogue.itemTypes[id] else { return nil }
        return ItemTypeDetail(type, in: catalogue)
    }

    var selectedEdgeType: EdgeTypeDetail? {
        guard case .edge(let id) = selection, let edge = catalogue.edgeTypes[id] else { return nil }
        return EdgeTypeDetail(edge, in: catalogue)
    }
}
