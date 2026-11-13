import Foundation

/// Works out each type's look from what was chosen, the type's preset and its parents. Pure: it reads the catalogue and
/// the choices it is given, and keeps no state between calls beyond the presets it has already worked out.
///
/// A type starts from the preset its own fields suggest. A place it was not given a choice for is taken from the nearest
/// type above it that chose one, along Marfa's `parent` chain (at most ten above, `Catalogue.ancestors`), but only
/// through types that suggest the same preset: a type whose fields suggest another preset starts afresh from its own,
/// so a place under an entity gets Place, not the entity's Person. A parent the catalogue lacks ends the walk.
nonisolated struct TypeLookResolver {
    let catalogue: Catalogue
    let choices: [TypeID: TypeLookChoice]
    private var presets: [TypeID: LookPreset] = [:]

    init(catalogue: Catalogue, choices: [TypeID: TypeLookChoice] = [:]) {
        self.catalogue = catalogue
        self.choices = choices
    }

    /// The preset a type's fields suggest, kept for the next type that asks about the same parent.
    mutating func preset(of type: TypeID) -> LookPreset {
        if let known = presets[type] { return known }
        let preset = LookPreset.suggested(for: type, in: catalogue)
        presets[type] = preset
        return preset
    }

    /// The look of `type`. A choice naming a field the type does not have, or a date it cannot show, is passed over for
    /// the preset's.
    mutating func look(of type: TypeID) -> TypeLook {
        let suggested = preset(of: type)
        let base = suggested.look(for: type, in: catalogue)
        var chosen = choices[type] ?? TypeLookChoice()
        for ancestor in catalogue.ancestors(of: type) where !chosen.isComplete {
            guard catalogue.itemTypes[ancestor] != nil, preset(of: ancestor) == suggested else { break }
            guard let inherited = choices[ancestor] else { continue }
            chosen.fill(from: inherited)
        }
        let surface = LookSurface(type, in: catalogue)
        let wanted = TypeLook(
            date: chosen.date ?? base.date, secondary: chosen.secondary ?? base.secondary, facts: chosen.facts ?? base.facts)
        return surface.fitting(wanted, fallback: base.date)
    }
}

nonisolated extension TypeLookChoice {
    var isComplete: Bool { date != nil && secondary != nil && facts != nil }

    /// Takes each place this choice has not made from `other`.
    mutating func fill(from other: TypeLookChoice) {
        date = date ?? other.date
        secondary = secondary ?? other.secondary
        facts = facts ?? other.facts
    }
}

nonisolated extension Catalogue {
    /// The look of one type, given what was chosen for types (`TypeLooks`).
    func look(of type: TypeID, choices: [TypeID: TypeLookChoice] = [:]) -> TypeLook {
        var resolver = TypeLookResolver(catalogue: self, choices: choices)
        return resolver.look(of: type)
    }

    /// The look of every type the catalogue holds, in one pass: each type's preset is worked out once.
    func looks(choices: [TypeID: TypeLookChoice] = [:]) -> [TypeID: TypeLook] {
        var resolver = TypeLookResolver(catalogue: self, choices: choices)
        return Dictionary(uniqueKeysWithValues: itemTypes.keys.map { ($0, resolver.look(of: $0)) })
    }
}
