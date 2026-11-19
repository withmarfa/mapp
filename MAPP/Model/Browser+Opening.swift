import Foundation

/// Opening an item the way Settings > Lists > Open Items In says (`ItemOpening`): in the modal over the window, as a
/// full page, or in a window of its own. Every layout and the list open through here.
extension Browser {
    /// Whether an item is open in the modal.
    var isModalPresented: Bool { modalItem != nil }

    /// Opens `ids` as `way`, or as Settings says when none is given. A modal and a full page need exactly one item;
    /// windows take every item chosen (the ask before many is the window opener's).
    /// Whether it opened anything, which a key handler answers with.
    @discardableResult
    func open(_ ids: Set<ItemID>, as way: ItemOpening? = nil) -> Bool {
        let way = way ?? ItemOpening.stored()
        guard way.canOpen(ids.count), let id = ids.first else { return false }
        switch way {
        case .newWindow: windowOpener?(ids)
        case .modal: presentModal(id)
        case .fullPage: presentFullPage(id)
        }
        return true
    }

    /// Opens the selection, which is what Return opens.
    @discardableResult
    func openSelection(as way: ItemOpening? = nil) -> Bool { open(selection, as: way) }

    private func presentModal(_ id: ItemID) {
        leaveSettings()
        // A full page and the modal never show the page at once: the modal is over the layout the full page left.
        isCollectionItemPresented = false
        if selection != [id] { selection = [id] }
        modalItem = id
        focusRequest = nil
    }

    private func presentFullPage(_ id: ItemID) {
        leaveSettings()
        if selection != [id] { selection = [id] }
        modalItem = nil
        isCollectionItemPresented = true
        focusRequest = nil
    }

    /// Puts the modal away, and gives the keyboard back to the layout behind it unless something else is taking it.
    func closeModal(returningFocus: Bool = true) {
        guard modalItem != nil else { return }
        modalItem = nil
        if returningFocus { focusRequest = .list }
    }

    nonisolated enum ModalStep: Sendable { case previous, next }

    /// The items in the order of the layout behind the modal: the table's rows, and for every other layout the list's
    /// sections, which follow the filters and the sort.
    func orderBehind(in library: any ItemLibrary, order: ItemOrder) -> [ItemID] {
        if viewMode == .table {
            let content = tableContent(in: library)
            let rows = content.grouping == nil ? content.rows : content.groups.flatMap(\.rows)
            return rows.map(\.item.id)
        }
        return sections(in: library, order: order, now: library.now()).flatMap { $0.items.map(\.id) }
    }

    /// The items the modal's arrows go to.
    func modalNeighbors(in library: any ItemLibrary, order: ItemOrder) -> ListNeighbors {
        guard let id = modalItem else { return ListNeighbors(of: ItemID(""), in: []) }
        return ListNeighbors(of: id, in: orderBehind(in: library, order: order))
    }

    /// Moves the modal to the item before or after it, and the selection with it. Nothing happens at either end.
    func moveModal(_ step: ModalStep, in library: any ItemLibrary, order: ItemOrder) {
        let neighbors = modalNeighbors(in: library, order: order)
        guard let target = step == .previous ? neighbors.previous : neighbors.next else { return }
        // First, so the selection that follows is the modal's item and does not end it.
        modalItem = target
        selection = [target]
    }
}
