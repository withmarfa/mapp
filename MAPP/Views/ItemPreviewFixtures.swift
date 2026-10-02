#if DEBUG
import SwiftUI

/// Fixed values and an in-memory library keep canvas edits away from the person's files.
enum ItemPreviewFixtures {
    static let projectID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let ticketID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let noteID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    static let date = Date(timeIntervalSince1970: 1_791_000_000)

    static var library: NoteLibrary {
        NoteLibrary(notes: [
            Note(id: projectID, path: "Projects/Field Research.md", text: "---\ntype: aic.project\ntitle: Field Research\n---\n# Field Research\n\nA project with connected work.\n", created: date),
            Note(id: ticketID, path: "Tickets/Review the findings.md", text: "---\ntype: aic.ticket.task\ntitle: Review the findings\ndescription: Compare the field notes and photographs.\nstatus: in_progress\npriority: high\nchild-of: \"[[Field Research]]\"\n---\n# Findings\n\nRead [[Field notes]] before writing the review.\n", created: date),
            Note(id: noteID, path: "Notes/Field notes.md", text: "---\ntype: core.note\ntitle: Field notes\nchild-of: \"[[Field Research]]\"\n---\n# Field notes\n\nStart with what we observed.\n", created: date)
        ], now: { date })
    }

    static var unresolved: AppItem {
        AppItem(projection: NoteProjection(id: ticketID, file: NoteFile(text: "---\ntype: aic.ticket.task\ntitle: Review the findings\nstatus: unfamiliar_status\npriority: high\nchild-of: \"[[Missing project]]\"\ncustom_property: preserved\n---\nNotes\n"), fallbackTitle: "Review the findings"))
    }
}

#Preview("Ticket Details") {
    let library = ItemPreviewFixtures.library
    ItemInspectorHost(itemID: ItemPreviewFixtures.ticketID)
        .environment(library)
        .frame(width: 330, height: 750)
}

#Preview("Project and Related Work") {
    ItemInspectorHost(itemID: ItemPreviewFixtures.projectID)
        .environment(ItemPreviewFixtures.library)
        .frame(width: 330, height: 600)
}

#Preview("Missing and Unfamiliar Values") {
    ItemInspector(item: ItemPreviewFixtures.unresolved,
                  relationships: [.init(field: "child-of", label: "Parent", targets: [.init(title: "Missing project", itemID: nil, resolution: .missing)], isEditable: true, allowsMultiple: false)],
                  mentions: [], onProperty: { _, _ in true }, onOpen: { _ in }, onEdit: { _ in })
        .frame(width: 330, height: 650)
}

#Preview("Relationship Selection") {
    let library = ItemPreviewFixtures.library
    ItemRelationshipPicker(relationship: library.relationships(for: ItemPreviewFixtures.ticketID)[0],
                           candidates: library.relationshipCandidates(for: ItemPreviewFixtures.ticketID, field: "child-of"), onSave: { _ in true })
}

#Preview("New Item") {
    NewItemSheet(browser: Browser())
        .environment(ItemPreviewFixtures.library)
}

#Preview("Content and Details") {
    let library = ItemPreviewFixtures.library
    HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 20) {
            ItemSummary(item: library.item(ItemPreviewFixtures.ticketID)!, parent: "Field Research")
            Text("Findings").font(.title).padding(.horizontal, 24)
            Text("Read the field notes before writing the review.").padding(.horizontal, 24)
            Spacer()
        }
        Divider()
        ItemInspectorHost(itemID: ItemPreviewFixtures.ticketID).frame(width: 310)
    }
    .environment(library)
    .frame(width: 900, height: 650)
}

#Preview("Unsaved Property Input") {
    Form {
        ItemPropertyRow(definition: .init(key: "description", label: "Description", kind: .text),
                        value: .string("Edit this value and press Return to see the save error."),
                        isEditable: true, onChange: { _ in false })
    }
    .formStyle(.grouped)
    .frame(width: 330, height: 220)
}
#endif
