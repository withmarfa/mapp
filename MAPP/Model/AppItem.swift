import Foundation

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
    enum Content: Sendable { case markdown(NoteProjection), file(AppFile) }
    var content: Content { if let file { .file(file) } else { .markdown(projection) } }
    var typeID: String { file.map { $0.isImage ? "core.image" : $0.isPDF ? "core.pdf" : "core.file" } ?? projection.declaredType ?? "core.note" }
    var fields: [String: NoteFieldValue] { projection.fields ?? [:] }
    var properties: [ItemPropertyDefinition] { type?.properties ?? [] }
    var relationshipFields: [String] { type?.relationshipFields ?? [] }
    var isEditable: Bool { if file != nil { return false }; return if case .invalid = projection.frontMatter { false } else { true } }
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
