import Foundation
import Observation

/// The looks a person has chosen, one set for each server, kept in the defaults. A server is named as a library is
/// (`Libraries.libraryKey`), so two servers that share a type identifier keep separate looks.
///
/// Only what was chosen is stored, place by place, and every look is worked out from the type's preset and its parent each
/// time it is read (`TypeLookResolver`), so improving a preset improves every look not chosen. The connected server's looks
/// sync through its Marfa (`PreferencesMap`). A look kept for a type the server lacks waits for the type.
///
/// Stored text that cannot be read, such as a look a later version wrote, is moved aside under a key of its own, kept and
/// never removed, and reported; what can be read is kept as stored, with members a later version added, and the looks of
/// the rest are worked out as if never chosen.
@Observable @MainActor
final class TypeLooks {
    static let defaultsKey = "typeLooks"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "typeLooksSetAside"

    @ObservationIgnored private let defaults: UserDefaults
    private var chosen: [String: [String: TypeLookChoice]]

    @ObservationIgnored private let reporting: Reporting

    init(defaults: UserDefaults = .standard, reporting: Reporting = .shared) {
        self.defaults = defaults
        self.reporting = reporting
        chosen = [:]
        reload()
    }

    /// Reads the stored value again, as when another Mac's change has reached the defaults (`PreferencesSync`).
    func reload() {
        guard let saved = defaults.data(forKey: Self.defaultsKey) else {
            chosen = [:]
            return
        }
        let (readable, unreadable) = Self.read(saved)
        chosen = readable
        guard let unreadable else { return }
        defaults.set((defaults.array(forKey: Self.setAsideKey) as? [Data] ?? []) + [unreadable], forKey: Self.setAsideKey)
        // Only what was set aside leaves the stored value, and the sync keeps it in the Marfa.
        if var libraries = Self.stored(saved) {
            for (library, entry) in Self.stored(unreadable) ?? [:] {
                guard let types = entry as? [String: Any], var held = libraries[library] as? [String: Any] else {
                    libraries[library] = nil
                    PreferenceHolds.record(Self.defaultsKey, library: library, keys: nil, in: defaults)
                    continue
                }
                for type in types.keys { held[type] = nil }
                libraries[library] = held.isEmpty ? nil : held
                PreferenceHolds.record(Self.defaultsKey, library: library, keys: Array(types.keys), in: defaults)
            }
            write(libraries)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
            PreferenceHolds.record(Self.defaultsKey, keys: nil, in: defaults)
        }
        Telemetry.typeLooksUnreadable(reporting: reporting)
    }

    /// The choices that can be read, and the stored data of those that cannot: the whole of it where it is not an object
    /// of servers at all, otherwise an object of the unreadable looks alone. A look that holds only members a later version
    /// added is no choice.
    private static func read(_ saved: Data) -> (readable: [String: [String: TypeLookChoice]], unreadable: Data?) {
        let (readable, unreadable) = readEvery(saved)
        return (readable.compactMapValues { types in
            let chosen = types.filter { !$0.value.isEmpty }
            return chosen.isEmpty ? nil : chosen
        }, unreadable)
    }

    private static func readEvery(_ saved: Data) -> (readable: [String: [String: TypeLookChoice]], unreadable: Data?) {
        if let all = try? JSONDecoder().decode([String: [String: TypeLookChoice]].self, from: saved) { return (all, nil) }
        guard let libraries = stored(saved) else { return ([:], saved) }
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

    // MARK: Choosing

    /// Whether the person has chosen any place of `type`'s look on `library`.
    func hasChoice(for type: TypeID, in library: String) -> Bool {
        chosen[library]?[type.rawValue] != nil
    }

    /// How many of `type`'s three places (date, line under the title, facts) the person chose.
    func changeCount(for type: TypeID, in library: String) -> Int {
        guard let choice = chosen[library]?[type.rawValue] else { return 0 }
        return [choice.date != nil, choice.secondary != nil, choice.facts != nil].filter { $0 }.count
    }

    /// Changes `type`'s look as `change` does, and keeps only the places that now differ from what this Mac works out
    /// without a choice (the preset, and what the types above chose), as Import does: a place changed back to what the type
    /// would show anyway is no choice, so a later better preset still reaches it. Only `type`'s own choice is written; the
    /// choices of its children are left as they were, and a child that took this place from it follows the change.
    func change(_ type: TypeID, in library: String, catalogue: Catalogue, _ change: (inout TypeLook) -> Void) {
        var resolver = TypeLookResolver(catalogue: catalogue, choices: choices(for: library))
        var look = resolver.look(of: type)
        let before = look
        change(&look)
        guard look != before else { return }
        let baseline = resolver.baseline(of: type)
        let choice = TypeLookChoice(
            date: look.date == baseline.date ? nil : look.date,
            secondary: look.secondary == baseline.secondary ? nil : look.secondary,
            facts: look.facts == baseline.facts ? nil : look.facts)
        var types = chosen[library] ?? [:]
        types[type.rawValue] = choice.isEmpty ? nil : choice
        chosen[library] = types.isEmpty ? nil : types
        save(library)
    }

    /// Takes back every choice for `type`, so it shows what its preset and the types above it give. Other types' choices
    /// stay.
    func restore(_ type: TypeID, in library: String) {
        guard var types = chosen[library], types.removeValue(forKey: type.rawValue) != nil else { return }
        chosen[library] = types.isEmpty ? nil : types
        save(library)
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
        let depths = Dictionary(uniqueKeysWithValues: known.map { ($0, Self.depth(of: $0, in: catalogue)) })
        known.sort { (depths[$0] ?? 0, $0.rawValue) < (depths[$1] ?? 0, $1.rawValue) }
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
        save(library)
    }

    /// How many types lie above `type` along the catalogue's `parent` links, however long the chain: `ancestors(of:)` stops
    /// at Marfa's limit of ten, where deeper types would tie. A parent the catalogue lacks counts as the last one, and a
    /// loop ends the walk.
    private static func depth(of type: TypeID, in catalogue: Catalogue) -> Int {
        var seen: Set<TypeID> = [type]
        var current = type
        while let parent = catalogue.itemTypes[current]?.parent, seen.insert(parent).inserted { current = parent }
        return seen.count - 1
    }

    /// Writes `library`'s choices over what is stored, so the other servers' looks and a later version's members of a
    /// look are kept as they were. A look with no choice left keeps those members.
    private func save(_ library: String) {
        var all = defaults.data(forKey: Self.defaultsKey).flatMap(Self.stored) ?? [:]
        var stored = all[library] as? [String: Any] ?? [:]
        let types = chosen[library] ?? [:]
        for (type, value) in stored where types[type] == nil && Self.choice(value) != nil {
            let others = (value as? [String: Any] ?? [:]).filter { !TypeLookChoice.members.contains($0.key) }
            stored[type] = others.isEmpty ? nil : others
        }
        for (type, choice) in types where Self.choice(stored[type]) != choice {
            var look = stored[type] as? [String: Any] ?? [:]
            let encoded = (try? JSONEncoder().encode(choice)).flatMap(Self.stored) ?? [:]
            for member in TypeLookChoice.members { look[member] = encoded[member] }
            stored[type] = look
        }
        all[library] = stored.isEmpty ? nil : stored
        write(all)
    }

    private func write(_ libraries: [String: Any]) {
        guard !libraries.isEmpty else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: libraries, options: .sortedKeys) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func stored(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func choice(_ value: Any?) -> TypeLookChoice? {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else { return nil }
        return try? JSONDecoder().decode(TypeLookChoice.self, from: data)
    }
}
