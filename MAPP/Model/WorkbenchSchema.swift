import Foundation

nonisolated struct ItemPropertyDefinition: Identifiable, Sendable {
    enum Kind: Sendable { case text, choice([String]), date, boolean, number }
    let key: String
    let label: String
    let kind: Kind
    var id: String { key }
}

nonisolated struct ItemTypeDefinition: Identifiable, Sendable {
    let id: String
    let label: String
    let folder: String
    let properties: [ItemPropertyDefinition]
    let relationshipFields: [String]
}

/// Interim workbench input, replaced by the store's public catalogue when the app moves to Marfa.
nonisolated enum WorkbenchSchema {
    static let statuses = ["someday", "pending", "in_progress", "blocked", "completed", "canceled"]
    static let taskProperties: [ItemPropertyDefinition] = [
        .init(key: "description", label: "Description", kind: .text),
        .init(key: "status", label: "Status", kind: .choice(statuses)),
        .init(key: "priority", label: "Priority", kind: .choice(["high", "medium", "low"])),
        .init(key: "assignee", label: "Assignee", kind: .text)
    ]
    static let types: [ItemTypeDefinition] = [
        .init(id: "core.note", label: "Note", folder: "Notes", properties: [], relationshipFields: ["child-of"]),
        .init(id: "aic.project", label: "Project", folder: "Projects", properties: [], relationshipFields: ["child-of"]),
        .init(id: "aic.epic", label: "Epic", folder: "Epics", properties: taskProperties, relationshipFields: ["child-of"]),
        .init(id: "aic.ticket.feature", label: "Feature", folder: "Tickets", properties: taskProperties, relationshipFields: ["child-of", "derived-from"]),
        .init(id: "aic.ticket.spike", label: "Question", folder: "Tickets", properties: taskProperties, relationshipFields: ["child-of", "derived-from"]),
        .init(id: "aic.ticket.task", label: "Task", folder: "Tickets", properties: taskProperties, relationshipFields: ["child-of", "derived-from"]),
        .init(id: "aic.decision", label: "Decision", folder: "Decisions", properties: [.init(key: "occurred_at", label: "Decided", kind: .date)], relationshipFields: ["child-of", "about", "supersedes", "derived-from"]),
        .init(id: "aic.agent.session", label: "Session", folder: "Agents/Sessions", properties: [.init(key: "description", label: "Description", kind: .text), .init(key: "starts_at", label: "Starts", kind: .date), .init(key: "ends_at", label: "Ends", kind: .date)], relationshipFields: ["child-of", "about"]),
        .init(id: "aic.agent.log", label: "Log", folder: "Agents/Logs", properties: [], relationshipFields: ["child-of", "about"])
    ]
    static func definition(_ id: String?) -> ItemTypeDefinition? { types.first { $0.id == id } }
    static func label(for field: String) -> String {
        switch field { case "child-of": "Parent"; case "about": "About"; case "derived-from": "Derived From"; case "supersedes": "Supersedes"; default: field }
    }
    static var rulesByType: [String: [NoteConnectionRule]] {
        Dictionary(uniqueKeysWithValues: types.map { type in
            (type.id, type.relationshipFields.map { field in
                .init(field: field, name: field == "child-of" ? "parent-of" : field, reverseName: field == "child-of" ? "child-of" : nil, direction: field == "child-of" ? .reverse : .forward)
            })
        })
    }

    /// Files are items too, typed as Marfa's core types name them; an image or a PDF is a kind of file.
    static let fileType = TypeID.file
    static let imageType = TypeID("core.image")
    static let pdfType = TypeID("core.pdf")

    /// The schema as the item layer reads it, which a Marfa library's catalogue takes the place of.
    static let catalogue: Catalogue = {
        let itemTypes = types.map { type in
            ItemTypeInfo(
                id: TypeID(type.id), label: type.label,
                fields: type.properties.map { property in
                    ItemTypeInfo.Field(key: property.key, label: property.label, kind: kind(property.kind), declaredBy: TypeID(type.id))
                },
                titleField: "title", bodyField: nil, parent: nil)
        } + [
            ItemTypeInfo(id: fileType, label: "File", fields: [], titleField: nil, bodyField: nil, parent: nil),
            ItemTypeInfo(id: imageType, label: "Image", fields: [], titleField: nil, bodyField: nil, parent: fileType),
            ItemTypeInfo(id: pdfType, label: "PDF", fields: [], titleField: nil, bodyField: nil, parent: fileType)
        ]
        var fields: [String] = []
        for field in types.flatMap(\.relationshipFields) where !fields.contains(field) { fields.append(field) }
        let edgeTypes = fields.map { field in
            let holders = Set(types.filter { $0.relationshipFields.contains(field) }.map { TypeID($0.id) })
            // A child names its parent, so `parent-of` is written at its target, under its reverse name.
            return field == "child-of"
                ? EdgeTypeInfo(
                    id: "parent-of", label: label(for: field), reverseName: field, cardinality: .one, writtenAt: .target,
                    sourceTypes: [], targetTypes: holders)
                : EdgeTypeInfo(
                    id: field, label: label(for: field), reverseName: nil, cardinality: field == "about" ? .many : .one,
                    writtenAt: .source, sourceTypes: holders, targetTypes: [])
        }
        return Catalogue(itemTypes: itemTypes, edgeTypes: edgeTypes)
    }()

    private static func kind(_ kind: ItemPropertyDefinition.Kind) -> ItemTypeInfo.Field.Kind {
        switch kind {
        case .text: .text
        case .choice(let choices): .choice(choices)
        case .date: .date
        case .boolean: .boolean
        case .number: .number
        }
    }
}
