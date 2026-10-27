import MarfaIcons
import Observation

/// What the icon picker shows and does for one type: the names that match the search, the icon the type has now, and
/// the choice made, which goes to the library and is drawn at once.
@MainActor @Observable final class TypeIconPickerModel {
    let type: TypeID
    private let library: any ItemLibrary
    private let names: [String]
    var search = ""
    private(set) var isWorking = false
    /// Why the last choice was refused, until the next choice or search.
    private(set) var failure: TypeIconFailure?

    init(type: TypeID, library: any ItemLibrary, names: [String] = LucidePinned.names) {
        self.type = type
        self.library = library
        self.names = names
    }

    var typeLabel: String { library.catalogue.label(for: type) }
    /// The icon the type shows now, so the grid can mark it.
    var current: String? { library.catalogue.icon(for: type) }
    var results: [String] { IconNameSearch.matching(search, in: names) }
    var canChoose: Bool { library.canChooseTypeIcons && !isWorking }

    /// Chooses `name` for the type. True when the server took it, so the picker can close.
    func choose(_ name: String?) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        failure = await library.setIcon(name, ofType: type)
        return failure == nil
    }
}
