import Foundation
import Testing
@testable import MarfaMac

/// New items typed where they will stand (`InPlaceRow`), and the rows held where they were seen (`RowHold`).
@MainActor
@Suite(.hangLimit)
struct InPlaceRowTests {
    private static let tasks = PlaceView.type(TypeID("core.task"))

    private static func browser(in library: FakeItemLibrary) -> Browser {
        let browser = Browser()
        // One store, as the app's windows share, so the row can hand its draft to the text form.
        let drafts = NewItemDrafts(file: nil)
        browser.inPlace.drafts = drafts
        browser.quickAdd.drafts = drafts
        browser.showing = tasks
        _ = library
        return browser
    }

    private static func type(_ title: String, in browser: Browser) {
        browser.inPlace.change { $0.title = title }
    }

    @Test func escapeDropsAnEmptyRowAndKeepsATypedOne() throws {
        let library = FakeItemLibrary()
        let browser = Self.browser(in: library)
        #expect(browser.beginInPlace(.table(group: nil), in: library))
        #expect(browser.inPlace.isEditing)
        browser.escapeInPlace()
        #expect(browser.inPlace.draft == nil, "an empty row goes")

        browser.beginInPlace(.table(group: nil), in: library)
        Self.type("Book the courier", in: browser)
        browser.escapeInPlace()
        #expect(browser.inPlace.draft?.title == "Book the courier", "a typed row stays in sight")
        #expect(!browser.inPlace.isEditing)
        #expect(library.items.isEmpty, "Escape adds nothing")
    }

    @Test func aChangeOfPlaceKeepsWhatWasTypedForItsPlace() throws {
        let library = FakeItemLibrary()
        let browser = Self.browser(in: library)
        browser.beginInPlace(.table(group: nil), in: library)
        Self.type("Half typed", in: browser)
        let slot = InPlaceRow.slot(.table(group: nil), in: Self.tasks)

        browser.showing = .library
        #expect(browser.inPlace.draft == nil)
        #expect(browser.inPlace.drafts.holdsDraft(slot, in: library.serverKey), "the draft is kept, not added")
        #expect(library.items.isEmpty)

        browser.showing = Self.tasks
        browser.inPlace.restore(.table(group: nil), in: Self.tasks, library: library)
        #expect(browser.inPlace.draft?.title == "Half typed")
        #expect(!browser.inPlace.isEditing, "it comes back out of the keyboard's way")
    }

    @Test func aClosedWindowLeavesTheDraftForTheNextWindow() throws {
        let library = FakeItemLibrary()
        let drafts = NewItemDrafts(file: nil)
        let first = Self.browser(in: library)
        first.inPlace.drafts = drafts
        first.beginInPlace(.lane(.option("todo")), in: library)
        Self.type("Typed on the board", in: first)
        first.leaveInPlace()

        let second = Self.browser(in: library)
        second.inPlace.drafts = drafts
        second.beginInPlace(.lane(.option("todo")), in: library)
        #expect(second.inPlace.draft?.title == "Typed on the board")
    }

    @Test func addingMakesOneItemOneUndoStepAndHoldsItWhereTyped() async throws {
        let library = FakeItemLibrary()
        let browser = Self.browser(in: library)
        let undo = UndoManager()
        undo.groupsByEvent = false
        browser.beginInPlace(.table(group: nil), in: library)
        Self.type("Order the paper samples", in: browser)
        let id = try #require(await browser.addInPlace(in: library, undoManager: undo, next: true))

        #expect(library.item(id)?.title == "Order the paper samples")
        #expect(library.item(id)?.type == TypeID("core.task"), "the place's type")
        #expect(browser.rowHold.added == [id], "it stands where it was typed")
        #expect(browser.inPlace.draft?.title == "", "the next row starts empty")
        #expect(browser.inPlace.isEditing)
        #expect(undo.canUndo)
        undo.undo()
        #expect(!undo.canUndo, "one step for the row")

        browser.escapeInPlace()
        #expect(browser.rowHold.added.isEmpty, "leaving the row lets the item take its place")
    }

    @Test func theViewsFiltersGiveTheirOneValue() throws {
        let library = FakeItemLibrary()
        let browser = Self.browser(in: library)
        var options = ItemTableOptions()
        options.filter = FilterState(clauses: [FilterClause(field: "field.priority", op: .is, values: ["high"])])
        browser.tableOptions[Self.tasks] = options
        browser.beginInPlace(.table(group: nil), in: library)
        let draft = try #require(browser.inPlace.draft)
        #expect(draft.typeID == "core.task")
        #expect(draft.properties["priority"] == .string("high"), "a filter's one value")
    }

    @Test func aRefusedCreateGivesTheTextBackToTheRow() async throws {
        let library = FakeItemLibrary()
        library.holdsCreations = true
        let browser = Self.browser(in: library)
        browser.beginInPlace(.table(group: nil), in: library)
        Self.type("Refused task", in: browser)
        let id = try #require(await browser.addInPlace(in: library, undoManager: nil, next: true))
        #expect(browser.inPlace.draft?.title == "")

        library.refusedCreations = [id]
        browser.finishNewItems(in: library)
        #expect(browser.inPlace.draft?.title == "Refused task", "never lost")
        #expect(browser.inPlace.notice != nil, "and the row says why")
    }

    @Test func aRowThatCannotBeMadeWholeGoesToTheTextForm() async throws {
        let library = FakeItemLibrary()
        let browser = Self.browser(in: library)
        browser.beginInPlace(.table(group: nil), in: library)
        // A parent the library no longer holds is never sent; the text form shows it and lets it be taken away.
        browser.inPlace.change {
            $0.title = "Under a gone parent"
            $0.setParent(ItemID("gone"))
        }
        #expect(await browser.addInPlace(in: library, undoManager: nil, next: false) == nil)
        #expect(library.items.isEmpty)
        #expect(browser.quickAdd.isPresented)
        #expect(browser.quickAdd.draft?.title == "Under a gone parent", "everything typed goes with it")
        #expect(browser.inPlace.draft == nil)
    }

    // MARK: What the place implies

    /// A task in To Do, so the tasks' board has its status lanes.
    private static func board() -> (FakeItemLibrary, Browser) {
        let task = Item(
            id: ItemID("task-1"), type: TypeID("core.task"), title: "Existing", titleRule: .property("title"),
            properties: [Property(key: "status", value: .string("todo"))], version: ItemVersion(1), created: .now, modified: .now)
        let library = FakeItemLibrary(items: [task])
        let browser = Self.browser(in: library)
        browser.viewMode = .board
        return (library, browser)
    }

    @Test func anUntouchedLaneRowHoldsNothingAndLeavingItMakesNothing() async throws {
        let (library, browser) = Self.board()
        let slot = InPlaceRow.slot(.lane(.option("todo")), in: Self.tasks)
        #expect(browser.beginInPlace(.lane(.option("todo")), in: library))
        #expect(browser.inPlace.draft?.properties["status"] == .string("todo"), "the lane gives its value")
        #expect(!browser.inPlace.holdsContent, "a value the place gives is not typed")
        #expect(await browser.addInPlace(in: library, undoManager: nil, next: false) == nil)
        #expect(library.items.count == 1, "nothing is made")
        #expect(!browser.quickAdd.isPresented, "nothing is handed on")
        #expect(!browser.inPlace.drafts.holdsDraft(slot, in: library.serverKey))

        browser.beginInPlace(.lane(.option("todo")), in: library)
        Self.type("Typed", in: browser)
        Self.type("", in: browser)
        browser.escapeInPlace()
        #expect(browser.inPlace.draft == nil, "a row typed and emptied again goes")
        #expect(!browser.inPlace.drafts.holdsDraft(slot, in: library.serverKey))
    }

    @Test func aBlockDrawnInAMixedPlaceTakesAKindWithATimeAndAloneHoldsNothing() async throws {
        let library = FakeItemLibrary()
        let event = TypeID("core.event")
        var catalogue = library.catalogue
        catalogue.itemTypes[event] = ItemTypeInfo(
            id: event, label: "Event",
            fields: [
                .init(key: MarfaMapping.startField, label: "Starts", kind: .date(includesTime: true), declaredBy: event),
                .init(key: MarfaMapping.endField, label: "Ends", kind: .date(includesTime: true), declaredBy: event),
            ],
            titleField: "title", bodyField: "body", parent: nil)
        library.catalogue = catalogue
        let browser = Self.browser(in: library)
        browser.showing = .library
        browser.viewMode = .calendar
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(browser.beginInPlace(.block(start: start, end: start.addingTimeInterval(1800)), in: library))
        let draft = try #require(browser.inPlace.draft)
        #expect(draft.typeID == event.rawValue, "a note has no time to stand at")
        #expect(draft.properties[MarfaMapping.startField] != nil)
        #expect(!browser.inPlace.holdsContent)
        #expect(await browser.addInPlace(in: library, undoManager: nil, next: false) == nil)
        #expect(library.items.isEmpty)
        #expect(!browser.quickAdd.isPresented)
    }

    @Test func aRefusedCreateOnALaneRowComesBack() async throws {
        let (library, browser) = Self.board()
        library.holdsCreations = true
        browser.beginInPlace(.lane(.option("todo")), in: library)
        Self.type("Refused in the lane", in: browser)
        let id = try #require(await browser.addInPlace(in: library, undoManager: nil, next: true))
        #expect(browser.inPlace.draft?.title == "")
        library.refusedCreations = [id]
        browser.finishNewItems(in: library)
        #expect(browser.inPlace.draft?.title == "Refused in the lane", "the next row held only the lane's value")
    }

    @Test func aHandedOnDraftStaysTheTextFormsAlone() async throws {
        let library = FakeItemLibrary()
        let browser = Self.browser(in: library)
        browser.beginInPlace(.table(group: nil), in: library)
        browser.inPlace.change {
            $0.title = "Handed on"
            $0.setParent(ItemID("gone"))
        }
        let entry = try #require(browser.inPlace.entry)
        #expect(await browser.addInPlace(in: library, undoManager: nil, next: false) == nil)
        #expect(browser.quickAdd.isPresented)
        #expect(browser.inPlace.drafts.take(entry, in: library.serverKey) == nil, "the form still holds its claim")
    }

    @Test func thePointerLeavingTheTableLetsItsRowGo() {
        let browser = Self.browser(in: FakeItemLibrary())
        let row = HeldRow(id: ItemID("a"), group: nil, index: 0)
        browser.pointerMoved(to: ItemID("a"), anchors: [ItemID("a"): row])
        #expect(browser.rowHold.pointer == row)
        browser.pointerMoved(to: nil, anchors: [ItemID("a"): row])
        #expect(browser.rowHold.pointer == nil)
    }

    @Test func aPlaceOfFilesHasNoRowToType() {
        let library = FakeItemLibrary()
        let browser = Self.browser(in: library)
        browser.viewMode = .table
        #expect(browser.typesInPlace(in: library), "a place of tasks has one")
        browser.showing = .type(.file)
        #expect(!browser.typesInPlace(in: library))
    }

    // MARK: Held rows

    private struct Row: Identifiable, Equatable {
        let id: ItemID
    }

    private static func rows(_ names: [String]) -> [Row] { names.map { Row(id: ItemID($0)) } }

    @Test func aHeldRowStaysWhereItWasSeenThoughItsChangeWouldMoveOrHideIt() {
        var hold = RowHold()
        hold.pointer = HeldRow(id: ItemID("b"), group: nil, index: 1)
        let lookup: (ItemID) -> Row? = { Row(id: $0) }
        // A status change sorted "b" last.
        #expect(hold.holding(Self.rows(["a", "c", "d", "b"]), group: nil, row: lookup).map(\.id.rawValue) == ["a", "b", "c", "d"])
        // A sync left it out of the filter.
        #expect(hold.holding(Self.rows(["a", "c", "d"]), group: nil, row: lookup).map(\.id.rawValue) == ["a", "b", "c", "d"])
        let released = hold.releasePointer()
        #expect(released, "letting it go draws again")
        #expect(hold.holding(Self.rows(["a", "c", "d"]), group: nil, row: lookup).map(\.id.rawValue) == ["a", "c", "d"])
    }

    @Test func aHeldRowStaysInItsGroupAndLeavesTheOther() {
        var hold = RowHold()
        hold.keyboard = HeldRow(id: ItemID("x"), group: "todo", index: 0)
        let lookup: (ItemID) -> Row? = { Row(id: $0) }
        #expect(hold.holding(Self.rows(["a"]), group: "todo", row: lookup).map(\.id.rawValue) == ["x", "a"])
        #expect(hold.holding(Self.rows(["x", "b"]), group: "done", row: lookup).map(\.id.rawValue) == ["b"])
    }

    @Test func itemsTypedInPlaceStandAtTheEndOrAtTheLanesTop() {
        var hold = RowHold()
        hold.added = [ItemID("new1"), ItemID("new2")]
        let lookup: (ItemID) -> Row? = { Row(id: $0) }
        #expect(hold.holding(Self.rows(["new2", "a"]), group: nil, row: lookup).map(\.id.rawValue) == ["a", "new1", "new2"])
        hold.addedIn = ItemBoardLane.holdKey(.option("todo"))
        #expect(
            hold.holding(Self.rows(["a", "new1"]), group: hold.addedIn, atTop: true, row: lookup).map(\.id.rawValue) == ["new1", "new2", "a"])
        let wasMoved = hold.releaseAdded()
        #expect(wasMoved)
        #expect(hold.added.isEmpty)
    }
}
