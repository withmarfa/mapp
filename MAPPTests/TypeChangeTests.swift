import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// Types laid out as Marfa's built-in ones are: titles and text under different keys, a type titled by its first
/// line, one with no text, and required fields.
nonisolated enum TypeChangeFixture {
    static let note = TypeID("core.note"), task = TypeID("core.task"), event = TypeID("core.event")
    static let entity = TypeID("core.entity"), message = TypeID("core.message"), highlight = TypeID("core.highlight")

    static func field(_ key: String, _ kind: ItemTypeInfo.Field.Kind = .text, required: Bool = false, in type: TypeID) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(key: key, label: key.capitalized, kind: kind, declaredBy: type, required: required)
    }

    static let types: [ItemTypeInfo] = [
        ItemTypeInfo(
            id: note, label: "Note", fields: [field("title", in: note), field("body", in: note)],
            titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(
            id: task, label: "Task",
            fields: [
                field("title", required: true, in: task), field("body", in: task),
                field("status", .choice(["pending", "done"]), in: task), field("priority", .number, in: task),
            ],
            titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(
            id: event, label: "Event",
            fields: [
                field("title", required: true, in: event), field("description", in: event),
                field("starts_at", .date(includesTime: true), required: true, in: event),
            ],
            titleField: "title", bodyField: "description", parent: nil),
        ItemTypeInfo(
            id: entity, label: "Entity", fields: [field("name", required: true, in: entity)], titleField: "name",
            bodyField: nil, parent: nil),
        ItemTypeInfo(
            id: message, label: "Message", fields: [field("body", in: message), field("from", required: true, in: message)],
            titleField: nil, bodyField: "body", parent: nil),
        ItemTypeInfo(
            id: highlight, label: "Highlight",
            fields: [field("text", required: true, in: highlight), field("note", in: highlight), field("tags", .other, required: true, in: highlight)],
            titleField: "text", bodyField: "note", parent: nil),
        ItemTypeInfo(id: MarfaMapping.fileType, label: "File", fields: [], titleField: nil, bodyField: nil, parent: nil),
    ]

    static let catalogue = Catalogue(itemTypes: types)
    /// A change that removes the property.
    static let gone: PropertyValue? = nil

    static func info(_ type: TypeID) -> ItemTypeInfo { catalogue.itemTypes[type]! }

    static func plan(
        _ values: [String: PropertyValue], _ from: TypeID, _ to: TypeID, filling: [String: PropertyValue] = [:]
    ) -> Result<TypeChange, TypeChange.Obstacle> {
        TypeChange.plan(values, from: info(from), to: info(to), filling: filling)
    }
}

@Suite struct TypeChangeTests {
    typealias F = TypeChangeFixture

    @Test func theSameKeysChangeNothingButTheType() throws {
        let plan = try F.plan(["title": .string("Plan"), "body": .string("Text")], F.task, F.note).get()
        #expect(plan.changes.isEmpty)
        #expect(plan.missing.isEmpty)
        #expect(plan.unused.isEmpty)
    }

    @Test func fieldsTheNewTypeDoesNotUseStayAndAreNamed() throws {
        let values: [String: PropertyValue] = ["title": .string("Plan"), "body": .string("Text"), "status": .string("done"), "priority": .number(2)]
        let plan = try F.plan(values, F.task, F.note).get()
        #expect(plan.changes.isEmpty)
        #expect(plan.unused == ["priority", "status"])
    }

    @Test func theTextMovesToTheNewBodyKey() throws {
        let plan = try F.plan(
            ["title": .string("Launch"), "body": .string("Line one\n\n- [ ] two\n")], F.note, F.event,
            filling: ["starts_at": .string("2026-10-26T09:00:00Z")]
        ).get()
        #expect(plan.changes == [
            "body": F.gone, "description": .string("Line one\n\n- [ ] two\n"), "starts_at": .string("2026-10-26T09:00:00Z"),
        ])
        #expect(plan.missing.isEmpty)

        // And back again, the text whole.
        let back = try F.plan(
            ["title": .string("Launch"), "description": .string("Line one\n\n- [ ] two\n"), "starts_at": .string("2026-10-26T09:00:00Z")],
            F.event, F.note
        ).get()
        #expect(back.changes == ["description": F.gone, "body": .string("Line one\n\n- [ ] two\n")])
        #expect(back.unused == ["starts_at"])
    }

    @Test func theTitleMovesToTheNewTitleKey() throws {
        let plan = try F.plan(["name": .string("Ada")], F.entity, F.note).get()
        #expect(plan.changes == ["name": F.gone, "title": .string("Ada")])
        let highlight = try F.plan(["title": .string("Quote"), "body": .string("Why")], F.note, F.highlight, filling: ["tags": .array([])])
        #expect(highlight == .failure(.cannotFill(F.info(F.highlight).fields[2])))
    }

    @Test func aTitleNeverReplacesADifferentValueUnderTheNewTitleKey() throws {
        // The entity's `title`, left by another app, becomes the note's title, and its name stays where it was.
        let plan = try F.plan(["name": .string("Ada"), "title": .string("Research notes")], F.entity, F.note).get()
        #expect(plan.changes.isEmpty)
        #expect(plan.unused == ["name"])

        // The same title under both keys is held once.
        let same = try F.plan(["name": .string("Ada"), "title": .string("Ada")], F.entity, F.note).get()
        #expect(same.changes == ["name": F.gone])
        #expect(same.unused.isEmpty)
    }

    @Test func aTitleGoesIntoTheTextOfATypeTitledByItsFirstLine() throws {
        let plan = try F.plan(
            ["title": .string("Hello"), "body": .string("Body text")], F.note, F.message, filling: ["from": .string("Ada")]
        ).get()
        #expect(plan.changes == ["title": F.gone, "body": .string("Hello\n\nBody text"), "from": .string("Ada")])

        // Text that already starts with the title is not given it twice.
        let same = try F.plan(
            ["title": .string("Hello"), "body": .string("Hello\nmore")], F.note, F.message, filling: ["from": .string("Ada")]
        ).get()
        #expect(same.changes == ["title": F.gone, "from": .string("Ada")])

        // And the first line moves back out to the title, the rest kept byte for byte.
        let back = try F.plan(["body": .string("Hello\n\n  Body text\n"), "from": .string("Ada")], F.message, F.note).get()
        #expect(back.changes == ["title": .string("Hello"), "body": .string("  Body text\n")])
        #expect(back.unused == ["from"])
    }

    @Test func aRequiredFieldTheItemLacksIsAskedFor() throws {
        let plan = try F.plan(["title": .string("Launch")], F.note, F.event).get()
        #expect(plan.missing.map(\.key) == ["starts_at"])

        // A required title the item does not have is asked for too.
        let untitled = try F.plan(["title": .string(" "), "body": .string("")], F.note, F.task).get()
        #expect(untitled.missing.map(\.key) == ["title"])
        let filled = try F.plan(["title": .string(" ")], F.note, F.task, filling: ["title": .string("Named")]).get()
        #expect(filled.missing.isEmpty)
        #expect(filled.changes == ["title": .string("Named")])

        // A value that does not fit the field is no fill.
        let wrong = try F.plan(["title": .string("Launch")], F.note, F.event, filling: ["starts_at": .string("soon")]).get()
        #expect(wrong.missing.map(\.key) == ["starts_at"])
    }

    @Test func textATypeCannotKeepIsNeverDropped() {
        #expect(F.plan(["title": .string("Ada"), "body": .string("Notes about her")], F.note, F.entity) == .failure(.noPlaceForText))
        // An empty text goes, and the title moves.
        #expect(
            F.plan(["title": .string("Ada"), "body": .string("\n")], F.note, F.entity)
                == .success(TypeChange(changes: ["title": F.gone, "body": F.gone, "name": .string("Ada")], missing: [], unused: [])))
        // A message's first line is its title, so all of it must have somewhere to go.
        #expect(F.plan(["body": .string("Hi\n\nmore"), "from": .string("A")], F.message, F.entity) == .failure(.noPlaceForText))
    }

    @Test func textAlreadyUnderTheNewKeyIsKept() throws {
        // Left by an earlier change of type that did not move it, the event's `body` is text no page showed.
        let plan = try F.plan(
            ["title": .string("Launch"), "description": .string("Agenda"), "body": .string("Old notes"), "starts_at": .string("2026-10-26")],
            F.event, F.note
        ).get()
        #expect(plan.changes == ["description": F.gone, "body": .string("Agenda\n\nOld notes")])
    }

    @Test func aValueThatDoesNotFitTheNewFieldStopsTheChange() {
        let event = F.plan(["title": .string("Launch"), "starts_at": .string("soon")], F.note, F.event)
        #expect(event == .failure(.valueDoesNotFit(F.info(F.event).fields[2])))
        let task = F.plan(["title": .string("Plan"), "status": .string("someday")], F.note, F.task)
        #expect(task == .failure(.valueDoesNotFit(F.info(F.task).fields[2])))
    }

    @Test func firstLines() {
        #expect(NoteName.firstLine(of: "\n\n  Hello \nrest") == "Hello")
        #expect(NoteName.removingFirstLine(of: "\n\n  Hello \n\n\nrest\n") == "rest\n")
        #expect(NoteName.removingFirstLine(of: "Only") == "")
        #expect(NoteName.removingFirstLine(of: "\n\n") == "\n\n")
    }
}

@MainActor
@Suite struct TypeChangeOptionsTests {
    typealias F = TypeChangeFixture

    private func library() -> FakeItemLibrary {
        let library = FakeItemLibrary()
        library.catalogue = F.catalogue
        return library
    }

    @Test func offersTheTypesAnyItemCanBecome() throws {
        let library = library()
        let note = library.add("Ada\n\nNotes about her")
        let empty = library.add("")
        // Text goes nowhere in an entity, and a file is made only by adding one.
        #expect(Set(library.typeChangeOptions(for: [note.id]).map(\.id)) == [F.event, F.message, F.task])
        #expect(library.typeChangeOptions(for: [empty.id]).map(\.id).contains(F.entity))
        // An item that can't become a type is skipped, so the type is still offered for the rest.
        #expect(library.typeChangeOptions(for: [note.id, empty.id]).map(\.id).contains(F.entity))
        #expect(!library.typeChangeOptions(for: [note.id]).map(\.id).contains(MarfaMapping.fileType))
    }

    @Test func offersAChangeWhereAnyItemCanBecomeAnotherType() throws {
        let library = library()
        let note = library.add("Ada\n\nNotes about her")
        let empty = library.add("")
        let file = library.add("Scan")
        let index = try #require(library.items.firstIndex { $0.id == file.id })
        library.items[index].content = .file(.png, byteCount: 10)
        #expect(library.offersTypeChange(for: [note.id]))
        #expect(library.offersTypeChange(for: [file.id, note.id, empty.id]))
        #expect(!library.offersTypeChange(for: []))
        #expect(!library.offersTypeChange(for: [ItemID("gone")]))
        for ids: Set<ItemID> in [[note.id], [empty.id], [file.id], [file.id, note.id], [], [ItemID("gone")]] {
            #expect(library.offersTypeChange(for: ids) == !library.typeChangeOptions(for: ids).isEmpty)
        }
    }
}
