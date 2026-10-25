import Foundation
import Marfa

/// The properties a create or an edit sends, built without the engine's state.
extension MarfaEngine {
    /// The library checks the same properties before submitting, so a create missing required values is refused before it is queued.
    nonisolated static func creationProperties(_ draft: ItemDraft, catalogue: Catalogue) throws(Refused) -> JSONObject {
        let info = catalogue.itemTypes[draft.type]
        var properties = JSONObject(draft.properties.sorted { $0.key < $1.key }.map { ($0.key, MarfaMapping.json($0.value)) })
        var body = draft.body
        if let titleField = MarfaMapping.titleField(of: info) {
            properties[titleField] = .string(draft.title)
        } else if !draft.title.isEmpty {
            body = body.isEmpty ? draft.title : draft.title + "\n\n" + body
        }
        if !body.isEmpty {
            guard let bodyField = MarfaMapping.bodyField(of: info) else {
                throw Refused(problem: SyncProblem(code: "unsupported", message: Self.noText))
            }
            properties[bodyField] = .string(body)
        }
        if let bodyField = MarfaMapping.bodyField(of: info), properties[bodyField] == nil,
           info?.fields.contains(where: { $0.key == bodyField && $0.required && $0.kind == .text }) == true {
            properties[bodyField] = .string("")
        }
        let missing = info?.fields.filter { field in
            guard field.required else { return false }
            guard let value = properties[field.key], value != .null else { return true }
            // A title or body supplied as text cannot satisfy a required field of another shape.
            if field.key == MarfaMapping.titleField(of: info) || field.key == MarfaMapping.bodyField(of: info) {
                return !field.kind.accepts(MarfaMapping.value(value))
            }
            return false
        } ?? []
        if !missing.isEmpty {
            let fields = missing.map(\.label).joined(separator: ", ")
            throw Refused(problem: SyncProblem(
                code: "invalid_properties",
                message: String(localized: "MAPP can’t fill these required fields: \(fields).")))
        }
        return properties
    }

    /// A property is given a value or taken away. A merge keeps a property it names no value for, and a null clears
    /// nothing, so taking one away replaces the item's properties with those it holds less that one.
    /// A replacement is built from the row's own properties, so a row whose stored properties could not be read,
    /// and so shows none, is never the base of one: it would clear everything the copy cannot show.
    nonisolated static func propertyEdit(
        _ changes: [String: PropertyValue?], of row: Marfa.Item?
    ) throws -> (properties: JSONObject, replacing: Bool) {
        func clears(_ value: PropertyValue?) -> Bool {
            guard let value else { return true }
            return value == .null
        }
        let given = changes.sorted { $0.key < $1.key }.compactMap { key, value -> (String, JSONValue)? in
            guard let value, !clears(value) else { return nil }
            return (key, MarfaMapping.json(value))
        }
        let cleared = changes.filter { clears($0.value) }.keys
        guard !cleared.isEmpty else { return (JSONObject(given), false) }
        guard let row else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."))
        }
        guard row.unreadableProperties == nil else { throw Refused(problem: MarfaProblems.unreadable) }
        var whole = row.properties
        for key in cleared { whole.removeValue(forKey: key) }
        for (key, value) in given { whole[key] = value }
        return (whole, true)
    }
}
