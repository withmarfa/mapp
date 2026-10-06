#if DEBUG
import SwiftUI

/// A catalogue shaped like Marfa's: a hierarchy with inherited fields, a type whose parent is missing, and edge
/// types of each kind of cardinality and cascade.
extension Catalogue {
    static let typesSample: Catalogue = {
        func field(
            _ key: String, _ kind: ItemTypeInfo.Field.Kind = .text, by owner: String, required: Bool = false,
            _ description: String? = nil
        ) -> ItemTypeInfo.Field {
            ItemTypeInfo.Field(
                key: key, label: MarfaMapping.label(forField: key), kind: kind, declaredBy: TypeID(owner),
                required: required, description: description)
        }
        let file = [
            field("blob_ref", by: "core.file", required: true, "Reference to the binary content"),
            field("mime_type", by: "core.file", required: true, "MIME type"),
            field("title", by: "core.file", "Filename or title")
        ]
        let entity = [field("name", by: "core.entity", required: true, "What it is called")]
        let task = [
            field("title", by: "aic.task", required: true),
            field("status", .choice(["pending", "in_progress", "completed"]), by: "aic.task"),
            field("due_at", .date, by: "aic.task")
        ]
        return Catalogue(
            itemTypes: [
                ItemTypeInfo(
                    id: TypeID("core.file"), label: "File", fields: file, titleField: "title", bodyField: nil, parent: nil,
                    description: "A file with its content held by reference.", version: 2, roles: ["attachment"]),
                ItemTypeInfo(
                    id: TypeID("core.file.image"), label: "Image",
                    fields: file + [field("width", .number, by: "core.file.image"), field("height", .number, by: "core.file.image")],
                    titleField: "title", bodyField: nil, parent: TypeID("core.file"), version: 1),
                ItemTypeInfo(
                    id: TypeID("core.file.pdf"), label: "PDF", fields: file, titleField: "title", bodyField: nil,
                    parent: TypeID("core.file"), version: 1),
                ItemTypeInfo(
                    id: TypeID("core.entity"), label: "Entity", fields: entity, titleField: "name", bodyField: nil, parent: nil,
                    version: 1),
                ItemTypeInfo(
                    id: TypeID("core.entity.person"), label: "Person",
                    fields: entity + [field("email", by: "core.entity.person")], titleField: "name", bodyField: nil,
                    parent: TypeID("core.entity"), version: 3, compatibleWith: [TypeID("core.contact")]),
                ItemTypeInfo(
                    id: TypeID("core.contact"), label: "Contact", fields: entity, titleField: "name", bodyField: nil, parent: nil,
                    version: 1),
                ItemTypeInfo(
                    id: TypeID("aic.task"), label: "Task", fields: task, titleField: "title", bodyField: "body", parent: nil,
                    description: "Work to be done.", version: 1, roles: ["actionable"]),
                ItemTypeInfo(
                    id: TypeID("aic.ticket.bug"), label: "Bug", fields: task, titleField: "title", bodyField: "body",
                    parent: TypeID("aic.ticket"), version: 1),
                ItemTypeInfo(id: TypeID("system.folder"), label: "Folder", fields: [], titleField: nil, bodyField: nil, parent: nil)
            ],
            edgeTypes: [
                EdgeTypeInfo(
                    id: "parent-of", label: "Parent of", reverseName: "child-of", cardinality: .one, writtenAt: .target,
                    sourceTypes: [], targetTypes: [], description: "The source holds the target as a child.",
                    reverseCardinality: .many, cascadeOnDelete: .cascade),
                EdgeTypeInfo(
                    id: "assigned-to", label: "Assigned to", reverseName: "assignee-of", cardinality: .many,
                    writtenAt: .source, sourceTypes: [TypeID("aic.task")], targetTypes: [TypeID("core.entity")],
                    description: "A task given to someone.", reverseCardinality: .many, cascadeOnDelete: .block,
                    properties: [field("since", .date, by: "assigned-to", "When it was given")]),
                EdgeTypeInfo(
                    id: "supersedes", label: "Supersedes", reverseName: nil, cardinality: .one, writtenAt: .source,
                    sourceTypes: [], targetTypes: [], reverseCardinality: .one),
                EdgeTypeInfo(
                    id: "in-folder", label: "In folder", reverseName: "contains", cardinality: .many, writtenAt: .source,
                    sourceTypes: [], targetTypes: [TypeID("system.folder")])
            ])
    }()
}

private struct TypesPreview: View {
    @State private var browser: TypesBrowser

    init(selection: TypeSelection?, search: String = "") {
        let browser = TypesBrowser(catalogue: .typesSample)
        browser.select(selection)
        browser.searchText = search
        _browser = State(initialValue: browser)
    }

    var body: some View {
        NavigationSplitView {
            Color.clear
        } content: {
            TypesListView(browser: browser)
                .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 480)
        } detail: {
            TypeDetailView(browser: browser)
        }
        .frame(width: 1_000, height: 640)
    }
}

#Preview("Item Type") { TypesPreview(selection: .item(TypeID("core.file.image"))) }
#Preview("Edge Type") { TypesPreview(selection: .edge("assigned-to")) }
#Preview("Search Keeps Parents") { TypesPreview(selection: nil, search: "pers") }
#Preview("Nothing Selected") { TypesPreview(selection: nil) }
#endif
