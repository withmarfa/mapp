import Foundation

/// The SF Symbol that stands for an item type wherever the app shows one: list rows, the sidebar, empty states.
nonisolated enum TypeSymbol {
    static let fallback = "doc"

    /// Marfa's built-in types have their own symbols. Any other type takes its nearest built-in ancestor's
    /// symbol, following the parents the catalogue names, so the app names no type a person or an app defined.
    static func name(for type: TypeID, in catalogue: Catalogue) -> String {
        var visited: Set<TypeID> = []
        var current: TypeID? = type
        while let id = current, visited.insert(id).inserted {
            if let symbol = builtIn[id] { return symbol }
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

    private static let builtIn: [TypeID: String] = [
        TypeID("core.note"): "doc.text",
        TypeID("core.task"): "checkmark.circle",
        TypeID("core.event"): "calendar",
        TypeID("core.bookmark"): "bookmark",
        TypeID("core.entity.person"): "person",
        TypeID("core.file"): "doc",
        TypeID("core.file.image"): "photo",
        TypeID("core.file.audio"): "waveform",
        TypeID("core.file.video"): "film",
    ]
}
