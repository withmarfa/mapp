import AppKit
import Foundation
import struct Marfa.ItemDate
import Testing
@testable import MarfaMac

/// What a value panel lists, where it opens, and that one is open at a time.
@MainActor
@Suite(.hangLimit)
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

    // MARK: Kinds

    @Test func everyKindOfValueThePanelEditsIsFoundByTheFieldsKindAndNotItsName() {
        #expect(ValueEditKind(field: Self.note) == .text(Self.note))
        #expect(ValueEditKind(field: Self.points)?.isNumber == true)
        #expect(ValueEditKind(field: Self.labels) == .words(Self.labels))
        let done = ItemTypeInfo.Field(key: "done", label: "Done", kind: .boolean, declaredBy: Self.task)
        #expect(ValueEditKind(field: done) == .yesNo(done))
        #expect([ValueEditKind.tags, .relation(PagePlacement.parent), .text(Self.note)].map(\.rowID) == [PagePlacement.tags, PagePlacement.parent, "note"])
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

    // MARK: Links

    private static let parentField = RelationField(
        field: "child-of", label: "Parent", cardinality: .one, allowedTypes: [], targets: [], editability: .editable)
    private static let aboutField = RelationField(
        field: "about", label: "About", cardinality: .many, allowedTypes: [], targets: [], editability: .editable)

    /// A panel for `field` over an item that holds no link yet, with one other item to link.
    private func linkPanel(_ field: RelationField) -> (model: ValueEditModel, library: FakeItemLibrary, item: Item, other: Item) {
        let (item, other) = (Self.item(), Self.item(id: "10000000-0000-0000-0000-000000000002"))
        let library = Self.library([item, other])
        library.relationFieldsByItem[item.id] = [field]
        library.candidatesByItem[item.id] = [other]
        let model = ValueEditModel(Self.request(.relation(field.field), item: item, in: library))
        return (model, library, item, other)
    }

    @Test func aLinkTheLibraryRefusesStaysOpenWithTheReasonAndKeepsWhatWasTyped() async {
        let (model, library, item, other) = linkPanel(Self.parentField)
        library.refusals[item.id] = [other.id: "That would make a loop."]
        var closed = false
        model.close = { closed = true }
        model.query = other.displayTitle
        model.activate(ValueEditModel.linkPrefix + other.id.rawValue)
        while model.isSaving { await Task.yield() }
        #expect(!closed && model.notice == "That would make a loop.")
        #expect(model.query == other.displayTitle, "a refusal loses nothing typed")
    }

    @Test func aCopyNotYetWholeSaysSoAndChangesNothing() async {
        let (model, library, _, other) = linkPanel(Self.aboutField)
        library.linkAnswer = .incomplete
        model.activate(ValueEditModel.linkPrefix + other.id.rawValue)
        while model.isSaving { await Task.yield() }
        #expect(model.notice == EdgeVerdict.incomplete.reason)
    }

    @Test func aLinkTheLibraryTakesClosesAPanelOfOneLinkAndReplacesWhatItHeld() async {
        let (model, library, item, other) = linkPanel(Self.parentField)
        library.acceptsRelationships = true
        var closed = false
        model.close = { closed = true }
        model.activate(ValueEditModel.linkPrefix + other.id.rawValue)
        while model.isSaving { await Task.yield() }
        #expect(closed)
        #expect(library.relationshipWrites.count == 1, "one commit is one call, so one undo step")
        #expect(library.relationshipWrites.first?.item == item.id && library.relationshipWrites.first?.adding == [other.id])
    }

    @Test func aLinkTheLibraryTakesLeavesAPanelOfManyOpenAndNamesOnlyWhatChanged() async {
        let (model, library, _, other) = linkPanel(Self.aboutField)
        library.acceptsRelationships = true
        var closed = false
        model.close = { closed = true }
        model.query = "oth"
        model.activate(ValueEditModel.linkPrefix + other.id.rawValue)
        while model.isSaving { await Task.yield() }
        #expect(!closed && model.query.isEmpty)
        #expect(library.relationshipWrites.map(\.adding) == [[other.id]] && library.relationshipWrites.map(\.removing) == [[]])
    }

    @Test func aChildUnderAnotherParentSaysSoInTheListAndAfterTheMove() async {
        let children = RelationField(
            field: "inverse:parent-of", label: "Children", cardinality: .many, allowedTypes: [], targets: [], editability: .editable)
        let (model, library, _, other) = linkPanel(children)
        let parent = Self.item(["title": .string("Alpha")], id: "10000000-0000-0000-0000-000000000003")
        library.items.append(parent)
        library.takenFrom[other.id] = parent.id
        library.acceptsRelationships = true
        let row = ValueEditModel.linkPrefix + other.id.rawValue
        #expect(model.rows.first { $0.id == row }?.detail == "In \(parent.displayTitle)")
        #expect(model.moved == nil)
        model.activate(row)
        while model.isSaving { await Task.yield() }
        #expect(model.moved?.contains(parent.displayTitle) == true, "the panel's line says which parent the item left")
        #expect(library.relationshipWrites.count == 1, "the move is one call, so one undo step")
    }

    @Test func aKeystrokeReadsTheFieldFromTheRevisionItHasAndNotFromTheLibraryAgain() {
        let (model, library, item, _) = linkPanel(Self.aboutField)
        for typed in ["o", "ot", "oth", "othe"] {
            model.query = typed
            _ = model.rows
            _ = model.chips
            _ = model.takesLinks
        }
        #expect(library.relationFieldReads == 1)
        library.relationFieldsByItem[item.id] = [
            RelationField(field: "about", label: "About", cardinality: .many, allowedTypes: [], targets: [], editability: .readOnly("In the text."))
        ]
        #expect(!model.takesLinks)
        #expect(library.relationFieldReads == 2, "a change of the library's links is read again")
    }

    @Test func aFieldHoldingManyLinksShowsThirtyChipsThenMoreWhichShowsTheRest() {
        let held = (0..<45).map { ItemRelationshipTarget(title: "Item \($0)", itemID: ItemID(String(format: "20000000-0000-0000-0000-%012d", $0)), resolution: .resolved(ItemID(String(format: "20000000-0000-0000-0000-%012d", $0)))) }
        let field = RelationField(
            field: "about", label: "About", cardinality: .many, allowedTypes: [], targets: held, editability: .editable)
        let (model, _, _, _) = linkPanel(field)
        var chips = model.chips
        #expect(chips.count == 31)
        #expect(chips.last?.title == PageHead.moreLinksText(15) && chips.last?.isRemovable == false)
        model.remove(chips[30])
        chips = model.chips
        #expect(chips.count == 45 && !chips.contains { $0.revealsMore })
    }

    @Test func aFieldOfOneLinkListsTheLinkItHoldsLitFirstWithOpenAndAnUnmatchedTextSaysSo() {
        let (item, other) = (Self.item(), Self.item(id: "10000000-0000-0000-0000-000000000002"))
        let library = Self.library([item, other])
        let field = RelationField(
            field: "child-of", label: "Parent", cardinality: .one, allowedTypes: [],
            targets: [ItemRelationshipTarget(title: other.displayTitle, itemID: other.id, resolution: .resolved(other.id))], editability: .editable)
        library.relationFieldsByItem[item.id] = [field]
        library.candidatesByItem[item.id] = [other]
        let model = ValueEditModel(Self.request(.relation(field.field), item: item, in: library))
        let rows = model.rows
        #expect(rows.first?.id == ValueEditModel.linkPrefix + other.id.rawValue && rows.first?.isCurrent == true)
        #expect(rows.dropFirst().first?.id == ValueEditModel.openID)
        #expect(model.activeRow == rows.first?.id, "the held link is lit")
        model.query = "zzzz"
        #expect(model.rows.map(\.title) == ["No Results"])
    }

    @Test func aPanelForAFieldTheItemCannotChangeTakesNoLink() async {
        let locked = RelationField(
            field: "references", label: "References", cardinality: .many, allowedTypes: [], targets: [], editability: .readOnly("In the text."))
        let (model, library, _, other) = linkPanel(locked)
        library.acceptsRelationships = true
        #expect(!model.isEditable)
        model.activate(ValueEditModel.linkPrefix + other.id.rawValue)
        #expect(library.relationshipWrites.isEmpty)
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
    private func peoplePanel(_ entries: [PropertyValue], others: [PropertyValue] = [], writing: Bool = false, in library: FakeItemLibrary = Self.library([]), written: Written) -> ValueEditModel {
        let item = Self.item(["assignees": .array(entries)])
        let more = others.enumerated().map { index, entry in
            Self.item(["assignees": .array([entry])], id: "10000000-0000-0000-0000-00000000010\(index)")
        }
        library.items = [item] + more
        if writing { library.writingProperties = [item.id] }
        return ValueEditModel(Self.request(.people(Self.assignees, Self.people), item: item, in: library, write: { written.all.append($0); return true }))
    }

    @Test func twoPeopleWithOneNameAreTwoChipsAndRemovingOneKeepsTheOther() throws {
        let (sam, other, written) = (Self.person("Sam", "one@example.com"), Self.person("Sam", "two@example.com"), Written())
        let model = peoplePanel([sam, other], written: written)
        let held = model.chips
        #expect(held.count == 2 && Set(held.map(\.id)).count == 2)
        model.remove(try #require(held.last))
        #expect(written.all == [PropertyValue.array([sam])])
    }

    @Test func theSameNameTwiceWithNoAddressStillHasTwoChips() {
        let model = peoplePanel([Self.person("Ana"), Self.person("Ana")], written: Written())
        let held = model.chips
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

    @Test func aTimeTypedInTheFieldIsWrittenOnTheDayTheValueHolds() {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07T09:30:00Z", written: written)
        #expect(model.hasTime)
        model.timeDraft = "2:45 pm"
        model.commitTime()
        #expect(written.all == [PropertyValue.string(ItemDate.instant(Self.moment(7, 14, 45)))])
    }

    @Test func aDayOnlyValueGainsATimeFromTheFieldAndLosesItWhenTheFieldIsEmptied() throws {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07", written: written)
        #expect(model.allowsTime && !model.hasTime && model.timeText.isEmpty)
        model.timeDraft = "9:30"
        model.commitTime()
        let timed = try #require(written.all.last??.string)
        #expect(ItemDate.parse(timed)?.hasTime == true)
        let back = datePanel(Self.due, holding: timed, written: written)
        back.timeDraft = "  "
        back.commitTime()
        let day = try #require(written.all.last??.string)
        #expect(ItemDate.parse(day)?.hasTime == false)
    }

    @Test func aTimeThatIsNotOneIsRefusedWithAReasonAndWritesNothing() {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07", written: written)
        model.timeDraft = "later"
        model.commitTime()
        #expect(written.all.isEmpty)
        #expect(model.notice != nil)
    }

    @Test func aTimeTypedBeforeTheItemBecomesReadOnlyIsHandedBackNotDropped() {
        let written = Written()
        let item = Self.item(["due": .string("2026-11-07T09:30:00Z")])
        let library = Self.library([item])
        var request = Self.request(.date(Self.due), item: item, in: library, write: { written.all.append($0); return true })
        request.calendar = Self.utc
        let model = ValueEditModel(request)
        model.timeDraft = "2:45 pm"
        library.items[0].readOnly = true
        model.commitTime()
        #expect(written.all.isEmpty)
        #expect(library.notices.waiting.first?.text == "Due: 2:45 pm")
    }

    @Test func aTimeTheLibraryRefusesStaysInTheFieldAndIsHandedBackWhenThePanelEnds() {
        let item = Self.item(["due": .string("2026-11-07T09:30:00Z")])
        let library = Self.library([item])
        var request = Self.request(.date(Self.due), item: item, in: library, write: { _ in false })
        request.calendar = Self.utc
        let model = ValueEditModel(request)
        model.timeDraft = "2:45 pm"
        model.commitTime()
        #expect(model.timeDraft == "2:45 pm" && model.notice != nil && library.notices.waiting.isEmpty)
        model.finish(cancelled: false)
        #expect(library.notices.waiting.first?.text == "Due: 2:45 pm")
    }

    @Test func aWordTypedBeforeTheItemBecomesReadOnlyIsHandedBackNotDropped() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["red"], in: library, written: written)
        model.query = "blue"
        library.items[0].readOnly = true
        model.activate("create")
        #expect(written.all.isEmpty)
        #expect(library.notices.waiting.first?.text == "Labels: blue")
    }

    @Test func aPersonTypedBeforeTheItemBecomesReadOnlyIsHandedBackNotDropped() {
        let written = Written()
        let library = Self.library([])
        let model = peoplePanel([], in: library, written: written)
        model.query = "Sam"
        library.items[0].readOnly = true
        model.activate("create")
        #expect(written.all.isEmpty)
        #expect(library.notices.waiting.first?.text?.contains("Sam") == true)
    }

    @Test func aNewTagTheItemCanNoLongerTakeIsHandedBackOnceWhenTheTagsBoxEnds() {
        let item = Self.item()
        let library = Self.library([item])
        let model = ValueEditModel(Self.request(.tags, item: item, in: library))
        model.query = "fresh"
        library.items[0].state = .trashed
        model.finishTagField()
        #expect(library.notices.told == 1 && library.notices.waiting.first?.text == "fresh")
    }

    @Test func aTimeAlreadySavedFromElsewhereIsNotHandedBackWhenTheItemBecomesReadOnly() {
        let item = Self.item(["due": .string("2026-11-07T09:30:00Z")])
        let library = Self.library([item])
        var request = Self.request(.date(Self.due), item: item, in: library, write: { _ in true })
        request.calendar = Self.utc
        let model = ValueEditModel(request)
        model.timeDraft = "2:45 pm"
        var arrived = Self.item(["due": .string("2026-11-07T14:45:00Z")])
        arrived.readOnly = true
        library.items[0] = arrived
        model.commitTime()
        #expect(library.notices.told == 0)
    }

    @Test func aTimeIsNotWrittenOverOneThatArrivedFromElsewhereAndIsHandedBackInstead() {
        let written = Written()
        let item = Self.item(["due": .string("2026-11-07T09:30:00Z")])
        let library = Self.library([item])
        var request = Self.request(.date(Self.due), item: item, in: library, write: { written.all.append($0); return true })
        request.calendar = Self.utc
        let model = ValueEditModel(request)
        model.timeDraft = "14:45"
        library.items[0] = Self.item(["due": .string("2026-11-07T16:00:00Z")])
        model.finish(cancelled: false)
        #expect(written.all.isEmpty)
        #expect(library.notices.waiting.first?.text == "Due: 14:45")
    }

    @Test func aTimeThatIsNotOneStaysInTheFieldOnFocusLossAndIsHandedBackWhenThePanelEnds() {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07", written: written)
        model.timeDraft = "later"
        model.commitTime()
        #expect(model.timeDraft == "later" && model.notice != nil)
        model.finish(cancelled: false)
        #expect(written.all.isEmpty)
        #expect((model.request.library as? FakeItemLibrary)?.notices.waiting.first?.text == "Due: later")
    }

    @Test func aWordTheListRefusedIsHandedBackWhenThePanelEnds() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["a", "b"], limit: 2, in: library, written: written)
        add("c", to: model)
        #expect(model.notice != nil && model.query == "c")
        model.finish(cancelled: false)
        #expect(written.all.isEmpty)
        #expect(library.notices.waiting.first?.text == "Labels: c")
    }

    @Test func aDayChosenAfterATimeArrivedElsewhereDoesNotLetTheTypedTimeWriteOverIt() {
        let written = Written()
        let item = Self.item(["due": .string("2026-11-07T09:30:00Z")])
        let library = Self.library([item])
        var request = Self.request(.date(Self.due), item: item, in: library, write: { written.all.append($0); return true })
        request.calendar = Self.utc
        let model = ValueEditModel(request)
        model.timeDraft = "14:45"
        library.items[0] = Self.item(["due": .string("2026-11-07T16:00:00Z")])
        model.chooseDay(Self.moment(8, 0, 0))
        model.finish(cancelled: false)
        #expect(written.all == [PropertyValue.string(ItemDate.instant(Self.moment(8, 16, 0)))])
        #expect(library.notices.waiting.first?.text == "Due: 14:45")
    }

    @Test func aWordTheListRefusedIsHandedBackEvenAfterAnotherChangeSucceeds() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["a", "b"], limit: 2, in: library, written: written)
        add("c", to: model)
        model.removeToken("a")
        #expect(model.notice == nil && model.query == "c")
        model.finish(cancelled: false)
        #expect(library.notices.waiting.first?.text == "Labels: c")
    }

    @Test func aFilterForAHeldWordIsNotHandedBackWhenAnotherChangeFails() {
        let item = Self.item(["labels": Self.list("red", "blue")])
        let library = Self.library([item])
        let model = ValueEditModel(Self.request(.words(Self.labels), item: item, in: library))
        model.query = "blue"
        model.removeToken("red")
        #expect(model.notice != nil)
        model.finish(cancelled: false)
        model.finish(cancelled: false)
        #expect(library.notices.told == 0)
    }

    @Test func aClearedTimeThatCouldNotBeMadeIsTold() {
        let written = Written()
        let item = Self.item(["due": .string("2026-11-07T09:30:00Z")])
        let library = Self.library([item])
        var request = Self.request(.date(Self.due), item: item, in: library, write: { written.all.append($0); return true })
        request.calendar = Self.utc
        let model = ValueEditModel(request)
        model.timeDraft = ""
        library.items[0] = Self.item(["due": .string("2026-11-07T16:00:00Z")])
        model.finish(cancelled: false)
        #expect(written.all.isEmpty)
        #expect(library.notices.told == 1 && library.notices.waiting.first?.text == nil && library.notices.holdsQuit)
    }

    @Test func aTimeIsNotWrittenOverOneThatArrivedAfterTheFieldShowedTheValueAndBeforeTheFirstKey() throws {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07T09:30:00Z", written: written)
        let library = try #require(model.request.library as? FakeItemLibrary)
        model.beginTime()
        library.items[0] = Self.item(["due": .string("2026-11-07T16:00:00Z")])
        model.timeDraft = "14:45"
        model.finish(cancelled: false)
        #expect(written.all.isEmpty)
        #expect(library.notices.waiting.first?.text == "Due: 14:45")
    }

    @Test func aWordTypedInFullAndChosenAsASuggestionIsHandedBackWhenTheListRefusesIt() {
        var field = Self.labels
        field.maxItems = 2
        let item = Self.item(["labels": Self.list("a", "b")])
        let library = Self.library([item, Self.item(["labels": Self.list("blue")], id: "10000000-0000-0000-0000-000000000101")])
        let model = ValueEditModel(Self.request(.words(field), item: item, in: library, write: { _ in true }))
        model.query = "blue"
        model.submitTyped()
        #expect(model.notice != nil)
        model.finish(cancelled: false)
        #expect(library.notices.waiting.first?.text == "Labels: blue")
    }

    @Test func aTagTheTagsBoxCanNoLongerTakeIsHandedBackBeforeTheBoxCloses() {
        let item = Self.item()
        let library = Self.library([item])
        let model = ValueEditModel(Self.request(.tags, item: item, in: library))
        var toldAtClose: Int?
        model.close = { if toldAtClose == nil { toldAtClose = library.notices.told } }
        model.query = "bluer"
        library.items[0].state = .trashed
        model.activate("tag:bluer")
        model.finishTagField()
        #expect(toldAtClose == 1 && library.notices.told == 1 && library.notices.waiting.first?.text == "bluer")
    }

    @Test func choosingNotSetHandsBackATimeTypedAndNotYetWritten() throws {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07T09:30:00Z", written: written)
        model.timeDraft = "14:45"
        model.activate(ValueEditOptions.notSetID)
        #expect(written.all == [nil])
        #expect(try #require(model.request.library as? FakeItemLibrary).notices.waiting.first?.text == "Due: 14:45")
    }

    @Test func aRefusedWordAddedOnRetryLeavesNothingForALaterSearchToInherit() {
        let (library, written) = (Self.library([]), Written())
        let model = wordsPanel(["a", "b"], limit: 2, in: library, written: written)
        add("c", to: model)
        model.removeToken("a")
        model.activate("create")
        model.query = "x"
        model.finish(cancelled: false)
        #expect(library.notices.told == 0)
    }

    @Test func aClearedTimeIsNotToldAsLostWhereAnotherDeviceClearedItFirst() throws {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07T09:30:00Z", written: written)
        let library = try #require(model.request.library as? FakeItemLibrary)
        model.timeDraft = ""
        library.items[0] = Self.item(["due": .string("2026-11-07")])
        model.finish(cancelled: false)
        #expect(written.all.isEmpty && library.notices.told == 0)
    }

    @Test func aTagThatArrivedBeforeTheItemBecameReadOnlyIsNotHandedBack() {
        let item = Self.item()
        let library = Self.library([item])
        let model = ValueEditModel(Self.request(.tags, item: item, in: library))
        model.query = "blue"
        library.items[0].tags.insert("blue")
        library.items[0].readOnly = true
        model.finishTagField()
        #expect(library.notices.told == 0)
    }

    @Test func timesAreReadAsPeopleTypeThem() {
        #expect(TimeOfDay.parse("9")?.hour == 9)
        #expect(TimeOfDay.parse("930").map { [$0.hour, $0.minute] } == [9, 30])
        #expect(TimeOfDay.parse("21.30").map { [$0.hour, $0.minute] } == [21, 30])
        #expect(TimeOfDay.parse("12 am").map { [$0.hour, $0.minute] } == [0, 0])
        #expect(TimeOfDay.parse("12:15 PM").map { [$0.hour, $0.minute] } == [12, 15])
        #expect(TimeOfDay.parse("7p").map { [$0.hour, $0.minute] } == [19, 0])
        #expect(TimeOfDay.parse("24:00") == nil)
        #expect(TimeOfDay.parse("13 pm") == nil)
        #expect(TimeOfDay.parse("9:75") == nil)
    }

    @Test func aQuickDateKeepsTheTimeTheValueHasAndAFieldWithoutTimesNeverGainsOne() {
        let written = Written()
        datePanel(Self.due, holding: "2026-11-07T09:30:00Z", written: written).chooseDay(Self.moment(9, 0, 0))
        #expect(written.all == [PropertyValue.string(ItemDate.instant(Self.moment(9, 9, 30)))])
        let plain = datePanel(Self.dayOnly, holding: "2026-11-07", written: written)
        plain.timeDraft = "14:45"
        plain.commitTime()
        #expect(written.all.count == 1, "a field without times writes none")
    }

    @Test func aDayTypedAtTheTopSetsItKeepingTheTimeAndAnUntidyOneStaysWithItsReason() {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07T09:30:00Z", written: written)
        model.beginDay()
        #expect(model.dayDraft == model.dayText && model.dayDraft?.hasSuffix(model.timeText) == true)
        model.dayDraft = "25 Nov 2026"
        model.commitDay(closing: true)
        #expect(written.all == [PropertyValue.string(ItemDate.instant(Self.moment(25, 9, 30)))])

        let item = Self.item(["due": .string("2026-11-07T09:30:00Z")])
        let library = Self.library([item])
        var request = Self.request(.date(Self.due), item: item, in: library, write: { written.all.append($0); return true })
        request.calendar = Self.utc
        let untidy = ValueEditModel(request)
        untidy.dayDraft = "sometime soon"
        untidy.commitDay()
        #expect(written.all.count == 1 && untidy.dayDraft == "sometime soon" && untidy.notice != nil)
        untidy.finish(cancelled: false)
        #expect(library.notices.waiting.first?.text == "Due: sometime soon")
    }

    @Test func aDayTypedForADateAndTimeKeepsTheWholeClockTheValueHolds() {
        let written = Written()
        let model = datePanel(Self.due, holding: "2026-11-07T09:30:42.123Z", written: written)
        model.beginDay()
        model.dayDraft = "25 Nov 2026"
        model.commitDay()
        #expect(written.all == [PropertyValue.string("2026-11-25T09:30:42.123Z")])
        let quick = Written()
        datePanel(Self.due, holding: "2026-11-07T09:30:42.123Z", written: quick).chooseDay(Self.moment(9, 0, 0))
        #expect(quick.all == [PropertyValue.string("2026-11-09T09:30:42.123Z")])
    }

    @Test func aTypedDayIsTheDayItNamesAndNothingElse() {
        #expect(TypedDay.parse("25 Nov 2026", calendar: Self.utc) == Self.moment(25, 0, 0))
        #expect(TypedDay.parse("2026-11-25", calendar: Self.utc) == Self.moment(25, 0, 0))
        #expect(TypedDay.parse("25 Nov 2026 and then some", calendar: Self.utc) == nil)
        #expect(TypedDay.parse("Ines", calendar: Self.utc) == nil)
        #expect(TypedDay.split("25 Nov 2026 at 9:30") == (day: "25 Nov 2026", time: "9:30"))
    }

    // MARK: Change Type and people

    @Test func theTypePanelListsTheSidebarsTypesFirstAndTheRestUnderALine() {
        func option(_ id: String, _ label: String) -> ItemTypeOption { ItemTypeOption(id: TypeID(id), label: label, icon: nil) }
        let options = [option("a", "Article"), option("b", "Book"), option("t", "Task"), option("n", "Note")]
        let rows = ValueEditModel.typeRows(of: options, shown: [TypeID("t"), TypeID("n"), TypeID("gone")])
        #expect(rows.map(\.title) == ["Task", "Note", "", "Article", "Book"])
        #expect(rows[2].role == .separator)
        #expect(ValueEditModel.typeRows(of: options, shown: []).map(\.title) == ["Article", "Book", "Task", "Note"])
    }

    @Test func peopleTheLibraryHoldsAsItemsAreOfferedByNameAndAddedWithTheirAddress() {
        let person = TypeID("core.entity.person")
        let addresses = ListShape(members: [
            .init(key: "value", label: "Email", kind: .text(.email), required: true), .init(key: "label", label: "Label", kind: .text(nil)),
        ])
        let field = ItemTypeInfo.Field(key: "emails", label: "Emails", kind: .list(addresses), declaredBy: person)
        var ines = Item(
            id: ItemID("10000000-0000-0000-0000-000000000200"), type: person, title: "Ines Reyes", titleRule: .property("title"),
            properties: [Property(key: "emails", value: .array([.object(["value": .string("ines@example.com")])]))],
            version: ItemVersion(1), created: .now, modified: .now)
        ines.name = "Ines Reyes"
        let task = Self.item()
        let library = FakeItemLibrary(items: [task, ines])
        library.catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: Self.task, label: "Task", fields: [Self.status], titleField: "title", bodyField: "body", parent: nil),
            ItemTypeInfo(id: person, label: "Person", fields: [field], titleField: "title", bodyField: "body", parent: nil),
        ])
        let written = Written()
        let model = ValueEditModel(Self.request(.people(Self.assignees, Self.people), item: task, in: library, write: { written.all.append($0); return true }))
        model.query = "Ines"
        let offered = model.rows.filter { $0.role == .option }
        #expect(offered.map(\.title) == ["Ines Reyes"])
        model.activate(offered[0].id)
        #expect(written.all == [PropertyValue.array([Self.person("Ines Reyes", "ines@example.com")])])
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
        let defaults = ThrowawayDefaults.make("ValueEditingTests")
        return Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) }, valuePanels: presenter)
    }

    @Test func quittingOrChangingLibraryHandsBackTextTypedInTheOpenPanel() async throws {
        let item = Self.item(["note": .string("old")])
        let library = Self.library([item])
        let sessions = Box()
        let presenter = presenter(sessions)
        presenter.present(Self.request(.text(Self.note), item: item, in: library), anchor: anchor())
        sessions.all[0].model.typed = "my careful words"
        let bench = HostBench()
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
        let bench = HostBench()
        let kept = try libraries(bench, presenter)
        #expect(await kept.flushEditors(within: .seconds(5)))
        #expect(written.all == [PropertyValue.string("kept")] && library.notices.waiting.isEmpty)
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

    @Test func theFieldMenuMessageCarriesTheRowTheLabelsRectangleAndWhetherTheValueFollowsALink() throws {
        let body: [String: Any] = [
            "type": "fieldMenu", "item": "10000000-0000-0000-0000-000000000001", "row": "in-collection", "editsValue": true,
            "rect": [10, 20, 30, 40], "viewportHeight": 800,
        ]
        guard case .fieldMenu(let item, let row, let editsValue, let rect, let height) = try #require(EditorMessage(body: body)) else {
            Issue.record("Not a fieldMenu message")
            return
        }
        #expect(item == ItemID("10000000-0000-0000-0000-000000000001") && row == "in-collection" && editsValue)
        #expect(rect == CGRect(x: 10, y: 20, width: 30, height: 40) && height == 800)
        var plain = body
        plain["editsValue"] = nil
        guard case .fieldMenu(_, _, let defaulted, _, _) = try #require(EditorMessage(body: plain)) else { return }
        #expect(!defaulted, "a page that says nothing offers no value editor")
        #expect(EditorMessage(body: ["type": "fieldMenu", "item": "x", "row": "", "rect": [1, 2, 3, 4], "viewportHeight": 1]) == nil)
    }
}
