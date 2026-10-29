import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MAPP

@MainActor
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

    // MARK: Folding

    @Test func everySectionHasItsOwnStoredKeyAndIsResetWithTheRest() {
        let keys = InspectorSection.allCases.map(\.key)
        #expect(Set(keys).count == InspectorSection.allCases.count)
        for key in keys { #expect(InterfaceKey.all.contains(key)) }
    }

    /// The height a section takes in a hosting view, whose stored fold state is `defaults`.
    private static func height(of section: InspectorSection, in defaults: UserDefaults) -> CGFloat {
        let view = InspectorSectionView(section, title: "Section") { Color.clear.frame(width: 100, height: 200) }
            .defaultAppStorage(defaults)
        return NSHostingView(rootView: view).fittingSize.height
    }

    @Test func aSectionIsOpenUntilFolded() throws {
        let name = "InspectorEditingTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let open = Self.height(of: .tags, in: defaults)
        #expect(open >= 200, "nothing stored: the content shows")
        defaults.set(false, forKey: InspectorSection.tags.key)
        #expect(Self.height(of: .tags, in: defaults) < open - 100, "folded: only the heading")
        #expect(Self.height(of: .properties, in: defaults) == open, "another section is not folded with it")
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

    private static func presentation(typing text: String, into id: ItemID, key: String = "assignee") -> DetailsPresentation {
        let presentation = DetailsPresentation()
        let draft = presentation.draft(for: id, key: key)
        draft.field = field
        draft.base = ""
        draft.text = text
        draft.isDirty = true
        return presentation
    }

    @Test func aDraftOnAnItemDeletedElsewhereIsHandedBackWhenTheRowGoes() throws {
        let library = FakeItemLibrary()
        let gone = ItemID.mint()
        let presentation = Self.presentation(typing: "mine", into: gone)
        presentation.handOffProperties(in: library, undoManager: nil)
        #expect(try #require(library.notices.waiting.first).text == "Assignee: mine")
        #expect(presentation.unsavedProperties().isEmpty)
    }

    @Test func aFieldTheLibraryNoLongerTakesIsHandedBackAsNotSaved() throws {
        // The fake refuses every property write, as the library does for a field a type change removed.
        let library = FakeItemLibrary()
        let item = FakeItemLibrary.note("Task", modified: .now)
        library.items = [item]
        let presentation = Self.presentation(typing: "mine", into: item.id)
        presentation.handOffProperties(in: library, undoManager: nil)
        let notice = try #require(library.notices.waiting.first)
        #expect(notice.text == "Assignee: mine")
        #expect(notice.message.contains("could not be saved"))
    }

    @Test func foldingASectionKeepsADraftButAnItemSwitchHandsItBack() throws {
        let library = FakeItemLibrary()
        let first = ItemID.mint()
        let second = ItemID.mint()
        let presentation = Self.presentation(typing: "mine", into: first)
        // A fold or a hidden inspector reaches no hand-off, so the draft waits.
        #expect(presentation.unsavedProperties(of: first).count == 1)
        presentation.handOffProperties(of: second, in: library, undoManager: nil)
        #expect(presentation.unsavedProperties(of: first).count == 1 && library.notices.waiting.isEmpty)
        presentation.handOffProperties(of: first, in: library, undoManager: nil)
        #expect(presentation.unsavedProperties().isEmpty)
        #expect(library.notices.waiting.count == 1)
    }

    @Test func aSelectionChangeHandsBackEveryDraftButTheShownItemsWhetherOrNotTheInspectorShows() throws {
        let library = FakeItemLibrary()
        let shown = ItemID.mint()
        let left = ItemID.mint()
        let presentation = Self.presentation(typing: "kept", into: shown)
        let draft = presentation.draft(for: left, key: "assignee")
        draft.field = Self.field
        draft.base = ""
        draft.text = "held back"
        draft.isDirty = true
        presentation.handOffProperties(except: shown, in: library, undoManager: nil)
        #expect(presentation.unsavedProperties(of: shown).count == 1)
        #expect(presentation.unsavedProperties(of: left).isEmpty)
        #expect(try #require(library.notices.waiting.first).text == "Assignee: held back")
        // Again, as the next change of selection would: a draft is told once.
        presentation.handOffProperties(except: shown, in: library, undoManager: nil)
        #expect(library.notices.waiting.count == 1)
        // With nothing shown, the rest goes too.
        presentation.handOffProperties(except: nil, in: library, undoManager: nil)
        #expect(presentation.unsavedProperties().isEmpty)
    }

    @Test func quittingHandsBackTheDraftsOfEveryWindow() throws {
        let library = FakeItemLibrary()
        let one = Self.presentation(typing: "one", into: ItemID.mint())
        let two = Self.presentation(typing: "two", into: ItemID.mint())
        DetailsPresentation.handOffAllProperties(in: library)
        #expect(one.unsavedProperties().isEmpty && two.unsavedProperties().isEmpty)
        let text = try #require(library.notices.waiting.first?.text)
        #expect(text.contains("Assignee: one") && text.contains("Assignee: two"))
    }

    @Test func titlesAndTagsAreNotPropertyDrafts() {
        let id = ItemID.mint()
        let presentation = DetailsPresentation()
        for key in ["title", "new-tag"] {
            let draft = presentation.draft(for: id, key: key)
            draft.text = "x"
            draft.isDirty = true
        }
        #expect(presentation.unsavedProperties().isEmpty)
        #expect(presentation.unsavedTitles == [id])
    }

    // MARK: The relationship plus

    /// What an accessibility element answers to `selector`, whatever class SwiftUI made it.
    private static func answer(_ element: NSObject, _ selector: String) -> Any? {
        let selector = NSSelectorFromString(selector)
        return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
    }

    /// The accessibility elements under `element`.
    private static func descendants(of element: Any?, into found: inout [NSObject]) {
        guard let element = element as? NSObject else { return }
        found.append(element)
        for child in answer(element, "accessibilityChildren") as? [Any] ?? [] { descendants(of: child, into: &found) }
    }

    @Test func theHiddenPlusStaysInTheAccessibilityTree() throws {
        let view = InspectorPlusButton(accessibilityLabel: "Add to Related", identifier: "Plus", isRowHovered: false, action: {})
            .frame(width: 100, height: 40)
        // SwiftUI builds its accessibility elements only once an assistive client is attached.
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        var found: [NSObject] = []
        Self.descendants(of: host, into: &found)
        let labels = found.compactMap { Self.answer($0, "accessibilityLabel") as? String }
        let roles = found.compactMap { Self.answer($0, "accessibilityRole") as? String }
        #expect(labels.contains("Add to Related") && roles.contains("AXButton"))
    }

    @Test func theHiddenPlusMenuStaysInTheAccessibilityTree() throws {
        let view = InspectorPlusMenu(accessibilityLabel: "Add to Related", identifier: "Plus", isRowHovered: false) { Button("Item") {} }
            .frame(width: 100, height: 40)
        // SwiftUI builds its accessibility elements only once an assistive client is attached.
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        var found: [NSObject] = []
        Self.descendants(of: host, into: &found)
        // A menu's button takes its name from the system when drawn, so it is found by role and identifier.
        let roles = found.compactMap { Self.answer($0, "accessibilityRole") as? String }
        let identifiers = found.compactMap { Self.answer($0, "accessibilityIdentifier") as? String }
        #expect(roles.contains("AXMenuButton") && identifiers.contains("Plus"))
    }
}
