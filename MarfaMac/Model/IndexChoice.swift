import Observation

/// The container chosen in an index table, which the right sidebar shows. Held apart from the table's rows so that
/// choosing one runs no row's body: only the table's selection and the right sidebar read it.
@MainActor
@Observable
final class IndexChoice {
    var chosen: Place?

    /// Clears the choice when its container is no longer among `rows`, the page's every row: deleted, or gone on a sync.
    /// A container the tab or the search leaves out of the table stays chosen.
    func keep(within rows: [IndexRow]) {
        guard let chosen, !rows.contains(where: { $0.id == chosen }) else { return }
        self.chosen = nil
    }

    /// The row the right sidebar shows: the chosen container's, while `rows` still holds it.
    func row(in rows: [IndexRow]) -> IndexRow? {
        chosen.flatMap { chosen in rows.first { $0.id == chosen } }
    }
}
