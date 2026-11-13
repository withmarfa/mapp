import Foundation

extension Browser {
    /// What decides the looks: the library, how often its items and types changed, and the person's choices.
    struct LooksKey: Equatable {
        let library: ObjectIdentifier
        let membership: Int
        let choices: [TypeID: TypeLookChoice]
    }

    /// The look of every type of the library, resolved once for the library's membership and the person's choices and
    /// held until either changes, so no view that needs them (the list, the cards, the table's columns) resolves them again for an edit.
    func looks(in library: any ItemLibrary) -> [TypeID: TypeLook] {
        let key = LooksKey(library: ObjectIdentifier(library), membership: library.membershipRevision, choices: lookChoices)
        if let held = looksMemo, held.key == key { return held.looks }
        let looks = library.catalogue.looks(choices: lookChoices)
        looksMemo = (key, looks)
        return looks
    }
}
