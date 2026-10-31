import Foundation
import Marfa
import Testing
@testable import MAPP

/// Editing a list of entries never drops or misplaces what the person typed: an entry keeps its identity while the
/// list changes, a member's text is written against the entry it began from, and what cannot be written goes back
/// through `Notices`.
@MainActor struct ListEditingTests {
    private static let emailsField = TypeField(
        name: "emails", type: "array", declaredBy: "core.entity",
        definition: ["items_type": "object", "items_fields": ["value": ["type": "email", "required": true], "label": ["type": "string"]]])
    private static let scoresField = TypeField(
        name: "scores", type: "array", declaredBy: "t",
        definition: ["items_type": "object", "items_fields": ["points": ["type": "integer", "minimum": 1, "maximum": 5, "required": true]]])

    private static func field(_ field: TypeField) throws -> ItemTypeInfo.Field {
        try #require(MarfaMapping.itemType(ItemType(id: "t", label: "T", fields: [field])).fields.first)
    }

    private static func shape(_ field: TypeField) throws -> ListShape {
        guard case .list(let shape) = try Self.field(field).kind else { throw CancellationError() }
        return shape
    }

    private static func email(_ value: String, _ label: String? = nil) -> PropertyValue {
        var fields: [String: PropertyValue] = ["value": .string(value)]
        if let label { fields["label"] = .string(label) }
        return .object(fields)
    }

    private static func member(_ shape: ListShape, _ key: String) throws -> ListShape.Member { try #require(shape.member(key)) }

    /// Stands in for the library: holds the list and records each write.
    final class Store {
        var value: PropertyValue?
        var writes: [PropertyValue?] = []
        var refuses = false
        init(_ value: PropertyValue?) { self.value = value }
        func write(_ new: PropertyValue?) -> Bool {
            guard !refuses else { return false }
            writes.append(new)
            value = new
            return true
        }
    }

    // MARK: The entry being added

    @Test func aNewEntryTheLibraryRefusesIsKeptWithItsText() throws {
        let shape = try Self.shape(Self.emailsField)
        let store = Store(nil)
        store.refuses = true
        let editing = ListEditing()
        editing.startEntry()
        let slot = ListEditing.Slot(entry: editing.pendingID, member: "value")
        editing.type("a@example.com", into: slot, in: store.value)
        editing.commit(try Self.member(shape, "value"), of: editing.pendingID, in: shape, value: store.value, write: store.write)

        #expect(editing.pending == ["value": .string("a@example.com")])
        #expect(editing.text(slot, in: store.value) == "a@example.com")
        #expect(editing.notice == "The list could not be saved.")
        #expect(editing.holdsUnsavedWork)

        // Once the library takes it, it is added and keeps its identity, so text still being typed stays with it.
        store.refuses = false
        let pendingID = editing.pendingID
        let label = ListEditing.Slot(entry: pendingID, member: "label")
        editing.type("work", into: label, in: store.value)
        editing.commit(try Self.member(shape, "label"), of: pendingID, in: shape, value: store.value, write: store.write)
        #expect(store.value == .array([Self.email("a@example.com", "work")]))
        #expect(editing.pending == nil)
        #expect(editing.rows(of: store.value).map(\.id) == [pendingID])
    }

    @Test func aNewEntryWithABadValueSaysWhyAndKeepsTheText() throws {
        let shape = try Self.shape(Self.scoresField)
        let editing = ListEditing()
        editing.startEntry()
        let slot = ListEditing.Slot(entry: editing.pendingID, member: "points")
        editing.type("9", into: slot, in: nil)
        let settled = editing.commit(try Self.member(shape, "points"), of: editing.pendingID, in: shape, value: nil) { _ in
            Issue.record("a refused value is never written")
            return true
        }
        #expect(!settled)
        #expect(editing.notice == NumberRule(integer: true, minimum: 1, maximum: 5).requirement)
        #expect(editing.text(slot, in: nil) == "9")
    }

    // MARK: Identity

    @Test func textStaysWithItsEntryWhenAnotherIsRemovedElsewhere() throws {
        let shape = try Self.shape(Self.emailsField)
        let a = Self.email("a@example.com"), b = Self.email("b@example.com")
        let store = Store(.array([a, b]))
        let editing = ListEditing()
        let ids = editing.rows(of: store.value).map(\.id)
        let slot = ListEditing.Slot(entry: ids[1], member: "label")
        editing.type("home", into: slot, in: store.value)

        store.value = .array([b])
        #expect(editing.rows(of: store.value).map(\.id) == [ids[1]])
        #expect(editing.commit(try Self.member(shape, "label"), of: ids[1], in: shape, value: store.value, write: store.write))
        #expect(store.value == .array([Self.email("b@example.com", "home")]))
    }

    @Test func textInAnEntryRemovedElsewhereGoesBackToThePerson() throws {
        let a = Self.email("a@example.com"), b = Self.email("b@example.com")
        let editing = ListEditing()
        let ids = editing.rows(of: .array([a, b])).map(\.id)
        editing.type("home", into: ListEditing.Slot(entry: ids[1], member: "label"), in: .array([a, b]))

        #expect(editing.rows(of: .array([a])).map(\.id) == [ids[0]])
        #expect(editing.holdsUnsavedWork)
        let notices = Notices()
        editing.handBackOrphans(label: "Emails", to: notices)
        let notice = try #require(notices.waiting.first)
        #expect(notice.text == "Emails: Label: home")
        #expect(!editing.holdsUnsavedWork)
    }

    @Test func theEditorsOwnMovesAndRemovalsKeepEachEntrysText() throws {
        let shape = try Self.shape(Self.emailsField)
        let a = Self.email("a@example.com"), b = Self.email("b@example.com"), c = Self.email("c@example.com")
        let store = Store(.array([a, b, c]))
        let editing = ListEditing()
        let ids = editing.rows(of: store.value).map(\.id)
        let slot = ListEditing.Slot(entry: ids[2], member: "label")
        editing.type("home", into: slot, in: store.value)

        editing.move(ids[2], to: 0, in: shape, value: store.value, write: store.write)
        #expect(editing.rows(of: store.value).map(\.id) == [ids[2], ids[0], ids[1]])
        editing.remove(ids[0], in: shape, value: store.value, write: store.write)
        #expect(editing.rows(of: store.value).map(\.id) == [ids[2], ids[1]])
        #expect(editing.text(slot, in: store.value) == "home")
        editing.commit(try Self.member(shape, "label"), of: ids[2], in: shape, value: store.value, write: store.write)
        #expect(store.value == .array([Self.email("c@example.com", "home"), b]))
    }

    // MARK: Changes made elsewhere

    @Test func aMemberChangedElsewhereWhileTypingIsNotWrittenOver() throws {
        let shape = try Self.shape(Self.emailsField)
        let store = Store(.array([Self.email("a@example.com", "work")]))
        let editing = ListEditing()
        let id = try #require(editing.rows(of: store.value).first?.id)
        let slot = ListEditing.Slot(entry: id, member: "label")
        editing.type("home", into: slot, in: store.value)

        store.value = .array([Self.email("a@example.com", "office")])
        #expect(editing.rows(of: store.value).map(\.id) == [id])
        #expect(editing.conflicts(slot, in: store.value))
        let label = try Self.member(shape, "label")
        #expect(!editing.commit(label, of: id, in: shape, value: store.value, write: store.write))
        #expect(store.writes.isEmpty)
        #expect(editing.text(slot, in: store.value) == "home")

        // Keep My Edit writes it over the change; Use Current Value would have dropped it.
        #expect(editing.commit(label, of: id, in: shape, value: store.value, overwriting: true, write: store.write))
        #expect(store.value == .array([Self.email("a@example.com", "home")]))
    }

    @Test func anotherMemberOfTheEntryChangedElsewhereAlsoHoldsTheTextBack() throws {
        let shape = try Self.shape(Self.emailsField)
        let store = Store(.array([Self.email("a@example.com", "work")]))
        let editing = ListEditing()
        let id = try #require(editing.rows(of: store.value).first?.id)
        let slot = ListEditing.Slot(entry: id, member: "value")
        editing.type("b@example.com", into: slot, in: store.value)

        store.value = .array([Self.email("c@example.com", "work")])
        #expect(editing.conflicts(slot, in: store.value))
        #expect(!editing.commit(try Self.member(shape, "value"), of: id, in: shape, value: store.value, write: store.write))
        #expect(store.writes.isEmpty)
    }

    // MARK: Lists Marfa refuses

    @Test func aMemberTheListDoesNotDeclareCanBeRemovedButNothingElseIsWrittenBesideIt() throws {
        let shape = try Self.shape(Self.emailsField)
        let odd: PropertyValue = .object(["value": .string("a@example.com"), "kind": .string("x")])
        let store = Store(.array([odd, Self.email("b@example.com")]))
        let editing = ListEditing()
        let ids = editing.rows(of: store.value).map(\.id)

        let slot = ListEditing.Slot(entry: ids[1], member: "label")
        editing.type("home", into: slot, in: store.value)
        #expect(!editing.commit(try Self.member(shape, "label"), of: ids[1], in: shape, value: store.value, write: store.write))
        #expect(store.writes.isEmpty)
        #expect(editing.notice != nil)
        #expect(editing.text(slot, in: store.value) == "home")

        #expect(editing.set("kind", to: nil, of: ids[0], in: shape, value: store.value, write: store.write))
        #expect(store.value == .array([Self.email("a@example.com"), Self.email("b@example.com")]))
        #expect(editing.commit(try Self.member(shape, "label"), of: ids[1], in: shape, value: store.value, write: store.write))
        #expect(store.value == .array([Self.email("a@example.com"), Self.email("b@example.com", "home")]))
    }

    @Test func anEntryThatIsNotAnObjectCanBeRemoved() throws {
        let shape = try Self.shape(Self.emailsField)
        let store = Store(.array([.string("a@example.com"), Self.email("b@example.com")]))
        let editing = ListEditing()
        let ids = editing.rows(of: store.value).map(\.id)
        editing.remove(ids[0], in: shape, value: store.value, write: store.write)
        #expect(store.value == .array([Self.email("b@example.com")]))
    }

    // MARK: Leaving

    @Test func leavingWritesWhatItCanAndGivesBackTheRest() throws {
        let shape = try Self.shape(Self.emailsField)
        let store = Store(.array([Self.email("a@example.com")]))
        let editing = ListEditing()
        let id = try #require(editing.rows(of: store.value).first?.id)
        editing.type("work", into: ListEditing.Slot(entry: id, member: "label"), in: store.value)
        editing.startEntry()
        editing.type("home", into: ListEditing.Slot(entry: editing.pendingID, member: "label"), in: store.value)

        let notices = Notices()
        editing.leave(shape, label: "Emails", value: store.value, isEditable: true, write: store.write, to: notices)
        #expect(store.value == .array([Self.email("a@example.com", "work")]))
        let notice = try #require(notices.waiting.first)
        #expect(notice.text == "Emails: New entry: Label: home")
        #expect(notice.message.hasPrefix("The new entry wasn’t finished"))
        #expect(!editing.holdsUnsavedWork)
    }

    @Test func leavingAnItemThatCanNoLongerBeEditedGivesBackEverything() throws {
        let shape = try Self.shape(Self.emailsField)
        let store = Store(.array([Self.email("a@example.com")]))
        let editing = ListEditing()
        let id = try #require(editing.rows(of: store.value).first?.id)
        editing.type("work", into: ListEditing.Slot(entry: id, member: "label"), in: store.value)
        let notices = Notices()
        editing.leave(shape, label: "Emails", value: store.value, isEditable: false, write: store.write, to: notices)
        #expect(store.writes.isEmpty)
        #expect(notices.waiting.first?.text == "Emails: Label: work")
    }

    @Test func theInspectorGivesBackAListLeftUnfinishedWhenTheSelectionMoves() throws {
        let field = try Self.field(Self.emailsField)
        guard case .list = field.kind else { return }
        let presentation = DetailsPresentation()
        let item = ItemID("10000000-0000-0000-0000-000000000001")
        let draft = presentation.draft(for: item, key: "emails")
        draft.field = field
        draft.list.startEntry()
        draft.list.type("work", into: ListEditing.Slot(entry: draft.list.pendingID, member: "label"), in: nil)
        #expect(presentation.unsavedProperties(of: item).map(\.key) == ["emails"])
    }

    // MARK: Quick add

    @Test func quickAddKeepsAnUnfinishedEntryAndGivesItBackWhenItCloses() throws {
        let field = try Self.field(Self.emailsField)
        let quickAdd = QuickAdd()
        quickAdd.draft = QuickAdd.Draft(typeID: "core.entity.person")
        let list = quickAdd.listDraft(for: "emails")
        list.field = field
        list.list.startEntry()
        list.list.type("work", into: ListEditing.Slot(entry: list.list.pendingID, member: "label"), in: nil)

        // The popover closing does not drop it: the window's quick add holds it, and it holds the draft back.
        #expect(quickAdd.listDraft(for: "emails") === list)
        #expect(quickAdd.unfinishedLists.map(\.key) == ["emails"])
        #expect(quickAdd.holdsContent)

        let notices = Notices()
        quickAdd.handOff(to: notices, because: .closed, in: nil)
        #expect(notices.waiting.first?.text == "Emails: New entry: Label: work")
        #expect(quickAdd.listDrafts.isEmpty)
    }
}
