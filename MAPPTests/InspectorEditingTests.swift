import Foundation
import Testing
@testable import MAPP

struct InspectorEditingTests {
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
        // is no edit left to hold back,
        // and the stale base is never written over their change.
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

    // MARK: Folding

    @Test func everySectionHasItsOwnStoredKeyAndIsResetWithTheRest() {
        let keys = InspectorSection.allCases.map(\.key)
        #expect(Set(keys).count == InspectorSection.allCases.count)
        for key in keys { #expect(InterfaceKey.all.contains(key)) }
    }

    @Test func aSectionIsOpenUntilFolded() throws {
        let name = "InspectorEditingTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for section in InspectorSection.allCases { #expect(InspectorSection.isOpen(section, in: defaults)) }
        defaults.set(false, forKey: InspectorSection.tags.key)
        #expect(!InspectorSection.isOpen(.tags, in: defaults))
        #expect(InspectorSection.isOpen(.properties, in: defaults))
    }

    // MARK: Values

    @Test func aDateIsNeverBrokenBetweenDayAndTime() {
        #expect(InspectorText.lineLimit(for: "29 Oct 2026 at 11:54 am", keepsOneLine: true) == 1)
        #expect(InspectorText.lineLimit(for: "a few words that wrap", keepsOneLine: false) == 3)
        #expect(InspectorText.lineLimit(for: "https://example.com/a/b", keepsOneLine: false) == 1)
    }

    @Test func theNameColumnFitsTheLongestNameWithinItsShare() {
        #expect(InspectorMetrics.nameColumn(longest: 60, fallback: 96, available: 300) == 60)
        #expect(InspectorMetrics.nameColumn(longest: 200, fallback: 96, available: 300) == 120)
        #expect(InspectorMetrics.nameColumn(longest: nil, fallback: 96, available: 300) == 96)
        #expect(InspectorMetrics.nameColumn(longest: nil, fallback: 96, available: 200) == 80)
    }
}
