import Foundation

/// The row of a place's views: their order, which the app keeps for each place (`ViewOrders`), the views hidden from it,
/// and what a pill's menu and drag do.
extension Browser {
    /// Every view of `place` in the person's order: its own, the Library's Favorites, then its saved views. Hidden
    /// ones are among them, since More still lists them.
    func viewChoices(in place: Place, library: any ItemLibrary) -> [ViewChoice] {
        let orders = ViewOrders.stored(in: defaults)
        var all: [ViewChoice] = [.own]
        if place == .library { all.append(.favorites) }
        all += library.views(in: place, order: orders.savedOrder(in: place)).map { .saved($0.id) }
        return orders.arranged(all, in: place)
    }

    /// The views the person hid from the row of `place`.
    func hiddenViews(in place: Place) -> Set<ViewChoice> {
        ViewOrders.stored(in: defaults).hidden(in: place)
    }

    /// Hides a view from the row, or shows it again. The view itself stays, in More and in every other app. A hidden
    /// view the window shows moves the window to the row's first view.
    func setHidden(_ view: ViewChoice, _ isHidden: Bool, in place: Place, library: any ItemLibrary, order: ItemOrder) {
        guard view != .own else { return }
        ViewOrders.update(in: defaults) { $0.setHidden(view, isHidden, in: place) }
        if isHidden, shown.place == place, shown.view == view { showFirstView(of: place, in: library, order: order) }
    }

    /// Puts `moved` where `target` stands in the row of `place`, the order every view of the place then keeps.
    func moveView(_ moved: ViewChoice, onto target: ViewChoice, in place: Place, library: any ItemLibrary) {
        var views = viewChoices(in: place, library: library)
        guard moved != target, let from = views.firstIndex(of: moved), let to = views.firstIndex(of: target) else { return }
        views.remove(at: from)
        views.insert(moved, at: to)
        ViewOrders.update(in: defaults) { $0.set(views, in: place) }
    }

    /// The first view of the row of `place`.
    func firstView(of place: Place, in library: any ItemLibrary) -> PlaceView {
        let hidden = hiddenViews(in: place)
        return PlaceView(place, viewChoices(in: place, library: library).first { !hidden.contains($0) } ?? .own)
    }

    func showFirstView(of place: Place, in library: any ItemLibrary, order: ItemOrder) {
        show(firstView(of: place, in: library), in: library, order: order)
    }
}
