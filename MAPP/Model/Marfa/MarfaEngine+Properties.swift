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

    /// A property is given a value or taken away. The edit names what it gives and what it clears, so the server keeps
    /// every property the edit does not name, including those the copy could not read.
    nonisolated static func propertyEdit(_ changes: [String: PropertyValue?]) -> (properties: JSONObject, clearing: Set<String>) {
        var given: [(String, JSONValue)] = []
        var clearing = Set<String>()
        for (key, value) in changes.sorted(by: { $0.key < $1.key }) {
            if let value, value != .null { given.append((key, MarfaMapping.json(value))) } else { clearing.insert(key) }
        }
        return (JSONObject(given), clearing)
    }
}
