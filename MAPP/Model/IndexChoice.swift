import Observation

/// The container chosen in an index table, which the right sidebar shows. Held apart from the table's rows so that
/// choosing one runs no row's body: only the table's selection and the right sidebar read it.
@MainActor
@Observable
final class IndexChoice {
    var chosen: SidebarItem?

    /// Clears the choice when its container is no longer among `rows`: deleted, gone on a sync, or left out by the tab or
    /// the search. A choice among them stays.
    func keep(within rows: [IndexRow]) {
        guard let chosen, !rows.contains(where: { $0.id == chosen }) else { return }
        self.chosen = nil
    }

    /// The row the right sidebar shows: the chosen container's, while `rows` still holds it.
    func row(in rows: [IndexRow]) -> IndexRow? {
        chosen.flatMap { chosen in rows.first { $0.id == chosen } }
    }
}
