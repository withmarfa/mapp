import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

@MainActor
struct PropertyDraftTests {
    private static func draft(base: String, typed: String) -> ItemPropertyDraft {
        let draft = ItemPropertyDraft()
        draft.text = base
        draft.base = base
        draft.text = typed
        draft.isDirty = true
        return draft
    }

    // MARK: Committing

    @Test func aDraftNobodyTypedInWritesNothing() {
        let draft = ItemPropertyDraft()
        draft.text = "a"
        draft.base = "a"
        #expect(draft.commit(as: .text, current: "a") == .unchanged)
    }

    @Test func typedTextIsWritten() {
        #expect(Self.draft(base: "a", typed: "b").commit(as: .text, current: "a") == .write(.string("b")))
    }

    @Test func clearingAValueWritesNone() {
        #expect(Self.draft(base: "a", typed: "").commit(as: .text, current: "a") == .write(nil))
        #expect(Self.draft(base: "5", typed: "").commit(as: .number, current: "5") == .write(nil))
    }

    @Test func clearingAnEmptyValueChangesNothing() {
        #expect(Self.draft(base: "", typed: "").commit(as: .text, current: "") == .alreadyCurrent)
    }

    @Test func aNumberIsReadAsOneAndAnythingElseIsHeldBack() {
        #expect(Self.draft(base: "5", typed: "7.5").commit(as: .number, current: "5") == .write(.number(Decimal(string: "7.5")!)))
        #expect(Self.draft(base: "5", typed: "7 apples").commit(as: .number, current: "5") == .invalid)
    }

    // MARK: A change under an edit

    @Test func anEditOverAChangeMadeElsewhereIsHeldBackNotWritten() {
        let draft = Self.draft(base: "a", typed: "mine")
        #expect(draft.conflicts(with: "theirs"))
        #expect(draft.commit(as: .text, current: "theirs") == .conflict)
        #expect(draft.text == "mine" && draft.isDirty)
    }

    @Test func thePersonCanKeepTheirEditOverTheChange() {
        let draft = Self.draft(base: "a", typed: "mine")
        #expect(draft.commit(as: .text, current: "theirs", overwriting: true) == .write(.string("mine")))
    }

    @Test func theChangeCanBeTakenInstead() {
        let draft = Self.draft(base: "a", typed: "mine")
        draft.discard(toMatch: "theirs")
        #expect(draft.text == "theirs" && !draft.isDirty && !draft.conflicts(with: "theirs"))
    }

    @Test func aChangeThatMatchesTheEditIsNoConflict() {
        let draft = Self.draft(base: "a", typed: "same")
        #expect(!draft.conflicts(with: "same"))
        #expect(draft.commit(as: .text, current: "same") == .alreadyCurrent)
    }

    @Test func anUntouchedValueIsNoConflict() {
        #expect(!Self.draft(base: "a", typed: "b").conflicts(with: "a"))
    }

    @Test func typingAndDeletingBackToTheBaseIsNoConflict() {
        // The person typed, then deleted back to what they started from, while the item changed elsewhere: there
        // is no edit left to hold back, and the stale base is never written over the other change.
        let draft = Self.draft(base: "a", typed: "a")
        #expect(!draft.conflicts(with: "theirs"))
        #expect(draft.commit(as: .text, current: "theirs") == .alreadyCurrent)
    }

    // MARK: Leaving the screen

    @Test func aHeldBackEditThatLeavesIsHandedOffNotDropped() {
        let draft = Self.draft(base: "a", typed: "mine")
        #expect(draft.loss(as: .text, current: "theirs", isEditable: true) == .conflict)
    }

    @Test func anEditOnAnItemThatStoppedBeingEditableIsHandedOff() {
        let draft = Self.draft(base: "a", typed: "mine")
        #expect(draft.loss(as: .text, current: "a", isEditable: false) == .notEditable)
        #expect(draft.loss(as: .text, current: "theirs", isEditable: false) == .notEditable)
    }

    @Test func aNumberThatIsNotOneIsHandedOffWhenItLeaves() {
        #expect(Self.draft(base: "5", typed: "7 apples").loss(as: .number, current: "5", isEditable: true) == .notANumber)
    }

    @Test func nothingIsLostWhereTheEditCanBeWrittenOrIsAlreadyThere() {
        #expect(Self.draft(base: "a", typed: "mine").loss(as: .text, current: "a", isEditable: true) == nil)
        #expect(Self.draft(base: "a", typed: "same").loss(as: .text, current: "same", isEditable: false) == nil)
        #expect(ItemPropertyDraft().loss(as: .text, current: "a", isEditable: false) == nil)
    }

    // MARK: Handing off

    private static let field = ItemTypeInfo.Field(key: "assignee", label: "Assignee", kind: .text, declaredBy: TypeID("core.task"))

    private static func handOff(
        _ draft: ItemPropertyDraft, current: String, isEditable: Bool = true, accepting: Bool = true,
        writes: inout [PropertyValue?], notices: Notices
    ) {
        var written: [PropertyValue?] = []
        draft.handOff(
            label: "Assignee", as: .text, current: current, isEditable: isEditable,
            write: { written.append($0); return accepting }, to: notices)
        writes = written
    }

    @Test func aWriteTheLibraryRefusesAsTheRowLeavesIsHandedBack() throws {
        let notices = Notices()
        var writes: [PropertyValue?] = []
        let draft = Self.draft(base: "a", typed: "mine")
        Self.handOff(draft, current: "a", accepting: false, writes: &writes, notices: notices)
        #expect(writes == [.string("mine")], "it was tried first")
        let notice = try #require(notices.waiting.first)
        #expect(notice.title == "Property Not Saved")
        #expect(notice.text == "Assignee: mine")
        #expect(notice.message.contains("could not be saved"))
        #expect(!draft.isDirty && draft.text == "a", "the draft is dropped, so it is told once")
    }

    @Test func aWriteTheLibraryTakesTellsNothing() {
        let notices = Notices()
        var writes: [PropertyValue?] = []
        let draft = Self.draft(base: "a", typed: "mine")
        Self.handOff(draft, current: "a", writes: &writes, notices: notices)
        #expect(writes == [.string("mine")])
        #expect(notices.waiting.isEmpty && notices.told == 0)
        #expect(!draft.isDirty)
    }

    @Test func anEditOnAnItemThatCannotBeEditedIsHandedBackWithoutAWrite() throws {
        let notices = Notices()
        var writes: [PropertyValue?] = []
        Self.handOff(Self.draft(base: "a", typed: "mine"), current: "a", isEditable: false, writes: &writes, notices: notices)
        #expect(writes.isEmpty)
        #expect(try #require(notices.waiting.first).text == "Assignee: mine")
    }

    @Test func aHeldBackConflictIsHandedBackNotOverwritten() throws {
        let notices = Notices()
        var writes: [PropertyValue?] = []
        Self.handOff(Self.draft(base: "a", typed: "mine"), current: "theirs", writes: &writes, notices: notices)
        #expect(writes.isEmpty)
        #expect(try #require(notices.waiting.first).text == "Assignee: mine")
    }

    @Test func anUnchangedEditRaisesNoAlert() {
        let notices = Notices()
        var writes: [PropertyValue?] = []
        // Typed and deleted back to where it began, while the item has since changed.
        let back = Self.draft(base: "a", typed: "a")
        #expect(back.loss(as: .text, current: "theirs", isEditable: false) == nil)
        Self.handOff(back, current: "theirs", isEditable: false, writes: &writes, notices: notices)
        Self.handOff(Self.draft(base: "a", typed: "same"), current: "same", isEditable: false, writes: &writes, notices: notices)
        #expect(notices.waiting.isEmpty && notices.told == 0)
    }

    // MARK: The window's drafts

    @Test func aTitleTypedAndNotSavedIsAnUnsavedTitle() {
        let id = ItemID.mint()
        let presentation = DetailsPresentation()
        let draft = presentation.draft(for: id, key: "title")
        draft.text = "x"
        draft.isDirty = true
        #expect(presentation.unsavedTitles == [id])
    }
}
