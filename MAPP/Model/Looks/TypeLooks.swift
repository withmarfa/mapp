import Foundation
import Observation

/// The looks a person has chosen, one set for each server, kept in the defaults. A server is named as a library is
/// (`Libraries.libraryKey`), so two servers that share a type identifier keep separate looks.
///
/// Only what was chosen is stored, place by place, and every look is worked out from the type's preset and its parent each
/// time it is read (`TypeLookResolver`), so improving a preset improves every look not chosen. Looks stay on this Mac:
/// they are never written to Marfa. Only Import chooses looks today, and a look it keeps for a type the server lacks waits
/// for the type.
///
/// Stored text that cannot be read, such as a look a later version wrote, is moved aside under a key of its own, kept and
/// never removed, and reported; what can be read is kept, and the looks of the rest are worked out as if never chosen.
@Observable @MainActor
final class TypeLooks {
    static let defaultsKey = "typeLooks"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "typeLooksSetAside"

    @ObservationIgnored private let defaults: UserDefaults
    private var chosen: [String: [String: TypeLookChoice]]

    init(defaults: UserDefaults = .standard, reporting: Reporting = .shared) {
        self.defaults = defaults
        guard let saved = defaults.data(forKey: Self.defaultsKey) else {
            chosen = [:]
            return
        }
        let (readable, unreadable) = Self.read(saved)
        chosen = readable
        guard let unreadable else { return }
        defaults.set((defaults.array(forKey: Self.setAsideKey) as? [Data] ?? []) + [unreadable], forKey: Self.setAsideKey)
        save()
        Telemetry.typeLooksUnreadable(reporting: reporting)
    }

    /// The choices that can be read, and the stored data of those that cannot: the whole of it where it is not an object
    /// of servers at all, otherwise an object of the unreadable looks alone.
    private static func read(_ saved: Data) -> (readable: [String: [String: TypeLookChoice]], unreadable: Data?) {
        if let all = try? JSONDecoder().decode([String: [String: TypeLookChoice]].self, from: saved) { return (all, nil) }
        guard let libraries = (try? JSONSerialization.jsonObject(with: saved)) as? [String: Any] else { return ([:], saved) }
        var readable: [String: [String: TypeLookChoice]] = [:]
        var unreadable: [String: Any] = [:]
        for (library, entry) in libraries {
            guard let types = entry as? [String: Any] else {
                unreadable[library] = entry
                continue
            }
            for (type, value) in types {
                if let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
                   let choice = try? JSONDecoder().decode(TypeLookChoice.self, from: data) {
                    readable[library, default: [:]][type] = choice
                } else {
                    var kept = unreadable[library] as? [String: Any] ?? [:]
                    kept[type] = value
                    unreadable[library] = kept
                }
            }
        }
        let kept = (try? JSONSerialization.data(withJSONObject: unreadable, options: .sortedKeys)) ?? saved
        return (readable, kept)
    }

    // MARK: Reading

    /// What was chosen for the types of `library`.
    func choices(for library: String) -> [TypeID: TypeLookChoice] {
        Dictionary(uniqueKeysWithValues: (chosen[library] ?? [:]).map { (TypeID($0.key), $0.value) })
    }

    /// The look of `type` on `library`.
    func look(of type: TypeID, in catalogue: Catalogue, library: String) -> TypeLook {
        catalogue.look(of: type, choices: choices(for: library))
    }

    /// The look of every type the catalogue holds, on `library`.
    func looks(in catalogue: Catalogue, library: String) -> [TypeID: TypeLook] {
        catalogue.looks(choices: choices(for: library))
    }

    // MARK: Export and import

    /// Every look of the catalogue's types on `library`, chosen or worked out, and the looks kept for types the server
    /// does not have, for Export.
    func file(in catalogue: Catalogue, library: String) -> LooksFile {
        let kept = choices(for: library).filter { catalogue.itemTypes[$0.key] == nil }
            .mapValues { TypeLook(date: $0.date ?? .off, secondary: $0.secondary ?? [], facts: $0.facts ?? []) }
        return LooksFile(looks: kept.merging(looks(in: catalogue, library: library)) { _, resolved in resolved })
    }

    /// Keeps every look in `file` as chosen on `library`, including those of types the server does not have yet, and
    /// leaves the other types' choices as they were.
    func importLooks(_ file: LooksFile, into library: String) {
        var types = chosen[library] ?? [:]
        for (type, choice) in file.choices { types[type.rawValue] = choice }
        chosen[library] = types
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(chosen) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
