import Foundation
import Testing
@testable import MAPP

@MainActor
struct ItemMutationTests {
    private func ticket(_ title: String = "Fix") -> Note {
        Note(path: "Tickets/\(title).md", text: "\u{FEFF}---\r\ntype: aic.ticket.feature\r\ntitle: \(title)\r\nstatus: pending\r\ncustom: {value: 7}\r\nmarfa_id: protected\r\n---\r\nBody\r\n", created: .now)
    }

    @Test func propertyEditsPreserveEnvelopeAndUndo() {
        let note = ticket()
        let library = NoteLibrary(notes: [note])
        let undo = UndoManager()
        #expect(library.setItemProperty(note.id, key: "status", value: .string("completed"), undoManager: undo))
        #expect(library.note(note.id)?.file.text == note.file.text.replacing("status: pending", with: "status: completed"))
        undo.undo()
        #expect(library.note(note.id)?.file.text == note.file.text)
        #expect(!library.setItemProperty(note.id, key: "status", value: .string("made-up")))
        #expect(!library.setItemProperty(note.id, key: "marfa_id", value: .string("changed")))
    }

    @Test func malformedMetadataIsNotRewritten() {
        let note = Note(path: "Bad.md", text: "---\ntype: aic.ticket.task\nstatus: [broken\n---\nBody", created: .now)
        let library = NoteLibrary(notes: [note])
        #expect(!library.setItemProperty(note.id, key: "status", value: .string("pending")))
        #expect(library.note(note.id)?.file.text == note.file.text)
    }

    @Test func creationAndRelationshipChangesUseOwningFiles() {
        let project = Note(path: "Projects/Area.md", text: "---\ntype: aic.project\ntitle: Area\n---\nAn area.", created: .now)
        let library = NoteLibrary(notes: [project])
        let created = library.createItem(typeID: "aic.ticket.feature", title: "New Feature", parentID: project.id)
        #expect(created?.path == "Tickets/New Feature.md")
        #expect(created?.file.property("child-of") == "[[Area]]")
        #expect(library.createItem(typeID: "core.note", title: "new feature") == nil)
        guard let created else { return }
        #expect(library.setItemRelationship(project.id, field: "inverse:parent-of", targetIDs: []))
        #expect(library.note(created.id)?.file.property("child-of") == nil)
        #expect(library.setItemRelationship(created.id, field: "child-of", targetIDs: [project.id]))
        #expect(!library.setItemRelationship(project.id, field: "child-of", targetIDs: [created.id]))
    }

    @Test func renameUpdatesDeclaredConnectionsAndBodyReferences() {
        let target = ticket("Old")
        let source = Note(path: "Notes/Source.md", text: "---\ntype: core.note\nchild-of: \"[[Old]]\"\n---\nSee [[Old]].", created: .now)
        let library = NoteLibrary(notes: [target, source])
        let undo = UndoManager()
        library.renameNote(target.id, to: "New", undoManager: undo)
        #expect(library.note(source.id)?.file.property("child-of") == "[[New]]")
        #expect(library.note(source.id)?.body == "See [[New]].")
        undo.undo()
        #expect(library.note(source.id)?.file.text == source.file.text)
    }
    @Test func propertyUndoKeepsSubsequentBodyEdits() {
        let note = ticket()
        let library = NoteLibrary(notes: [note])
        let undo = UndoManager()
        #expect(library.setItemProperty(note.id, key: "status", value: .string("completed"), undoManager: undo))
        library.updateBody(of: note.id, to: "New body\n")
        undo.undo()
        #expect(library.note(note.id)?.body == "New body\n")
        #expect(library.note(note.id)?.file.property("status") == "pending")
    }

    @Test func addingAboutKeepsUnresolvedTargets() {
        let source = Note(path: "Log.md", text: "---\ntype: aic.agent.log\nabout: [\"[[Missing]]\"]\n---\nBody", created: .now)
        let target = ticket()
        let library = NoteLibrary(notes: [source, target])
        #expect(library.setItemRelationship(source.id, field: "about", targetIDs: [target.id]))
        #expect(library.note(source.id)?.file.text.contains("[[Missing]]") == true)
        #expect(library.connectionIndex.edges.contains { $0.name == "about" && $0.targetID == target.id })
    }

}
