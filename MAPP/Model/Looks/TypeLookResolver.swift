import Foundation

/// Works out each type's look from what was chosen, the type's preset and its parents. Pure: it reads the catalogue and
/// the choices it is given, and keeps no state between calls beyond the presets it has already worked out. Resolve the
/// types together (`Catalogue.looks(choices:)`) so each preset is worked out once.
///
/// A type starts from the preset its own fields suggest. A place it was not given a choice for is taken from the nearest
/// type above it that chose one, along Marfa's `parent` chain (at most ten above, `Catalogue.ancestors`), but only
/// through types that suggest the same preset: a type whose fields suggest another preset starts afresh from its own,
/// so a place under an entity gets Place, not the entity's Person. A parent the catalogue lacks ends the walk.
nonisolated struct TypeLookResolver {
    let catalogue: Catalogue
    /// What was chosen, by type. Import changes it as it goes, so a child is measured against its parent's new choice.
    var choices: [TypeID: TypeLookChoice]
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

    /// The look of `type`. A date the type cannot show is replaced by the preset's; a part or fact naming a field the type
    /// lacks is left out.
    mutating func look(of type: TypeID) -> TypeLook {
        resolve(type, own: choices[type] ?? TypeLookChoice())
    }

    /// The look `type` has with no choice of its own: its preset, and what the types above it chose. Import keeps a
    /// place of a file only where it differs from this.
    mutating func baseline(of type: TypeID) -> TypeLook {
        resolve(type, own: TypeLookChoice())
    }

    private mutating func resolve(_ type: TypeID, own: TypeLookChoice) -> TypeLook {
        let suggested = preset(of: type)
        let base = suggested.look(for: type, in: catalogue)
        var chosen = own
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
    /// The look of every type the catalogue holds, in one pass: each type's preset is worked out once.
    func looks(choices: [TypeID: TypeLookChoice] = [:]) -> [TypeID: TypeLook] {
        var resolver = TypeLookResolver(catalogue: self, choices: choices)
        return Dictionary(uniqueKeysWithValues: itemTypes.keys.map { ($0, resolver.look(of: $0)) })
    }
}
