import Observation
import SwiftUI

/// The rows of an index page, worked out once and again only when what they read changes. Reading the library's
/// items for every redraw would walk them all each time the person types in the search or picks a layout.
@MainActor
@Observable
final class IndexRowsModel {
    private(set) var rows: [IndexRow] = []
    /// False until the rows have been worked out, so a page does not say it is empty first.
    private(set) var isBuilt = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var library: (any ItemLibrary)?

    func follow(_ place: IndexPlace, in library: any ItemLibrary) {
        generation += 1
        isBuilt = false
        self.library = library
        rebuild(place, generation: generation)
    }

    func stop() {
        generation += 1
        library = nil
    }

    private func rebuild(_ place: IndexPlace, generation: Int) {
        guard let library else { return }
        let next = withObservationTracking {
            Self.rows(for: place, in: library)
        } onChange: { [weak self] in
            // Called before the change lands, so the rows are read again after it.
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.rebuild(place, generation: generation)
            }
        }
        if rows != next { rows = next }
        isBuilt = true
    }

    private static func rows(for place: IndexPlace, in library: any ItemLibrary) -> [IndexRow] {
        switch place {
        case .sources:
            IndexRows.sources(of: library.items(in: .allNotes), catalogue: library.catalogue)
        case .collections:
            IndexRows.collections(
                library.collections, membersOf: { library.items(in: .collection($0.id)) }, catalogue: library.catalogue)
        }
    }
}
