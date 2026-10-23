import Foundation

/// The SF Symbol that stands for an item type wherever the app shows one: list rows, the sidebar, empty states.
nonisolated enum TypeSymbol {
    static let fallback = "doc"

    /// A type is known by the last segment of its identifier (`aic.ticket.task` is a `task`). One the table does
    /// not know takes its nearest ancestor's symbol, where the catalogue names a parent.
    static func name(for type: TypeID, in catalogue: Catalogue = Catalogue()) -> String {
        var visited: Set<TypeID> = []
        var current: TypeID? = type
        while let id = current, visited.insert(id).inserted {
            if let symbol = bySegment[segment(of: id)] { return symbol }
            current = catalogue.itemTypes[id]?.parent
        }
        return fallback
    }

    /// The type's name as people read it: the catalogue's label, else its last segment capitalized.
    static func label(for type: TypeID, in catalogue: Catalogue) -> String {
        if let label = catalogue.itemTypes[type]?.label, !label.isEmpty { return label }
        return segment(of: type).capitalized
    }

    private static func segment(of type: TypeID) -> String {
        type.rawValue.split(whereSeparator: { $0 == "." || $0 == "/" }).last.map(String.init)?.lowercased() ?? ""
    }

    private static let bySegment = [
        "note": "doc.text",
        "task": "checkmark.circle",
        "event": "calendar",
        "decision": "signpost.right",
        "log": "list.bullet.rectangle",
        "session": "clock",
        "epic": "flag",
        "ticket": "ticket",
        "feature": "sparkles",
        "spike": "bolt",
        "bookmark": "bookmark",
        "person": "person",
        "file": "doc",
        "image": "photo",
        "project": "folder",
    ]
}
