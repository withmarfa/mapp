import Foundation

/// What a field's name on the item page offers, decided once and drawn by the page's menu. Pure, with no SwiftUI.
///
/// The Mac's own placement (pin, move, hide) is offered for every row of the page. What changes the type for every
/// item (rename, edit choices, remove) is offered only for a field the type declares itself, on a type that is not
/// Marfa's own, and only while the server can be reached. A field that is not the person's to change shows what stops
/// them instead, and none of those entries.
nonisolated struct FieldMenu: Equatable, Sendable {
    enum Command: Hashable, Sendable {
        /// The value's own editor, for a value whose click follows a link instead.
        case editValue
        case rename, editChoices, remove
        case pin, unpin, moveUp, moveDown, hide
    }

    struct Entry: Equatable, Sendable {
        let command: Command
        let isEnabled: Bool
    }

    /// Why the field cannot be changed, in words, where it cannot.
    let lockText: String?
    /// The entries in groups, each group set apart from the next.
    let sections: [[Entry]]

    init(row: String, type: ItemTypeInfo?, layout: PageLayout?, catalogue: Catalogue, editsValue: Bool, reachesServer: Bool) {
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
                    lockText = String(localized: "Part of a type Marfa provides")
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

        var placing: [Entry] = []
        if let layout, let group = layout.group(of: row) {
            if group == .pinned {
                placing.append(Entry(command: .unpin, isEnabled: true))
            } else {
                placing.append(Entry(command: .pin, isEnabled: layout.moving(row, to: .pinned) != nil))
            }
            placing.append(Entry(command: .moveUp, isEnabled: layout.moved(row, by: -1) != nil))
            placing.append(Entry(command: .moveDown, isEnabled: layout.moved(row, by: 1) != nil))
            placing.append(Entry(command: .hide, isEnabled: group != .hidden))
        }
        sections = [
            editsValue ? [Entry(command: .editValue, isEnabled: true)] : [],
            own, placing, remove,
        ].filter { !$0.isEmpty }
    }
}

nonisolated extension PageLayout {
    /// The layout once a placement command is carried out on `row`, or nil where it changes nothing: a row already
    /// at the end it moves toward, a fifth pin, or a command that is not placement.
    func after(_ command: FieldMenu.Command, row: String) -> PageLayout? {
        switch command {
        case .pin: moving(row, to: .pinned)
        case .unpin: moving(row, to: .page)
        case .moveUp: moved(row, by: -1)
        case .moveDown: moved(row, by: 1)
        case .hide: moving(row, to: .hidden)
        case .editValue, .rename, .editChoices, .remove: nil
        }
    }
}
