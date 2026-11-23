import Foundation
import MarfaBrandIcons
import MarfaIcons
import Observation

/// A set of icons the picker offers. The SDK owns the lists; MAPP keeps none.
nonisolated enum IconSet: String, CaseIterable, Identifiable, Sendable {
    case lucide
    case simpleIcons = "simple-icons"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lucide: String(localized: "Lucide")
        case .simpleIcons: String(localized: "Simple Icons")
        }
    }

    /// Every full Iconify ID in the set, such as `lucide:bug`.
    var ids: [String] {
        switch self {
        case .lucide: LucideIconSet.ids
        case .simpleIcons: MarfaBrandIcons.ids
        }
    }

    /// The set an icon ID belongs to, or nil for a bare name or an unknown set.
    init?(iconID: String) {
        guard let prefix = iconID.split(separator: ":", maxSplits: 1).first, let set = IconSet(rawValue: String(prefix)) else {
            return nil
        }
        self = set
    }
}

/// What the icon picker shows and does for one type: the IDs that match the search in the chosen set, the icon the type
/// has now, and the choice made, which goes to the library as a full ID and is drawn at once.
@MainActor @Observable final class TypeIconPickerModel {
    let type: TypeID
    private let library: any ItemLibrary
    private let idsBySet: [IconSet: [String]]
    var search = ""
    var set: IconSet
    private(set) var isWorking = false
    /// Why the last choice was refused, until the next choice or search.
    private(set) var failure: TypeIconFailure?

    /// Opens on the set the type's icon is from. `ids` replaces the SDK's lists, for tests.
    init(type: TypeID, library: any ItemLibrary, ids: [IconSet: [String]]? = nil) {
        self.type = type
        self.library = library
        self.idsBySet = ids ?? Dictionary(uniqueKeysWithValues: IconSet.allCases.map { ($0, $0.ids) })
        self.set = library.catalogue.icon(for: type).flatMap(IconSet.init(iconID:)) ?? .lucide
    }

    var typeLabel: String { library.catalogue.label(for: type) }
    /// The icon the type shows now, so the grid can mark it.
    var current: String? { library.catalogue.icon(for: type) }
    var results: [String] { IconNameSearch.matching(search, in: idsBySet[set] ?? []) }
    /// Whether the grid and Use Default take a click: with a server to keep the choice, and none being written.
    var canChoose: Bool { library.reachesServer && !isWorking }
    /// Cancel waits for the write in flight, since closing the sheet would not stop it and the person would not see
    /// whether it was kept.
    var canCancel: Bool { !isWorking }

    /// Chooses the icon `id`, a full Iconify ID, for the type. True when the server took it, so the picker can close.
    func choose(_ id: String?) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        failure = await library.setIcon(id, ofType: type)
        return failure == nil
    }
}
