import Foundation
import Testing
@testable import MAPP

struct NoteProjectionTests {
    @Test func typedFieldsRetainUnknownDataAndSourceText() {
        let text = "\u{FEFF}---\r\ntype: custom.session\r\ntitle: \"A: session\"\r\nstarts_at: 2026-10-01T21:30:00+01:00\r\npinned: true\r\ncount: 9007199254740993\r\nratio: 1.25\r\nempty: null\r\nquoted: 'false'\r\nmetadata: {labels: [one, two], enabled: false}\r\nmarfa_id: 'opaque-id'\r\n---\r\n# Body\r\n"
        let file = NoteFile(text: text)
        let projection = NoteProjection(id: UUID(), file: file, fallbackTitle: "Filename")
        #expect(projection.declaredType == "custom.session")
        #expect(projection.title == "A: session")
        #expect(projection.body == "# Body\n")
        #expect(projection.fields?["starts_at"] == .string("2026-10-01T21:30:00+01:00"))
        #expect(projection.fields?["pinned"] == .bool(true))
        #expect(projection.fields?["count"] == .number(Decimal(string: "9007199254740993")!))
        #expect(projection.fields?["ratio"] == .number(Decimal(string: "1.25")!))
        #expect(projection.fields?["empty"] == .null)
        #expect(projection.fields?["quoted"] == .string("false"))
        #expect(projection.fields?["metadata"] == .object(["labels": .array([.string("one"), .string("two")]), "enabled": .bool(false)]))
        #expect(projection.fields?["marfa_id"] == .string("opaque-id"))
        #expect(projection.file == file)
        #expect(projection.file.text == text)
        #expect(projection.file.frontMatter == file.frontMatter)
    }

    @Test func headerOnlyRecordAndYAMLStringsAreReadWithoutRewriting() {
        let file = NoteFile(text: "---\ntype: custom.task\ntitle: >-\n  Multi-line\n  title\ndate: 2026-10-01\ncode: \"0012\"\nlist: &labels [red, green]\ncopy: *labels\n---")
        let projection = NoteProjection(id: UUID(), file: file, fallbackTitle: "Filename")
        #expect(projection.title == "Multi-line title")
        #expect(projection.body.isEmpty)
        #expect(projection.fields?["date"] == .string("2026-10-01"))
        #expect(projection.fields?["code"] == .string("0012"))
        #expect(projection.fields?["copy"] == .array([.string("red"), .string("green")]))
        #expect(projection.file.text == file.text)
    }

    @Test func noHeaderAndEmptyHeaderAreDifferent() {
        let plain = NoteProjection(id: UUID(), file: NoteFile(text: "Body"), fallbackTitle: "Filename")
        let empty = NoteProjection(id: UUID(), file: NoteFile(text: "---\n---"), fallbackTitle: "Filename")
        #expect(plain.frontMatter == .absent)
        #expect(empty.frontMatter == .parsed([:]))
        #expect(plain.title == "Filename")
        #expect(plain.declaredType == nil)
    }

    @Test(arguments: [
        "title: [broken",
        "- not a mapping",
        "title: one\ntitle: two",
        "nested: {1: value}",
        "number: .inf",
        "number: 1.0e-400",
        "custom: !unsupported value",
    ])
    func unusableYAMLIsExplicitAndDoesNotDiscardTheFile(header: String) {
        let file = NoteFile(text: "---\n\(header)\n---\nBody")
        let projection = NoteProjection(id: UUID(), file: file, fallbackTitle: "Filename")
        guard case .invalid(let error) = projection.frontMatter else {
            Issue.record("Expected a front matter error")
            return
        }
        #expect(!error.message.isEmpty)
        #expect(projection.fields == nil)
        #expect(projection.title == "Filename")
        #expect(projection.body == "Body")
        #expect(projection.file.text == file.text)
    }

    @Test func projectionCanReadAnExistingNoteWithoutChangingIt() {
        let note = Note(path: "Tasks/Record.md", text: "---\ntype: custom.task\ntitle: Record\n---", created: .now)
        let projection = NoteProjection(note: note)
        #expect(projection.id == note.id)
        #expect(projection.title == "Record")
        #expect(note.file.text == projection.file.text)
    }
}
