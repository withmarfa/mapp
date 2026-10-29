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
}
