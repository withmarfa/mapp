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
}

nonisolated struct AppItem: Identifiable, Sendable {
    let projection: NoteProjection
    let file: AppFile?
    init(projection: NoteProjection) { self.projection = projection; file = nil }
    init(file: AppFile) {
        self.file = file
        projection = NoteProjection(id: file.id, file: NoteFile(text: ""), fallbackTitle: file.title, filePath: file.path)
    }
    var id: UUID { projection.id }
    var title: String { projection.title }
    var type: ItemTypeDefinition? { if file != nil { return nil }; return WorkbenchSchema.definition(projection.declaredType ?? "core.note") }
    var fields: [String: NoteFieldValue] { projection.fields ?? [:] }
    var properties: [ItemPropertyDefinition] { type?.properties ?? [] }
    var relationshipFields: [String] { type?.relationshipFields ?? [] }
    var isEditable: Bool { if file != nil { return false }; if case .invalid = projection.frontMatter { false } else { true } }
    var validationMessage: String? { if case .invalid(let error) = projection.frontMatter { error.message } else { nil } }
}

nonisolated struct ItemRelationshipTarget: Identifiable, Sendable {
    let title: String
    let itemID: UUID?
    let resolution: NoteReferenceResolution
    var id: String { itemID?.uuidString ?? title }
}

nonisolated struct ItemRelationship: Identifiable, Sendable {
    let field: String
    let label: String
    let targets: [ItemRelationshipTarget]
    let isEditable: Bool
    let allowsMultiple: Bool
    var id: String { field }
}
