import Foundation

/// What a row's menu on the item page offers, decided once and drawn by the page's menu. Pure, with no SwiftUI.
///
/// First how the row shows on the type's pages (`RowShows`), with Pin Under the Title only while pinned properties are
/// on; then Move Up and Move Down; then the field's own menu. What changes the type for every item (rename, edit
/// choices, remove) is offered only for a field the type declares and no type above it does, on a type that is not
/// Marfa's own, and only while the server can be reached. A field that is not the person's to change shows what stops
/// them instead, and none of those entries.
nonisolated struct FieldMenu: Equatable, Sendable {
    enum Command: Hashable, Sendable {
        case showWhenSet, alwaysShow, hide
        case pin, unpin
        case moveUp, moveDown
        /// The value's own editor, for a value whose click follows a link instead.
        case editValue
        case rename, editChoices, remove
    }

    struct Entry: Equatable, Sendable {
        let command: Command
        let isEnabled: Bool
        var isChecked = false
    }

    /// Where the row is on the type's pages, for the entries that place it.
    struct Placing: Equatable, Sendable {
        var shows: RowShows
        var canMoveUp: Bool
        var canMoveDown: Bool
        /// Nil while pinned properties are off, else whether the row is pinned.
        var isPinned: Bool?
        /// Whether one more row can be pinned.
        var canPin = true
    }

    /// Why the field cannot be changed, in words, where it cannot.
    let lockText: String?
    /// The entries in groups, each group set apart from the next.
    let sections: [[Entry]]

    /// `placing` is nil for a row that is no person's to place, such as an event's When.
    init(row: String, type: ItemTypeInfo?, placing: Placing?, catalogue: Catalogue, editsValue: Bool, reachesServer: Bool) {
        let field = type?.fields.first { $0.key == row }

        var lockText: String?
        var own: [Entry] = []
        var remove: [Entry] = []
        if let type, let field {
            if let lock = type.lock(of: field, in: catalogue) {
                switch lock {
                case .inherited(let source):
                    let label = catalogue.itemTypes[source]?.label ?? source.rawValue
                    lockText = String(localized: "Inherited from \(label)")
                case .shipped:
                    lockText = String(localized: "Part of a type Marfa or a plugin provides")
                }
            } else {
                // A clash of names is for the sheet to say when it is submitted, not a reason to hide the way to fix one.
                func offered(_ edit: FieldEdit) -> Bool { reachesServer && (try? type.plan(edit, in: catalogue)) != nil }
                own.append(Entry(command: .rename, isEnabled: reachesServer))
                if case .choice(let choices) = field.kind {
                    own.append(Entry(command: .editChoices, isEnabled: offered(.setChoices(key: field.key, choices: choices))))
                }
                remove.append(Entry(command: .remove, isEnabled: offered(.remove(key: field.key))))
            }
        }
        self.lockText = lockText

        var showing: [Entry] = []
        var moving: [Entry] = []
        if let placing {
            showing = [
                Entry(command: .showWhenSet, isEnabled: true, isChecked: placing.shows == .whenSet),
                Entry(command: .alwaysShow, isEnabled: true, isChecked: placing.shows == .always),
                Entry(command: .hide, isEnabled: true, isChecked: placing.shows == .hidden),
            ]
            if let pinned = placing.isPinned {
                showing.append(pinned ? Entry(command: .unpin, isEnabled: true) : Entry(command: .pin, isEnabled: placing.canPin))
            }
            moving = [Entry(command: .moveUp, isEnabled: placing.canMoveUp), Entry(command: .moveDown, isEnabled: placing.canMoveDown)]
        }
        sections = [showing, moving, editsValue ? [Entry(command: .editValue, isEnabled: true)] : [], own, remove].filter { !$0.isEmpty }
    }
}
