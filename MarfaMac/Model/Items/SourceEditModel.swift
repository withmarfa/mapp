import Foundation
import Observation

/// What the sheet that renames a source or chooses its mark shows and does for one source. Both go to the server, for
/// every app, and what it refuses is kept for the sheet to show.
@MainActor @Observable final class SourceEditModel {
    enum Mode: Hashable, Sendable { case name, mark }

    let code: String
    let mode: Mode
    private let library: any ItemLibrary
    private let idsBySet: [IconSet: [String]]
    var name: String
    var search = ""
    var set: IconSet
    private(set) var isWorking = false
    /// Why the last change was refused, until the next change.
    private(set) var failure: SourceEditFailure?

    /// Opens on the source's name, and on the set its mark is from. `ids` replaces the SDK's lists, for tests.
    init(code: String, mode: Mode, library: any ItemLibrary, ids: [IconSet: [String]]? = nil) {
        self.code = code
        self.mode = mode
        self.library = library
        self.idsBySet = ids ?? (mode == .mark ? Dictionary(uniqueKeysWithValues: IconSet.allCases.map { ($0, $0.ids) }) : [:])
        let info = library.sources.info(code)
        name = info.name
        set = info.mark.flatMap(IconSet.init(iconID:)) ?? .lucide
    }

    /// The source as the sheet last read it, so a change made meanwhile shows.
    var current: SourceInfo { library.sources.info(code) }
    var results: [String] { IconNameSearch.matching(search, in: idsBySet[set] ?? []) }
    /// Whether a change takes a click: with a server to keep it, and none being written.
    var canChange: Bool { library.reachesServer && !isWorking }
    var canCancel: Bool { !isWorking }
    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canRename: Bool { canChange && !trimmedName.isEmpty && trimmedName != current.name }
    /// Taking the name back to the one an app or key gives, which only a name set on the source has to be.
    var canUseDefaultName: Bool { canChange && current.hasChosenName }
    var canRemoveMark: Bool { canChange && current.mark != nil }

    /// True when the server took the change, so the sheet can close.
    func rename() async -> Bool {
        guard canRename else { return false }
        return await change(name: .set(trimmedName), mark: nil)
    }

    func useDefaultName() async -> Bool {
        guard canUseDefaultName else { return false }
        return await change(name: .clear, mark: nil)
    }

    /// Chooses the mark `id`, a full Iconify ID, or removes it where nil.
    func chooseMark(_ id: String?) async -> Bool {
        guard canChange else { return false }
        return await change(name: nil, mark: id.map { .set($0) } ?? .clear)
    }

    private func change(name: SourceFieldChange?, mark: SourceFieldChange?) async -> Bool {
        isWorking = true
        failure = nil
        defer { isWorking = false }
        failure = await library.updateSource(code, name: name, mark: mark)
        return failure == nil
    }
}
