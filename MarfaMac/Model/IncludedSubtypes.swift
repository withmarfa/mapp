import Foundation

/// The types whose list also shows the items of their subtypes, by type identifier: the person's Include Subtypes
/// choice for each type, kept as one value in the defaults.
nonisolated struct IncludedSubtypes: Equatable, Sendable {
    static let key = "includedSubtypes"

    private(set) var types: Set<String> = []

    init(_ types: Set<String> = []) {
        self.types = types
    }

    mutating func set(_ type: String, included: Bool) {
        if included { types.insert(type) } else { types.remove(type) }
    }
}

/// The choice as `@AppStorage` keeps it: a JSON list of identifiers, sorted so the same choice is the same text.
nonisolated extension IncludedSubtypes: RawRepresentable {
    var rawValue: String {
        (try? JSONEncoder().encode(types.sorted())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    init?(rawValue: String) {
        guard let types = try? JSONDecoder().decode([String].self, from: Data(rawValue.utf8)) else { return nil }
        self.init(Set(types))
    }
}

nonisolated extension IncludedSubtypes {
    static func stored(in defaults: UserDefaults = .standard) -> IncludedSubtypes {
        defaults.string(forKey: key).flatMap(IncludedSubtypes.init(rawValue:)) ?? IncludedSubtypes()
    }

    static func update(in defaults: UserDefaults = .standard, _ change: (inout IncludedSubtypes) -> Void) {
        var value = stored(in: defaults)
        change(&value)
        defaults.set(value.rawValue, forKey: key)
    }
}

extension ItemLibrary {
    /// The types below `type` that hold items of their own, which a list of the type alone leaves out.
    func subtypesHoldingItems(of type: String) -> [TypeID] {
        catalogue.descendants(of: TypeID(type))
            .filter { count(in: .itemType($0.rawValue)) > 0 }
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// What opening a type lists with its subtypes' items too: the type's own place, which lists its own items only,
    /// and each subtype's place beside it.
    func items(inTypeAndSubtypes type: String) -> [Item] {
        let places = [TypeID(type)] + subtypesHoldingItems(of: type)
        return places.flatMap { items(in: .itemType($0.rawValue)) }
    }
}
