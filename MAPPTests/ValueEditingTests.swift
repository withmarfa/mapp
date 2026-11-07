import AppKit
import Foundation
import struct Marfa.ItemDate
import Testing
@testable import MAPP

/// What a value panel lists, where it opens, and that one is open at a time.
@MainActor
struct ValueEditingTests {
    private static let task = TypeID("core.task")
    private static let words: [StatusWord] = [
        .init(value: "done", group: .completed), .init(value: "doing", group: .inProgress), .init(value: "todo", group: .notStarted),
    ]
    private static let status = ItemTypeInfo.Field(key: "status", label: "Status", kind: .status(words), declaredBy: task)
    private static let priority = ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(["low", "high"]), declaredBy: task)
    private static let note = ItemTypeInfo.Field(key: "note", label: "Note", kind: .text, declaredBy: task)
    private static let points = ItemTypeInfo.Field(key: "points", label: "Points", kind: .number, declaredBy: task)
    private static let labels = ItemTypeInfo.Field(key: "labels", label: "Labels", kind: .words, declaredBy: task)
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: task, label: "Task", fields: [status, priority, note, points, labels], titleField: "title", bodyField: "body", parent: nil)
    ])

    private static func item(_ properties: [String: PropertyValue] = [:], id: String = "10000000-0000-0000-0000-000000000001") -> Item {
        Item(
            id: ItemID(id), type: task, title: "Title", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .now, modified: .now)
    }

    private static func library(_ items: [Item]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: items)
        library.catalogue = catalogue
        return library
    }

    private static func request(_ kind: ValueEditKind, item: Item, in library: FakeItemLibrary, write: @escaping (PropertyValue?) -> Bool = { _ in false }) -> ValueEditRequest {
        ValueEditRequest(kind: kind, library: library, item: item.id, write: write)
    }

    // MARK: Options

    @Test func statusWordsListUnderTheirGroupsAsTheTypeDeclaresThemWithAnUndeclaredWordUnderOther() {
        let rows = ValueEditOptions.statusRows(field: Self.status, current: "stale")
        let outline = rows.map { $0.role == .header ? "# " + $0.title : $0.role == .separator ? "-" : $0.title }
        let titles = ["# " + StatusBucket.group(.completed).title, "Done", "# " + StatusBucket.group(.inProgress).title, "Doing",
                      "# " + StatusBucket.group(.notStarted).title, "Todo", "# " + StatusBucket.other.title, "Stale", "-", "Not Set"]
        #expect(outline == titles)
        #expect(rows.first { $0.title == "Stale" }?.isCurrent == true)
    }

    @Test func nothingSetMarksNotSetAsCurrent() {
        let rows = ValueEditOptions.statusRows(field: Self.status, current: nil)
        #expect(rows.last?.isCurrent == true)
        #expect(rows.dropLast().allSatisfy { !$0.isCurrent })
    }

    // MARK: Quick dates

    @Test func quickDatesFollowThePersonsCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        calendar.firstWeekday = 2
        // Friday 6 November in UTC is already Saturday 7 November in Auckland.
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 11, day: 6, hour: 12))!
        let days = QuickDates.entries(now: now, calendar: calendar).map { calendar.dateComponents([.year, .month, .day], from: $0.date) }
        #expect(days.map(\.day) == [7, 8, 9])
        #expect(days.allSatisfy { $0.month == 11 })
    }

    // MARK: Frame

    private static let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func panelOpensBelowTheValueAndEndsWithANarrowValueWithinTheWidthLimits() {
        let narrow = ValuePanelFrame.placement(
            anchor: CGRect(x: 300, y: 500, width: 100, height: 20), visible: Self.screen, contentHeight: 200, floor: 220, ceiling: 320, gap: 4)
        #expect(narrow.frame == CGRect(x: 180, y: 296, width: 220, height: 200))
        #expect(!narrow.isAbove)
        let wide = ValuePanelFrame.placement(
            anchor: CGRect(x: 100, y: 500, width: 600, height: 20), visible: Self.screen, contentHeight: 200, floor: 220, ceiling: 320, gap: 4)
        #expect(wide.frame.width == 320)
        #expect(wide.frame.minX == 100)
    }

    @Test func panelFlipsAboveWhenThereIsNoRoomBelowAndStaysOnScreen() {
        let placement = ValuePanelFrame.placement(
            anchor: CGRect(x: 900, y: 100, width: 80, height: 20), visible: Self.screen, contentHeight: 300, floor: 220, ceiling: 320, gap: 4)
        #expect(placement.isAbove)
        #expect(placement.frame.minY == 124)
        #expect(placement.frame.maxX <= Self.screen.maxX)
    }

    @Test func panelShorterThanItsContentWhereNeitherSideFitsIt() {
        let placement = ValuePanelFrame.placement(
            anchor: CGRect(x: 100, y: 400, width: 200, height: 20), visible: Self.screen, contentHeight: 2000, floor: 220, ceiling: 320, gap: 4)
        #expect(placement.frame.height < 2000)
        #expect(placement.frame.minY >= 0 && placement.frame.maxY <= Self.screen.maxY)
    }

    // MARK: Writing

    @Test func aRefusedWriteKeepsThePanelOpenAndSaysWhy() {
        let item = Self.item()
        let model = ValueEditModel(Self.request(.status(Self.status), item: item, in: Self.library([item])))
        var closed = false
        model.close = { closed = true }
        model.activate(ValueEditOptions.optionID("doing"))
        #expect(!closed)
        #expect(model.notice != nil)
    }

    @Test func aTakenChoiceClosesThePanel() {
        let item = Self.item()
        let model = ValueEditModel(Self.request(.status(Self.status), item: item, in: Self.library([item]), write: { _ in true }))
        var closed = false
        model.close = { closed = true }
        model.activate(ValueEditOptions.optionID("doing"))
        #expect(closed)
        #expect(model.notice == nil)
    }

    // MARK: Kinds

    @Test func everyKindOfValueThePanelEditsIsFoundByTheFieldsKindAndNotItsName() {
        #expect(ValueEditKind(field: Self.note) == .text(Self.note))
        #expect(ValueEditKind(field: Self.points)?.isNumber == true)
        #expect(ValueEditKind(field: Self.labels) == .words(Self.labels))
        #expect(ValueEditKind(field: ItemTypeInfo.Field(key: "done", label: "Done", kind: .boolean, declaredBy: Self.task)) == nil)
        #expect([ValueEditKind.tags, .parent, .text(Self.note)].map(\.rowID) == [PagePlacement.tags, PagePlacement.parent, "note"])
    }

    // MARK: Typed values

    @Test func aRefusedTextKeepsWhatWasTypedAndTheCancelledPanelHandsNothingOver() {
        let item = Self.item(["note": .string("old")])
        let library = Self.library([item])
        let model = ValueEditModel(Self.request(.text(Self.note), item: item, in: library))
        var closed = false
        model.close = { closed = true }
        model.typed = "new"
        model.submitTyped()
        #expect(!closed && model.typed == "new" && model.notice != nil)
        model.finish(cancelled: true)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func aPanelEndedByAClickElsewhereGivesBackTheTextItCouldNotWrite() {
        let item = Self.item(["note": .string("old")])
        let library = Self.library([item])
        let model = ValueEditModel(Self.request(.text(Self.note), item: item, in: library))
        model.typed = "my careful words"
        model.finish(cancelled: false)
        #expect(library.notices.waiting.first?.text == "Note: my careful words")
    }

    @Test func aTextTheItemHoldsAlreadyIsNotWrittenAndClosesThePanel() {
        let item = Self.item(["note": .string("same")])
        var writes = 0
        let model = ValueEditModel(Self.request(.text(Self.note), item: item, in: Self.library([item]), write: { _ in writes += 1; return true }))
        var closed = false
        model.close = { closed = true }
        model.typed = "same"
        model.submitTyped()
        #expect(closed && writes == 0)
    }

    @Test func aNumberThatIsNotOneIsNotWrittenAndSaysSo() {
        let item = Self.item()
        var writes = 0
        let model = ValueEditModel(Self.request(.number(Self.points), item: item, in: Self.library([item]), write: { _ in writes += 1; return true }))
        model.typed = "twelve"
        model.submitTyped()
        #expect(writes == 0 && model.notice != nil && model.typed == "twelve")
    }

    @Test func aValueChangedUnderWhatWasTypedWaitsForThePersonToChoose() {
        let item = Self.item(["note": .string("old")])
        let library = Self.library([item])
        var written: [PropertyValue?] = []
        let model = ValueEditModel(Self.request(.text(Self.note), item: item, in: library, write: { written.append($0); return true }))
        model.typed = "mine"
        library.items[0].properties = [Property(key: "note", value: .string("theirs"))]
        model.submitTyped()
        #expect(model.hasConflict && written.isEmpty)
        model.keepEdit()
        #expect(written == [.string("mine")])
    }

    // MARK: Words and the parent

    @Test func aWordIsAddedToTheListAndANewOneIsOfferedWhileTyping() {
        let item = Self.item(["labels": .array([.string("red")])])
        var written: [PropertyValue?] = []
        let model = ValueEditModel(Self.request(.words(Self.labels), item: item, in: Self.library([item]), write: { written.append($0); return true }))
        #expect(model.heldTokens == ["red"])
        model.query = "blue"
        #expect(model.rows.contains { $0.role == .create })
        model.activate("create")
        #expect(written == [.array([.string("red"), .string("blue")])])
        #expect(model.query.isEmpty)
    }

    @Test func aParentTheLibraryRefusesStaysOpenWithTheReason() async {
        let (child, other) = (Self.item(), Self.item(id: "10000000-0000-0000-0000-000000000002"))
        let library = Self.library([child, other])
        library.refusals[child.id] = [other.id: "That would make a loop."]
        library.acceptsRelationships = true
        let model = ValueEditModel(Self.request(.parent, item: child, in: library))
        var closed = false
        model.close = { closed = true }
        model.activate("parent:" + other.id.rawValue)
        while model.isSaving { await Task.yield() }
        #expect(!closed && model.notice == "That would make a loop." && library.relationshipWrites.isEmpty)
    }

    @Test func aParentTheLibraryTakesClosesThePanel() async {
        let (child, other) = (Self.item(), Self.item(id: "10000000-0000-0000-0000-000000000002"))
        let library = Self.library([child, other])
        library.acceptsRelationships = true
        let model = ValueEditModel(Self.request(.parent, item: child, in: library))
        var closed = false
        model.close = { closed = true }
        model.activate("parent:" + other.id.rawValue)
        while model.isSaving { await Task.yield() }
        #expect(closed && library.relationshipWrites.map(\.adding) == [[other.id]])
    }

    // MARK: Lists written quickly

    /// A words panel over an item holding `items`, with every write it makes collected in `written`.
    private func wordsPanel(
        _ items: [String], limit: Int? = nil, writing: Bool = true, in library: FakeItemLibrary, written: Written
    ) -> ValueEditModel {
        var field = Self.labels
        field.maxItems = limit
        let item = Self.item(["labels": .array(items.map { .string($0) })])
        library.items = [item]
        if writing { library.writingProperties = [item.id] }
        return ValueEditModel(Self.request(.words(field), item: item, in: library, write: { written.all.append($0); return true }))
    }

    private final class Written { var all: [PropertyValue?] = [] }

    private static func list(_ words: String...) -> PropertyValue { .array(words.map { .string($0) }) }

    private func add(_ word: String, to model: ValueEditModel) {
        model.query = word
        model.activate("create")
    }

    @Test func twoQuickTapsBuildOnWhatThePanelLastWroteNotOnTheCopyThatHasNotCaughtUp() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["red"], in: library, written: written)
        add("blue", to: model)
        add("green", to: model)
        #expect(written.all == [Self.list("red", "blue"), Self.list("red", "blue", "green")])
        #expect(model.heldTokens == ["red", "blue", "green"])
    }

    @Test func twoQuickRemovalsBuildOnEachOther() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["a", "b", "c"], in: library, written: written)
        model.removeToken("a")
        model.removeToken("b")
        #expect(written.all == [Self.list("b", "c"), Self.list("c")])
    }

    @Test func aWordRemovedAgainStaysRemovedWhenTheCopyShowsItsFirstWrite() {
        let (library, written) = (Self.library([]), Written())
        library.marksPropertyWrites = true
        let model = wordsPanel(["red"], in: library, written: written)
        add("blue", to: model)
        model.removeToken("blue")
        add("green", to: model)
        library.items[0].properties = [Property(key: "labels", value: Self.list("red", "blue"))]
        #expect(model.heldTokens == ["red", "green"])
        add("pink", to: model)
        #expect(written.all.last == Self.list("red", "green", "pink"))
    }

    @Test func aWriteTheCopyRefusedIsNotBuiltOn() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["red"], in: library, written: written)
        add("blue", to: model)
        #expect(model.heldTokens == ["red", "blue"])
        // The library has finished and the copy still holds the list from before: the write was refused.
        library.writingProperties = []
        #expect(model.heldTokens == ["red"])
        add("green", to: model)
        #expect(written.all.last == Self.list("red", "green"))
    }

    @Test func aChangeMadeElsewhereMeanwhileKeepsBothChanges() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["red"], in: library, written: written)
        add("blue", to: model)
        // The copy holds a word the panel never saw, and not yet the panel's own.
        library.items[0].properties = [Property(key: "labels", value: Self.list("red", "yellow"))]
        #expect(model.heldTokens == ["red", "yellow", "blue"])
        add("green", to: model)
        #expect(written.all.last == Self.list("red", "yellow", "blue", "green"))
    }

    @Test func aWriteThatLandedIsNoLongerHeldAndTheCopyIsReadAgain() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["red"], in: library, written: written)
        add("blue", to: model)
        library.items[0].properties = [Property(key: "labels", value: Self.list("red", "blue"))]
        library.writingProperties = []
        #expect(model.heldTokens == ["red", "blue"])
        library.items[0].properties = [Property(key: "labels", value: Self.list("red"))]
        #expect(model.heldTokens == ["red"])
    }

    // MARK: Limits

    @Test func aListAtItsLimitSaysSoAndWritesNothingMore() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["a", "b"], limit: 2, in: library, written: written)
        add("c", to: model)
        #expect(written.all.isEmpty)
        #expect(model.notice == "Labels can hold 2 at most.")
        model.removeToken("a")
        add("c", to: model)
        #expect(written.all == [Self.list("b"), Self.list("b", "c")] && model.notice == nil)
    }

    // MARK: People

    private static let people = ListShape(members: [
        .init(key: "name", label: "Name", kind: .text(nil)), .init(key: "email", label: "Email", kind: .text(.email)),
    ])
    private static let assignees = ItemTypeInfo.Field(key: "assignees", label: "Assignees", kind: .list(people), declaredBy: task)

    private static func person(_ name: String, _ email: String? = nil) -> PropertyValue {
        var entry: [String: PropertyValue] = ["name": .string(name)]
        if let email { entry["email"] = .string(email) }
        return .object(entry)
    }

    /// A people panel over an item holding `entries`, with other items in the library holding `others`.
    private func peoplePanel(_ entries: [PropertyValue], others: [PropertyValue] = [], writing: Bool = false, written: Written) -> ValueEditModel {
        let library = Self.library([])
        let item = Self.item(["assignees": .array(entries)])
        let more = others.enumerated().map { index, entry in
            Self.item(["assignees": .array([entry])], id: "10000000-0000-0000-0000-00000000010\(index)")
        }
        library.items = [item] + more
        if writing { library.writingProperties = [item.id] }
        return ValueEditModel(Self.request(.people(Self.assignees, Self.people), item: item, in: library, write: { written.all.append($0); return true }))
    }

    @Test func twoPeopleWithOneNameAreTwoRowsAndRemovingOneKeepsTheOther() throws {
        let (sam, other, written) = (Self.person("Sam", "one@example.com"), Self.person("Sam", "two@example.com"), Written())
        let model = peoplePanel([sam, other], written: written)
        let held = model.rows.filter(\.isCurrent)
        #expect(held.count == 2 && Set(held.map(\.id)).count == 2)
        #expect(held.map(\.detail) == ["one@example.com", "two@example.com"])
        model.activate(try #require(held.last).id)
        #expect(written.all == [PropertyValue.array([sam])])
    }

    @Test func peopleWithNoAddressAreToldByNameAndTheSameNameTwiceStillHasTwoRows() {
        let model = peoplePanel([Self.person("Ana"), Self.person("Ana")], written: Written())
        let held = model.rows.filter(\.isCurrent)
        #expect(held.count == 2 && Set(held.map(\.id)).count == 2)
    }

    @Test func aSameNamedPersonWithAnotherAddressIsStillOfferedAndAddable() throws {
        let (one, two, written) = (Self.person("Sam", "one@example.com"), Self.person("Sam", "two@example.com"), Written())
        let model = peoplePanel([one], others: [two], written: written)
        let offered = model.rows.filter { $0.id.hasPrefix("person:") }
        #expect(offered.map(\.title) == ["Sam"])
        model.activate(try #require(offered.first).id)
        #expect(written.all == [PropertyValue.array([one, two])])
    }

    @Test func aSecondTapOnThePersonJustAddedAddsNobodyAgain() {
        let (two, written) = (Self.person("Sam", "two@example.com"), Written())
        let model = peoplePanel([], others: [two], writing: true, written: written)
        model.activate("person:two@example.com")
        model.activate("person:two@example.com")
        #expect(written.all == [PropertyValue.array([two])])
    }

    // MARK: Dates

    private static let due = ItemTypeInfo.Field(key: "due", label: "Due", kind: .date(includesTime: true), declaredBy: task)
    private static let dayOnly = ItemTypeInfo.Field(key: "day", label: "Day", kind: .date(includesTime: false), declaredBy: task)

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func moment(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func datePanel(_ field: ItemTypeInfo.Field, holding value: String?, written: Written) -> ValueEditModel {
        let item = Self.item(value.map { [field.key: .string($0)] } ?? [:])
        var request = Self.request(.date(field), item: item, in: Self.library([item]), write: { written.all.append($0); return true })
        request.calendar = Self.utc
        return ValueEditModel(request)
    }

    @Test func theTimeThePickerShowsIsTheTimeWritten() {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07T09:30:00Z", written: written)
        #expect(model.hasTime)
        model.setDate(Self.moment(7, 14, 45))
        #expect(written.all == [PropertyValue.string(ItemDate.instant(Self.moment(7, 14, 45)))])
    }

    @Test func aDayOnlyValueGainsATimeAndLosesItAgain() throws {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07", written: written)
        #expect(model.allowsTime && !model.hasTime)
        model.setIncludesTime(true)
        let timed = try #require(written.all.last??.string)
        #expect(ItemDate.parse(timed)?.hasTime == true)
        let back = datePanel(Self.due, holding: timed, written: written)
        back.setIncludesTime(false)
        let day = try #require(written.all.last??.string)
        #expect(ItemDate.parse(day)?.hasTime == false)
    }

    @Test func aQuickDateKeepsTheTimeTheValueHasAndAFieldWithoutTimesNeverGainsOne() {
        let written = Written()
        datePanel(Self.due, holding: "2026-11-07T09:30:00Z", written: written).chooseDay(Self.moment(9, 0, 0))
        #expect(written.all == [PropertyValue.string(ItemDate.instant(Self.moment(9, 9, 30)))])
        let plain = datePanel(Self.dayOnly, holding: "2026-11-07", written: written)
        plain.setIncludesTime(true)
        plain.setDate(Self.moment(9, 14, 45))
        #expect(written.all.last == PropertyValue.string(ItemDate.day(Self.moment(9, 14, 45), calendar: Self.utc)))
    }

    // MARK: Rows

    @Test func rowsAreBuiltOnceUntilWhatTheyShowChanges() {
        let library = Self.library([])
        let model = wordsPanel(["red"], writing: false, in: library, written: Written())
        _ = model.rows
        _ = model.rows
        _ = model.activeRow
        #expect(model.rowsBuilt == 1)
        model.query = "bl"
        _ = model.rows
        _ = model.rows
        #expect(model.rowsBuilt == 2)
        library.items[0].properties = [Property(key: "labels", value: Self.list("red", "blue"))]
        _ = model.rows
        _ = model.rows
        #expect(model.rowsBuilt == 3)
    }

    // MARK: Quitting

    private func libraries(_ bench: HostBench, _ presenter: ValueEditPresenter) throws -> Libraries {
        let defaults = try #require(UserDefaults(suiteName: "ValueEditingTests-\(UUID().uuidString)"))
        return Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) }, valuePanels: presenter)
    }

    @Test func quittingOrChangingLibraryHandsBackTextTypedInTheOpenPanel() async throws {
        let item = Self.item(["note": .string("old")])
        let library = Self.library([item])
        let sessions = Box()
        let presenter = presenter(sessions)
        presenter.present(Self.request(.text(Self.note), item: item, in: library), anchor: anchor())
        sessions.all[0].model.typed = "my careful words"
        let bench = try HostBench()
        let kept = try libraries(bench, presenter)
        #expect(await kept.flushEditors())
        #expect(!presenter.isOpen)
        #expect(library.notices.waiting.first?.text == "Note: my careful words")
    }

    @Test func aTextTheLibraryTakesWhenThePanelIsHandedOffIsWrittenNotTold() async throws {
        let item = Self.item(["note": .string("old")])
        let library = Self.library([item])
        let (sessions, written) = (Box(), Written())
        let presenter = presenter(sessions)
        presenter.present(Self.request(.text(Self.note), item: item, in: library, write: { written.all.append($0); return true }), anchor: anchor())
        sessions.all[0].model.typed = "kept"
        let bench = try HostBench()
        let kept = try libraries(bench, presenter)
        #expect(await kept.flushEditors(within: .seconds(5)))
        #expect(written.all == [PropertyValue.string("kept")] && library.notices.waiting.isEmpty)
    }

    // MARK: Keyboard

    @Test func arrowsMoveThroughTheQuickDatesAndReturnChoosesTheOneTheyReached() {
        let item = Self.item()
        let field = ItemTypeInfo.Field(key: "due", label: "Due", kind: .date(includesTime: false), declaredBy: Self.task)
        var written: [PropertyValue?] = []
        let model = ValueEditModel(Self.request(.date(field), item: item, in: Self.library([item]), write: { written.append($0); return true }))
        model.move(by: 1)
        model.move(by: 1)
        model.activateHighlighted()
        #expect(written.count == 1)
    }

    // MARK: One at a time

    private final class FakeSession: ValueEditSession {
        let request: ValueEditRequest
        let model: ValueEditModel
        let anchor: NSView
        var window: NSWindow? { nil }
        private(set) var isOpen = false
        private(set) var moves = 0
        private(set) var rects: [NSRect] = []

        init(_ request: ValueEditRequest, anchor: NSView) {
            self.request = request
            self.anchor = anchor
            model = ValueEditModel(request)
        }

        func open() { isOpen = true }
        func close(restoringFocus: Bool) { isOpen = false }
        func anchorMoved() { moves += 1 }
        func valueMoved(to rect: NSRect) { rects.append(rect) }
    }

    private func presenter(_ sessions: Box) -> ValueEditPresenter {
        ValueEditPresenter { request, anchor, _ in
            let session = FakeSession(request, anchor: anchor)
            sessions.all.append(session)
            return session
        }
    }

    private final class Box { var all: [FakeSession] = [] }

    private func anchor() -> NSView {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let view = NSView(frame: window.contentLayoutRect)
        window.contentView = view
        return view
    }

    @Test func openingASecondEditorClosesTheFirst() {
        let (one, two) = (Self.item(id: "10000000-0000-0000-0000-000000000001"), Self.item(id: "10000000-0000-0000-0000-000000000002"))
        let library = Self.library([one, two])
        let sessions = Box()
        let presenter = presenter(sessions)
        let view = anchor()
        presenter.present(Self.request(.status(Self.status), item: one, in: library), anchor: view)
        presenter.present(Self.request(.choice(Self.priority), item: two, in: library), anchor: view)
        #expect(sessions.all.count == 2)
        #expect(!sessions.all[0].isOpen && sessions.all[1].isOpen)
        presenter.dismiss()
    }

    @Test func theItemChangingClosesTheEditor() {
        let item = Self.item()
        let sessions = Box()
        let presenter = presenter(sessions)
        presenter.present(Self.request(.status(Self.status), item: item, in: Self.library([item])), anchor: anchor())
        #expect(presenter.isOpen)
        presenter.itemChanged(to: item.id)
        #expect(presenter.isOpen)
        presenter.itemChanged(to: ItemID("10000000-0000-0000-0000-000000000009"))
        #expect(!presenter.isOpen && sessions.all.first?.isOpen == false)
    }

    @Test func openingTheSameValueAgainClosesItsEditor() {
        let item = Self.item()
        let library = Self.library([item])
        let sessions = Box()
        let presenter = presenter(sessions)
        let view = anchor()
        presenter.present(Self.request(.status(Self.status), item: item, in: library), anchor: view)
        presenter.present(Self.request(.status(Self.status), item: item, in: library), anchor: view)
        #expect(!presenter.isOpen)
    }

    @Test func aValueThatMovesWithItsEditorOpenTakesTheEditorAlong() {
        let item = Self.item()
        let sessions = Box()
        let presenter = presenter(sessions)
        let view = anchor()
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        view.addSubview(row)
        presenter.present(Self.request(.status(Self.status), item: item, in: Self.library([item])), anchor: row)
        #expect(sessions.all.first?.moves == 0)
        row.setFrameOrigin(NSPoint(x: 0, y: 40))
        #expect(sessions.all.first?.moves == 1)
        // SwiftUI moves a row by moving the view that holds its background, not the background inside it.
        view.setFrameOrigin(NSPoint(x: 0, y: 40))
        #expect(sessions.all.first?.moves == 2)
        presenter.dismiss()
        row.setFrameOrigin(NSPoint(x: 0, y: 80))
        view.setFrameOrigin(NSPoint(x: 0, y: 80))
        #expect(sessions.all.first?.moves == 2)
    }

    @Test func aValueThePageMovesTakesItsOwnEditorAlongAndNoOthers() throws {
        let item = Self.item()
        let sessions = Box()
        let presenter = presenter(sessions)
        presenter.present(Self.request(.status(Self.status), item: item, in: Self.library([item])), anchor: anchor())
        let moved = NSRect(x: 5, y: 60, width: 200, height: 24)
        presenter.valueMoved(item: item.id, row: Self.status.key, to: moved)
        #expect(sessions.all.first?.rects == [moved])
        presenter.valueMoved(item: item.id, row: "other", to: moved)
        presenter.valueMoved(item: ItemID("elsewhere"), row: Self.status.key, to: moved)
        #expect(sessions.all.first?.rects == [moved], "a move of another value is not this editor's")
        presenter.dismiss()
        presenter.valueMoved(item: item.id, row: Self.status.key, to: moved)
        #expect(sessions.all.first?.rects == [moved])
    }

    @Test func theValueMovedMessageCarriesTheRowAndTheValuesNewRectangle() throws {
        let body: [String: Any] = ["type": "valueMoved", "item": "10000000-0000-0000-0000-000000000001", "row": "status", "rect": [10, 20, 30, 40], "viewportHeight": 800]
        guard case .valueMoved(let item, let row, let rect, let height) = try #require(EditorMessage(body: body)) else {
            Issue.record("Not a valueMoved message")
            return
        }
        #expect(item == ItemID("10000000-0000-0000-0000-000000000001") && row == "status")
        #expect(rect == CGRect(x: 10, y: 20, width: 30, height: 40) && height == 800)
    }

    // MARK: The page

    @Test func theEditValueMessageCarriesTheRowAndTheValuesRectangle() throws {
        let body: [String: Any] = ["type": "editValue", "item": "10000000-0000-0000-0000-000000000001", "row": "status", "rect": [10, 20, 30, 40], "viewportHeight": 800]
        guard case .editValue(let item, let row, let rect, let height) = try #require(EditorMessage(body: body)) else {
            Issue.record("Not an editValue message")
            return
        }
        #expect(item == ItemID("10000000-0000-0000-0000-000000000001") && row == "status")
        #expect(rect == CGRect(x: 10, y: 20, width: 30, height: 40) && height == 800)
        #expect(EditorMessage(body: ["type": "editValue", "item": "x", "row": "", "rect": [1, 2, 3, 4], "viewportHeight": 1]) == nil)
    }
}
