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

    /// The look of every type the catalogue holds, on `library`, each type's preset worked out once. This is the one way to
    /// resolve looks: a caller holds the result for the catalogue's revision and these choices, and never resolves in a
    /// row's body. A type the catalogue lacks has no entry.
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

    /// Keeps, for each type in `file` and each of its places, only a value that differs from what this Mac works out for
    /// the place without a choice (the preset, and what the types above chose), and clears the place's choice where it does
    /// not. So importing an export of this Mac changes nothing, and a later better preset still reaches every place nobody
    /// chose. A type is measured against its parents' choices as this import leaves them, so the parents go first.
    ///
    /// A type the catalogue lacks has nothing to measure against, so the file's whole look is kept for the type to take
    /// when it appears. The choices of types the file does not hold are left as they were.
    func importLooks(_ file: LooksFile, into library: String, in catalogue: Catalogue) {
        var resolver = TypeLookResolver(catalogue: catalogue, choices: choices(for: library))
        var types = chosen[library] ?? [:]
        var known: [TypeID] = []
        for (word, look) in file.looks {
            let type = TypeID(word)
            if catalogue.itemTypes[type] == nil {
                types[word] = TypeLookChoice(look)
            } else {
                known.append(type)
            }
        }
        known.sort { (catalogue.ancestors(of: $0).count, $0.rawValue) < (catalogue.ancestors(of: $1).count, $1.rawValue) }
        for type in known {
            guard let look = file.looks[type.rawValue] else { continue }
            let baseline = resolver.baseline(of: type)
            let choice = TypeLookChoice(
                date: look.date == baseline.date ? nil : look.date,
                secondary: look.secondary == baseline.secondary ? nil : look.secondary,
                facts: look.facts == baseline.facts ? nil : look.facts)
            resolver.choices[type] = choice.isEmpty ? nil : choice
            types[type.rawValue] = choice.isEmpty ? nil : choice
        }
        let kept: [String: TypeLookChoice]? = types.isEmpty ? nil : types
        guard kept != chosen[library] else { return }
        chosen[library] = kept
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(chosen) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
