import Observation
import SwiftUI

/// The rows of an index page, worked out once and again only when what they read changes. Reading the library's
/// items for every redraw would walk them all each time the person types in the search or picks a layout.
@MainActor
@Observable
final class IndexRowsModel {
    private var built: [IndexRow] = []
    /// The color slots of the types in all of the rows, worked out with them, so searching never recolors a type.
    private(set) var slots = IndexSlots()
    /// The place the rows are of; nil until they have been worked out.
    private(set) var builtPlace: IndexPlace?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var library: (any ItemLibrary)?

    /// The rows of `place`, empty while the model holds another place's, so a page never shows one place's rows
    /// under another.
    func rows(for place: IndexPlace) -> [IndexRow] { builtPlace == place ? built : [] }

    /// False until the rows of `place` have been worked out, so a page does not say it is empty first.
    func isBuilt(for place: IndexPlace) -> Bool { builtPlace == place }

    func follow(_ place: IndexPlace, in library: any ItemLibrary) {
        generation += 1
        builtPlace = nil
        built = []
        slots = IndexSlots()
        self.library = library
        rebuild(place, generation: generation)
    }

    func stop() {
        generation += 1
        library = nil
        builtPlace = nil
        built = []
        slots = IndexSlots()
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
        if built != next {
            built = next
            slots = IndexSlots(rows: next)
        }
        builtPlace = place
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
