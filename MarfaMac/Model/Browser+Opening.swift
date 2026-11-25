import Foundation

/// Opening an item the way the place's Open Items, or Settings > General > Open Items, says (`ItemOpening`): beside
/// the list, in the modal over the window, as a full page, or in a window of its own. Every layout and the list open
/// through here.
extension Browser {
    /// Whether an item is open in the modal.
    var isModalPresented: Bool { modalItem != nil }

    /// Opens `ids` as `way`, or as the place says when none is given (`itemOpening`). A column, a modal and a full page need exactly
    /// one item; windows take every item chosen (the ask before many is the window opener's).
    /// Whether it opened anything, which a key handler answers with.
    @discardableResult
    func open(_ ids: Set<ItemID>, as way: ItemOpening? = nil, defaults: UserDefaults = .standard) -> Bool {
        let way = way ?? itemOpening(defaults: defaults)
        guard way.canOpen(ids.count), let id = ids.first else { return false }
        switch way {
        case .newWindow: windowOpener?(ids)
        case .besideList: presentBeside(id)
        case .modal: presentModal(id)
        case .fullPage: presentFullPage(id)
        }
        return true
    }

    /// Opens the selection, which is what Return opens.
    @discardableResult
    func openSelection(as way: ItemOpening? = nil) -> Bool { open(selection, as: way) }

    /// Chooses the item, whose page is then in the column beside the layout, and gives it the keyboard. A layout that
    /// spans the window keeps its place, and a full page that was open gives the layout back.
    private func presentBeside(_ id: ItemID) {
        isCollectionItemPresented = false
        modalItem = nil
        if selection != [id] { selection = [id] }
        focusRequest = .page
    }

    /// Whether the page is in a column beside a layout that spans the window, which `opening` says it is to be and
    /// the window can show: one item is chosen and nothing has taken the window's editor (the modal, a full page).
    func showsBesidePage(opening: ItemOpening) -> Bool {
        opening == .besideList && showsCollection && !isModalPresented && selection.count == 1
    }

    /// How a link followed from a page in a layout that spans the window opens: where the page already is, beside
    /// the layout, with Beside the List, and as a full page otherwise, since the modal and a window are chosen apart.
    func wayToFollowInCollection(defaults: UserDefaults = .standard) -> ItemOpening {
        itemOpening(defaults: defaults) == .besideList ? .besideList : .fullPage
    }

    private func presentModal(_ id: ItemID) {
        // A full page and the modal never show the page at once: the modal is over the layout the full page left.
        isCollectionItemPresented = false
        if selection != [id] { selection = [id] }
        modalItem = id
        focusRequest = nil
    }

    private func presentFullPage(_ id: ItemID) {
        if selection != [id] { selection = [id] }
        modalItem = nil
        isCollectionItemPresented = true
        focusRequest = nil
    }

    /// Brings the list's search out as a field, which takes the keyboard. An open item, full page or modal, gives way to
    /// it in every layout, since the search belongs to the list.
    func showSearchField() {
        isCollectionItemPresented = false
        closeModal(returningFocus: false)
        isSearchExpanded = true
        searchFocusRequests += 1
    }

    /// Puts the modal away, and gives the keyboard back to the layout behind it unless something else is taking it.
    func closeModal(returningFocus: Bool = true) {
        guard modalItem != nil else { return }
        modalItem = nil
        if returningFocus { focusRequest = .list }
    }

    nonisolated enum ModalStep: Sendable { case previous, next }

    /// The items in the order of what is behind the modal: the table's rows, and for every other
    /// layout the list's sections, which follow the filters and the sort.
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

    /// Moves the modal to the item before or after it, and the selection with it, which adds no step to Back: stepping
    /// through a list is not a trail to walk back. Nothing happens at either end.
    func moveModal(_ step: ModalStep, in library: any ItemLibrary, order: ItemOrder) {
        let neighbors = modalNeighbors(in: library, order: order)
        guard let target = step == .previous ? neighbors.previous : neighbors.next else { return }
        moveModal(to: target)
    }

    /// Moves the modal, and the selection with it, to `target`, which Keep does for the item after the one it kept.
    func moveModal(to target: ItemID) {
        // First, so the selection that follows is the modal's item and does not end it.
        modalItem = target
        selectAutomatically([target])
    }
}
