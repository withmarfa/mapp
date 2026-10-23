import Foundation

/// The SF Symbol that stands for an item's type wherever the app lists types or items, chosen by the type's own
/// name so every library draws a note the same way.
nonisolated enum TypeSymbol {
    static let fallback = "doc.text"

    static func name(for type: TypeID) -> String {
        let name = type.rawValue.split(separator: ".").last.map(String.init) ?? type.rawValue
        return table[name] ?? fallback
    }

    private static let table = [
        "note": "doc.text", "task": "checkmark.circle", "event": "calendar", "decision": "signpost.right",
        "log": "list.bullet.rectangle", "session": "clock", "epic": "flag", "ticket": "ticket", "feature": "sparkles",
        "spike": "bolt", "bookmark": "bookmark", "person": "person", "file": "doc", "image": "photo", "project": "folder",
    ]
}
