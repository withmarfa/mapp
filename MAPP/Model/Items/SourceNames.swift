import Foundation

/// A source as the server names it: the code that items carry in `source`, the name to show for it and the mark to
/// draw beside the name.
nonisolated struct SourceInfo: Identifiable, Hashable, Sendable {
    let code: String
    /// Never empty.
    let name: String
    /// An icon ID from the sets a type's icon comes from, drawn by `TypeGlyph`.
    let mark: String?
    /// Whether the name was set on the source itself, so the person can take it back to the one an app or key gives.
    let hasChosenName: Bool

    var id: String { code }

    /// What stands in for a source the server has not named: its code.
    static func unnamed(_ code: String) -> SourceInfo { SourceInfo(code: code, name: code, mark: nil, hasChosenName: false) }
}

/// What the library knows of its sources from the server: their names and marks, and how many items each wrote.
/// Neither is held by the working copy, so both are empty until the server has answered, and the last answer stays
/// while it cannot be reached.
nonisolated struct SourceDirectory: Equatable, Sendable {
    var infos: [String: SourceInfo] = [:]
    /// Items per source in the library's places (`SourceNameSource.counts`); nil until the server has answered.
    var counts: [String: Int]?

    /// The source `code`, or the code standing in for its name while the server has not named it.
    func info(_ code: String) -> SourceInfo { infos[code] ?? .unnamed(code) }
    func name(_ code: String) -> String { info(code).name }

    /// The sources a list shows, by name, each with its count. Once the server has answered, they are its sources
    /// that hold items (the last answer, while it cannot be reached); until then, the sources of the items loaded,
    /// counted as `loaded` has them. The one place that chooses the sources, counts and order.
    func listing(loaded: [String: Int]) -> [(code: String, name: String, count: Int)] {
        (counts?.filter { $0.value > 0 } ?? loaded).filter { !$0.key.isEmpty }
            .map { (code: $0.key, name: name($0.key), count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// One field of a source, changed or taken back.
nonisolated enum SourceFieldChange: Hashable, Sendable {
    case set(String)
    /// Removes the field, so the source shows the name its app or key gives it, or its code, and no mark.
    case clear
}

/// Why the server did not read or change a source, in terms a sheet can word for a person.
nonisolated enum SourceEditFailure: Error, Hashable, Sendable {
    case unreachable
    /// The sign-in lacks `keys.manage`, which a source the key does not own needs.
    case notPermitted
    case keyRefused
    /// The server refused the name or mark, with its own sentence.
    case refused(String)
    /// This library has no server to keep the change.
    case unsupported
    case failed(String)

    var message: String {
        switch self {
        case .unreachable:
            String(localized: "MAPP can’t reach the server. Changing a source needs the server, so try again once it’s back.")
        case .notPermitted:
            String(localized: "This connection can’t change this source. Ask whoever runs the server to allow it, or sign in again and approve it.")
        case .keyRefused:
            String(localized: "The server has ended MAPP’s sign-in. Sign in again in Settings.")
        case .refused(let reason):
            reason
        case .unsupported:
            String(localized: "This library doesn’t keep source names.")
        case .failed(let message):
            message
        }
    }
}

/// Where the names and marks of sources, and their counts, are kept: on the server, for every app.
nonisolated protocol SourceNameSource: Sendable {
    /// Every source the key can see.
    func sources() async throws(SourceEditFailure) -> [SourceInfo]
    /// How many active items each source wrote, in either tier. A source with none is absent.
    func counts() async throws(SourceEditFailure) -> [String: Int]
    /// Changes the name or mark of `code`; a field left nil stays as it is. Answers the source as it now reads.
    func update(_ code: String, name: SourceFieldChange?, mark: SourceFieldChange?) async throws(SourceEditFailure) -> SourceInfo
}

nonisolated extension SourceDirectory {
    /// The directory once the server has answered `info`.
    func updating(_ info: SourceInfo) -> SourceDirectory {
        var changed = self
        changed.infos[info.code] = info
        return changed
    }
}
