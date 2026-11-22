import Foundation
import Testing
@testable import MAPP

/// The filter row's clauses: what each kind and operator becomes in a saved view's filter and comes back as, the "is not"
/// rewrite, All and Any, dates relative to the day (which a view never keeps), the count of conditions, and what a clause
/// keeps in the window.
@MainActor
struct FilterClauseTests {
    private static let task = TypeID("core.task")
    private static let words: [StatusWord] = [
        .init(value: "todo", group: .notStarted), .init(value: "doing", group: .inProgress),
        .init(value: "done", group: .completed), .init(value: "dropped", group: .canceled),
    ]
    private static let status = ItemTypeInfo.Field(key: "status", label: "Status", kind: .status(words), declaredBy: task)
    private static let priority = ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(["low", "high"]), declaredBy: task)
    private static let due = ItemTypeInfo.Field(key: "due_at", label: "Due", kind: .date(includesTime: false), declaredBy: task)
    private static let starts = ItemTypeInfo.Field(key: "starts_at", label: "Starts", kind: .date(includesTime: true), declaredBy: task)
    private static let estimate = ItemTypeInfo.Field(key: "estimate", label: "Estimate", kind: .number, declaredBy: task)
    private static let notes = ItemTypeInfo.Field(key: "notes", label: "Notes", kind: .text, declaredBy: task)
    private static let done = ItemTypeInfo.Field(key: "finished", label: "Finished", kind: .boolean, declaredBy: task)
    private static let assignees = ItemTypeInfo.Field(
        key: "assignees", label: "Assignees",
        kind: .list(ListShape(members: [.init(key: "name", label: "Name", kind: .text(nil)), .init(key: "email", label: "Email", kind: .text(.email))])),
        declaredBy: task)
    private static let labels = ItemTypeInfo.Field(key: "labels", label: "Labels", kind: .words, declaredBy: task)
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(
            id: task, label: "Task", plural: "Tasks", fields: [status, priority, due, starts, estimate, notes, done, assignees, labels],
            titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: TypeID("core.note"), label: "Note", plural: "Notes", fields: [], titleField: "title", bodyField: "body", parent: nil),
    ])
    private static let columns = ItemTableLayout.columns(for: [], types: [task], catalogue: catalogue, hidden: [], looks: [:])
    private static let offer = FilterOffer.make(columns: columns, types: [task], catalogue: catalogue)
    private static let targets = offer.targets

    private static func london() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        return calendar
    }

    private static func clause(_ field: String, _ op: FilterOp, _ values: [String] = []) -> FilterClause {
        FilterClause(field: field, op: op, values: values)
    }

    private static func filter(
        _ clauses: [FilterClause], any: Bool = false, base: String? = nil, calendar: Calendar = london()
    ) -> ViewDraft.Combination {
        let parsed = try! ViewDraft.terms(of: base)
        return ViewDraft.combine(
            base: parsed, adding: FilterState(clauses: clauses, matchesAny: any), targets: targets, catalogue: catalogue, calendar: calendar,
            keeping: base)
    }

    /// What a filter reads back as.
    private static func read(_ filter: String, calendar: Calendar = london()) throws -> ViewDraft.Reading {
        ViewDraft.read(try ViewDraft.terms(of: filter), among: [task], catalogue: catalogue, calendar: calendar)
    }

    // MARK: What Filter By offers

    @Test func filterByOffersTheFieldsOfThePlacesTypesThenWhatEveryItemHas() {
        let offer = Self.offer
        #expect(offer.placeTitle == "Tasks")
        #expect(offer.placeFields.first?.kind == .status, "the status leads")
        let labels = offer.placeFields.map(\.label)
        #expect(labels.contains("Due") && labels.contains("Assignees") && labels.contains("Estimate") && labels.contains("Notes"))
        #expect(!labels.contains("Labels"), "a list of words has no way to be asked about")
        #expect(offer.everyItem.map(\.label) == ["Type", "Tags", "Collection", "Parent", "Source", "Created", "Edited", "Happened"])
        let kinds = Dictionary(uniqueKeysWithValues: offer.placeFields.map { ($0.label, $0.kind) })
        #expect(kinds["Priority"] == .choice && kinds["Due"] == .date && kinds["Estimate"] == .number)
        #expect(kinds["Notes"] == .text && kinds["Assignees"] == .people && kinds["Finished"] == .boolean)
    }

    @Test func eachKindTakesTheOperatorsTheDesignListsAndCreatedEditedHappenedNeverTakeSetOrEmpty() {
        func ops(_ kind: FilterKind) -> [FilterOp] { FilterOp.offered(for: kind).map(\.op) }
        #expect(ops(.date) == [.on, .before, .after, .between, .isSet, .isEmpty, .beforeToday, .afterToday, .inLast, .inNext])
        #expect(ops(.moment) == [.on, .before, .after, .between, .beforeToday, .afterToday, .inLast, .inNext])
        #expect(ops(.people) == [.includes, .isSet, .isEmpty], "a person not in the list cannot be asked for")
        #expect(ops(.tags) == [.includes, .isSet, .isEmpty])
        #expect(ops(.status) == [.is, .isNot, .isSet, .isEmpty])
        #expect(ops(.number) == [.equal, .notEqual, .less, .lessOrEqual, .greater, .greaterOrEqual, .isSet, .isEmpty])
        #expect(ops(.text) == [.contains, .startsWith, .is, .isNot, .isSet, .isEmpty])
        #expect(ops(.type) == [.is, .isNot])
    }

    // MARK: Writing each kind

    @Test func aDateAloneIsTheLocalMidnightWithItsOffset() throws {
        #expect(Self.filter([Self.clause("field.due_at", .before, ["2026-06-15"])]).filter == #"properties.due_at lt "2026-06-15T00:00:00+01:00""#)
        #expect(Self.filter([Self.clause("field.due_at", .before, ["2026-11-30"])]).filter == #"properties.due_at lt "2026-11-30T00:00:00Z""#)
        // After a day is from the start of the next.
        #expect(Self.filter([Self.clause("field.due_at", .after, ["2026-11-30"])]).filter == #"properties.due_at gte "2026-12-01T00:00:00Z""#)
        #expect(Self.filter([Self.clause("field.due_at", .on, ["2026-11-30"])]).filter
            == #"properties.due_at gte "2026-11-30T00:00:00Z" AND properties.due_at lt "2026-12-01T00:00:00Z""#)
        // Between holds both days whole, whichever order they were chosen in.
        let between = #"properties.due_at gte "2026-11-01T00:00:00Z" AND properties.due_at lt "2026-11-06T00:00:00Z""#
        #expect(Self.filter([Self.clause("field.due_at", .between, ["2026-11-01", "2026-11-05"])]).filter == between)
        #expect(Self.filter([Self.clause("field.due_at", .between, ["2026-11-05", "2026-11-01"])]).filter == between)
    }

    @Test func aDayAcrossAChangeOfClocksIsStillWholeAndTheOffsetFollowsTheClock() {
        // 29 March 2026 is 23 hours long in London: the clocks go forward at 01:00.
        #expect(Self.filter([Self.clause("field.due_at", .on, ["2026-03-29"])]).filter
            == #"properties.due_at gte "2026-03-29T00:00:00Z" AND properties.due_at lt "2026-03-30T00:00:00+01:00""#)
        // 25 October is 25 hours long: they go back.
        #expect(Self.filter([Self.clause("field.due_at", .on, ["2026-10-25"])]).filter
            == #"properties.due_at gte "2026-10-25T00:00:00+01:00" AND properties.due_at lt "2026-10-26T00:00:00Z""#)
        // A range across the change names each end on the clock of its own day.
        #expect(Self.filter([Self.clause("field.due_at", .between, ["2026-03-28", "2026-03-30"])]).filter
            == #"properties.due_at gte "2026-03-28T00:00:00Z" AND properties.due_at lt "2026-03-31T00:00:00+01:00""#)
    }

    @Test func createdEditedAndHappenedCompareInstantsAndCannotBeSetOrEmpty() {
        #expect(Self.filter([Self.clause("created", .before, ["2026-06-15"])]).filter == #"created_at lt "2026-06-15T00:00:00+01:00""#)
        #expect(Self.filter([Self.clause("edited", .after, ["2026-11-30"])]).filter == #"updated_at gte "2026-12-01T00:00:00Z""#)
        #expect(Self.filter([Self.clause("occurred", .on, ["2026-11-30"])]).filter
            == #"occurred_at gte "2026-11-30T00:00:00Z" AND occurred_at lt "2026-12-01T00:00:00Z""#)
        let refused = Self.filter([Self.clause("created", .isSet)])
        #expect(refused.filter == nil)
        #expect(refused.unkept == [.filter(column: "Created")])
    }

    @Test func numbersAreComparedAsNumbers() {
        let ops: [(FilterOp, String)] = [
            (.equal, "eq"), (.notEqual, "neq"), (.less, "lt"), (.lessOrEqual, "lte"), (.greater, "gt"), (.greaterOrEqual, "gte"),
        ]
        for (op, word) in ops {
            #expect(Self.filter([Self.clause("field.estimate", op, ["3.5"])]).filter == "properties.estimate \(word) 3.5", "\(op)")
        }
        #expect(Self.filter([Self.clause("field.estimate", .greater, ["12"])]).filter == "properties.estimate gt 12")
        #expect(Self.filter([Self.clause("field.estimate", .isSet)]).filter == "properties.estimate exists")
        #expect(Self.filter([Self.clause("field.estimate", .isEmpty)]).filter == "properties.estimate not_exists")
        // Words are not a number: the clause says too little to filter by, so it is neither applied nor saved.
        #expect(!Self.clause("field.estimate", .greater, ["lots"]).isComplete)
        #expect(Self.filter([Self.clause("field.estimate", .greater, ["lots"])]).filter == nil)
    }

    @Test func textIsQuotedByTheCoreAndComesBackAsTyped() throws {
        let awkward = [#"say "hi""#, #"C:\temp\"#, #"a\"b"#, "100% sure_thing", "café 🎉"]
        for text in awkward {
            for op in [FilterOp.contains, .startsWith, .is, .isNot] {
                let written = Self.filter([Self.clause("field.notes", op, [text])])
                let saved = try #require(written.filter, "\(text) \(op)")
                #expect(written.unkept.isEmpty)
                let back = try Self.read(saved)
                #expect(back.items.map(\.clause) == [Self.clause("field.notes", op, [text])], "\(text) \(op) did not come back")
            }
        }
        #expect(Self.filter([Self.clause("field.notes", .contains, ["x"])]).filter == #"properties.notes contains "x""#)
        #expect(Self.filter([Self.clause("field.notes", .startsWith, ["x"])]).filter == #"properties.notes starts_with "x""#)
    }

    @Test func peopleTagsAndLinksAreFoundByWhatTheyHold() throws {
        #expect(Self.filter([Self.clause("field.assignees", .includes, ["Rui Alves"])]).filter == #"properties.assignees.name eq "Rui Alves""#)
        #expect(Self.filter([Self.clause("field.assignees", .includes, ["Rui", "Mira"])]).filter
            == #"properties.assignees.name eq "Mira" OR properties.assignees.name eq "Rui""#)
        #expect(Self.filter([Self.clause("field.assignees", .isSet)]).filter == "properties.assignees exists")
        #expect(Self.filter([Self.clause("tags", .includes, ["kitchen"])]).filter == #"tags contains "kitchen""#)
        #expect(Self.filter([Self.clause("tags", .isSet)]).filter == "tags exists")
        #expect(Self.filter([Self.clause("tags", .isEmpty)]).filter == "tags not_exists")
        #expect(Self.filter([Self.clause("parent", .is, ["p1"])]).filter == #"backref[parent-of] eq "p1""#)
        #expect(Self.filter([Self.clause("parent", .isSet)]).filter == "backref[parent-of] exists")
        #expect(Self.filter([Self.clause("collections", .is, ["c1"])]).filter == #"edge[in-collection] eq "c1""#)
        #expect(Self.filter([Self.clause("collections", .isNot, ["c1"])]).filter == #"edge[in-collection] neq "c1""#)
        #expect(Self.filter([Self.clause("collections", .isEmpty)]).filter == "edge[in-collection] not_exists")
        #expect(Self.filter([Self.clause("source", .is, ["mail"])]).filter == #"source eq "mail""#)
        #expect(Self.filter([Self.clause("type", .isNot, ["core.note"])]).filter == #"type neq "core.note""#)
        // Back again.
        for text in [#"properties.assignees.name eq "Rui Alves""#, #"tags contains "kitchen""#, #"backref[parent-of] eq "p1""#,
                     #"edge[in-collection] neq "c1""#, #"source eq "mail""#, "tags not_exists", "properties.assignees exists"] {
            let reading = try Self.read(text)
            #expect(reading.items.count == 1, "\(text) was not shown")
            #expect(Self.filter(reading.items.map(\.clause)).filter == text, "\(text) did not write back the same")
        }
    }

    @Test func aStatusGroupIsTheGroupTermAndWordsAreTheFieldsOwn() throws {
        let groups = Self.filter([Self.clause("field.status", .is, [FilterClause.groupValue(.inProgress)])])
        #expect(groups.filter == #"status_group eq "in_progress""#)
        #expect(Self.filter([Self.clause("field.status", .isNot, [FilterClause.groupValue(.completed), FilterClause.groupValue(.canceled)])]).filter
            == #"status_group neq "canceled" AND status_group neq "completed""#)
        // A word and a group in one chip are both ways to be the status.
        #expect(Self.filter([Self.clause("field.status", .is, ["todo", FilterClause.groupValue(.inProgress)])]).filter
            == #"status_group eq "in_progress" OR properties.status eq "todo""#)
        let back = try Self.read(#"status_group eq "in_progress""#)
        #expect(back.items.map(\.clause) == [Self.clause("field.status", .is, [FilterClause.groupValue(.inProgress)])])
        #expect(Self.filter([Self.clause("field.status", .is, ["done", ""])]).filter == #"properties.status not_exists OR properties.status eq "done""#)
    }

    @Test func aDateComesBackAsTheChipThatWroteIt() throws {
        for original in [
            Self.clause("field.due_at", .before, ["2026-06-15"]),
            Self.clause("field.due_at", .after, ["2026-03-28"]),
            Self.clause("field.due_at", .on, ["2026-03-29"]),
            Self.clause("field.due_at", .on, ["2026-10-25"]),
            Self.clause("field.due_at", .between, ["2026-03-28", "2026-03-30"]),
            Self.clause("created", .before, ["2026-11-30"]),
        ] {
            let saved = try #require(Self.filter([original]).filter)
            #expect(try Self.read(saved).items.map(\.clause) == [original], "\(original) did not come back: \(saved)")
        }
        // A bound that is not the start of the person's day is not a day, so the row cannot show it.
        #expect(try Self.read(#"properties.due_at lt "2026-06-15T10:00:00Z""#).items.isEmpty)
        #expect(try Self.read(#"properties.due_at gt "2026-06-15T00:00:00Z""#).items.isEmpty)
    }

    @Test func aDayAfterAndADayBeforeAreOneRangeOnceSaved() throws {
        let saved = try #require(Self.filter([Self.clause("field.due_at", .after, ["2026-11-01"]), Self.clause("field.due_at", .before, ["2026-11-10"])]).filter)
        #expect(try Self.read(saved).items.map(\.clause) == [Self.clause("field.due_at", .between, ["2026-11-02", "2026-11-09"])])
    }

    // MARK: The "is not" rewrite

    @Test func severalWordsOfAClosedFieldBesideAnotherChipAreSavedAsNotTheOthers() throws {
        // Status is Doing, To Do, and Priority is High: (A or B) and C, which Marfa cannot hold, so the status says what it
        // leaves out.
        let both = Self.filter([Self.clause("field.status", .is, ["doing", "todo"]), Self.clause("field.priority", .is, ["high"])])
        #expect(both.filter == #"properties.status neq "done" AND properties.status neq "dropped" AND properties.priority eq "high""#)
        #expect(both.unkept.isEmpty)
        // Alone it is the OR of its words.
        #expect(Self.filter([Self.clause("field.status", .is, ["doing", "todo"])]).filter
            == #"properties.status eq "doing" OR properties.status eq "todo""#)
        // Groups say the same by group.
        let groups = Self.filter([
            Self.clause("field.status", .is, [FilterClause.groupValue(.inProgress), FilterClause.groupValue(.notStarted)]),
            Self.clause("field.priority", .is, ["high"]),
        ])
        #expect(groups.filter == #"status_group neq "canceled" AND status_group neq "completed" AND properties.priority eq "high""#)
        // A choice and a yes or no do too.
        #expect(Self.filter([Self.clause("field.priority", .is, ["low", "high"]), Self.clause("field.status", .is, ["done"])]).unkept == [.mixedFilters],
                "every option chosen leaves nothing to be not")
    }

    @Test func theRewriteIsOnlyForClosedFieldsWithAWordLeftToExclude() {
        // Tags are not a closed set.
        let tags = Self.filter([Self.clause("tags", .includes, ["a", "b"]), Self.clause("field.status", .is, ["done"])])
        #expect(tags.filter == nil)
        #expect(tags.unkept == [.mixedFilters])
        // "No value" cannot be said as is not.
        let empty = Self.filter([Self.clause("field.status", .is, ["done", ""]), Self.clause("field.priority", .is, ["high"])])
        #expect(empty.unkept == [.mixedFilters])
        // Every word chosen leaves none to exclude.
        let all = Self.filter([Self.clause("field.status", .is, ["todo", "doing", "done", "dropped"]), Self.clause("field.priority", .is, ["high"])])
        #expect(all.unkept == [.mixedFilters])
        // A chip of one value is not a rewrite.
        #expect(Self.filter([Self.clause("field.status", .is, ["done"]), Self.clause("field.priority", .is, ["high"])]).filter
            == #"properties.status eq "done" AND properties.priority eq "high""#)
        // The rewrite comes back as the chip it is.
        let saved = Self.filter([Self.clause("field.status", .is, ["doing", "todo"]), Self.clause("field.priority", .is, ["high"])]).filter
        #expect((try? Self.read(saved ?? "").items.map(\.clause)) == [
            Self.clause("field.status", .isNot, ["done", "dropped"]), Self.clause("field.priority", .is, ["high"]),
        ])
    }

    // MARK: All and Any

    @Test func anyJoinsEveryConditionByOrAndAllByAnd() throws {
        let clauses = [Self.clause("field.status", .is, ["done"]), Self.clause("field.priority", .is, ["high"])]
        #expect(Self.filter(clauses).filter == #"properties.status eq "done" AND properties.priority eq "high""#)
        let any = Self.filter(clauses, any: true)
        #expect(any.filter == #"properties.status eq "done" OR properties.priority eq "high""#)
        #expect(any.unkept.isEmpty)
        // A chip of several values is already an OR, so Any keeps it.
        #expect(Self.filter([Self.clause("field.status", .is, ["doing", "todo"]), Self.clause("tags", .includes, ["a"])], any: true).filter
            == #"properties.status eq "doing" OR properties.status eq "todo" OR tags contains "a""#)
        // It reads back as a row that matches any, with the values of one field as one chip.
        let reading = try Self.read(try #require(any.filter))
        #expect(reading.matchesAny)
        #expect(reading.items.map(\.clause) == clauses)
        let merged = try Self.read(#"properties.status eq "a" OR properties.status eq "b" OR tags contains "x""#)
        #expect(merged.items.map(\.clause) == [Self.clause("field.status", .is, ["a", "b"]), Self.clause("tags", .includes, ["x"])])
    }

    @Test func anyNamesWhatItCannotHold() {
        // Several values left out are joined by AND inside, which an OR row cannot hold.
        let negated = Self.filter([Self.clause("field.status", .isNot, ["done", "dropped"]), Self.clause("field.priority", .is, ["high"])], any: true)
        #expect(negated.filter == nil)
        #expect(negated.unkept == [.mixedFilters])
        // A day's two bounds are an AND as well.
        let day = Self.filter([Self.clause("field.due_at", .on, ["2026-11-30"]), Self.clause("field.priority", .is, ["high"])], any: true)
        #expect(day.unkept == [.mixedFilters])
        // A single value left out is no AND.
        #expect(Self.filter([Self.clause("field.status", .isNot, ["done"]), Self.clause("field.priority", .is, ["high"])], any: true).unkept.isEmpty)
        // The view's or the place's own conditions cannot sit beside an OR row.
        let beside = Self.filter(
            [Self.clause("field.status", .is, ["done"]), Self.clause("field.priority", .is, ["high"])], any: true, base: #"type eq "core.task""#)
        #expect(beside.unkept == [.mixedFilters])
        // One clause is no Any.
        #expect(Self.filter([Self.clause("field.status", .is, ["done"])], any: true).unkept.isEmpty)
        // A saved filter that mixes AND and OR is one the core refuses, so none of it is a chip.
        #expect(throws: (any Error).self) { try Self.read(#"properties.status eq "a" AND properties.done eq true OR tags contains "x""#) }
    }

    @Test func anOrFilterIsShownOnlyWhereEveryConditionIs() throws {
        #expect(try Self.read(#"id eq "x" OR properties.status eq "a""#).items.isEmpty)
        #expect(try Self.read(#"id eq "x" AND properties.status eq "a""#).items.map(\.clause) == [Self.clause("field.status", .is, ["a"])])
    }

    // MARK: Dates relative to the day

    @Test func aRelativeDateIsNeverSavedAndIsNamedAsNotKept() throws {
        let relative = Self.clause("field.due_at", .inLast, ["7"])
        #expect(relative.isRelative)
        let state = FilterState(clauses: [Self.clause("field.priority", .is, ["high"]), relative])
        #expect(state.savable.clauses == [Self.clause("field.priority", .is, ["high"])])
        #expect(state.relative == [relative])
        let combined = Self.filter(state.clauses)
        #expect(combined.filter == #"properties.priority eq "high""#, "the relative date is left out of the filter")
        // A new view of the window lists it, as the row reads it.
        var window = ViewDraft.Window(place: .allItems, columns: Self.columns, sort: [], grouping: nil, filter: state, targets: Self.targets)
        window.layout = .table
        let draft = try #require(ViewDraft.draft(window, catalogue: Self.catalogue, views: []))
        #expect(draft.unkept == [.relativeFilter("Due is in the last 7 days")])
        #expect(draft.query.filter == #"properties.priority eq "high""#)
        for (op, values, words) in [
            (FilterOp.beforeToday, [String](), "Due is before today"), (.afterToday, [], "Due is after today"),
            (.inLast, ["1"], "Due is in the last 1 day"), (.inNext, ["30"], "Due is in the next 30 days"),
        ] {
            let sentence = FilterWording.sentence(of: Self.clause("field.due_at", op, values), target: Self.targets["field.due_at"]!, calendar: Self.london())
            #expect(sentence == words)
        }
        // A clause relative to the day with no count says too little to filter by.
        #expect(!Self.clause("field.due_at", .inLast, []).isComplete)
        #expect(!Self.clause("field.due_at", .inLast, ["0"]).isComplete)
        #expect(Self.clause("field.due_at", .beforeToday).isComplete)
    }

    @Test func aSavedViewNamesTheRelativeDateButWritesNothingForIt() {
        let view = LibraryView(id: ItemID("v"), title: "V", version: 2, query: LibraryViewQuery(types: [Self.task]))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        var options = seed
        options.filter = FilterState(clauses: [Self.clause("field.due_at", .inLast, ["7"])])
        var window = ViewDraft.Window(place: .view(view.id), columns: Self.columns, sort: [], grouping: nil, filter: options.filter, targets: Self.targets)
        window.layout = .table
        let update = ViewDraft.change(
            window, options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(update.change.query == nil)
        #expect(update.unkept == [.relativeFilter("Due is in the last 7 days")])
        // The window differs from the view while it holds the relative date, as it does for a search.
        #expect(ViewDraft.differs(options, timelineDate: nil, from: seed, seedTimelineDate: nil))
    }

    // MARK: How many conditions a view holds

    @Test func everyValueOfEveryChipAndEveryBoundOfBetweenCounts() {
        func count(_ clauses: [FilterClause]) -> Int {
            ViewDraft.holdability(of: FilterState(clauses: clauses), targets: Self.targets, catalogue: Self.catalogue, calendar: Self.london()).count
        }
        #expect(count([Self.clause("field.priority", .is, ["high"])]) == 1)
        #expect(count([Self.clause("field.assignees", .includes, ["a", "b", "c"])]) == 3)
        #expect(count([Self.clause("field.due_at", .between, ["2026-11-01", "2026-11-05"])]) == 2)
        #expect(count([Self.clause("field.due_at", .on, ["2026-11-01"])]) == 2)
        #expect(count([
            Self.clause("field.assignees", .includes, ["a", "b", "c"]), Self.clause("field.due_at", .between, ["2026-11-01", "2026-11-05"]),
            Self.clause("field.priority", .is, ["high"]),
        ]) == 6)
        // A relative date is not a condition of a view.
        #expect(count([Self.clause("field.due_at", .inLast, ["7"])]) == 0)
    }

    @Test func moreThanTenConditionsAreNamedAndNothingIsWritten() {
        let ten = Self.filter([Self.clause("field.assignees", .includes, (1...10).map { "p\($0)" })])
        #expect(ten.unkept.isEmpty)
        #expect(ten.count == 10)
        let eleven = Self.filter([Self.clause("field.assignees", .includes, (1...11).map { "p\($0)" })])
        #expect(eleven.filter == nil)
        #expect(eleven.unkept == [.tooManyFilters])
        #expect(eleven.count == 11)
        // The bounds of a between count too: five dates of two bounds are ten, six are twelve.
        let dates = (1...6).map { Self.clause("field.due_at", .between, ["2026-11-0\($0)", "2026-11-0\($0)"]) }
        #expect(Self.filter(Array(dates.prefix(5))).unkept.isEmpty)
        #expect(Self.filter(dates).unkept == [.tooManyFilters])
        // The view's own conditions count.
        let held = (1...9).map { #"tags contains "t\#($0)""# }.joined(separator: " AND ")
        #expect(Self.filter([Self.clause("field.priority", .is, ["high"])], base: held).unkept.isEmpty)
        #expect(Self.filter([Self.clause("field.priority", .is, ["high"]), Self.clause("field.status", .is, ["done"])], base: held).unkept == [.tooManyFilters])
    }

    @Test func aRowThatCannotBeSavedSaysSoAtOnce() {
        func held(_ clauses: [FilterClause], any: Bool = false) -> [ViewDraft.Unkept] {
            ViewDraft.holdability(of: FilterState(clauses: clauses, matchesAny: any), targets: Self.targets, catalogue: Self.catalogue).unkept
        }
        #expect(held([Self.clause("tags", .includes, ["a", "b"]), Self.clause("field.status", .is, ["done"])]) == [.mixedFilters])
        #expect(held([Self.clause("field.status", .isNot, ["done", "dropped"]), Self.clause("field.priority", .is, ["high"])], any: true) == [.mixedFilters])
        #expect(held([Self.clause("field.status", .is, ["doing", "todo"]), Self.clause("field.priority", .is, ["high"])]).isEmpty)
        #expect(held([Self.clause("created", .isSet)]) == [.filter(column: "Created")])
    }

    // MARK: A saved view's own conditions

    @Test func aConditionTheRowCannotShowIsLockedAndTheRestIsShown() throws {
        let query = LibraryViewQuery(types: [Self.task], filter: #"id eq "x" AND properties.owner eq "ann" AND properties.status eq "todo" AND state eq "active""#)
        let locked = ViewDraft.unshownConditions(of: query, catalogue: Self.catalogue)
        #expect(locked == [#"id eq "x""#, #"properties.owner eq "ann""#, #"state eq "active""#])
        let view = LibraryView(id: ItemID("v"), title: "V", query: query)
        #expect(ViewDraft.options(for: view, catalogue: Self.catalogue).filter.clauses == [Self.clause("field.status", .is, ["todo"])])
        // A write replaces the chip and keeps the locked conditions.
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        let result = ViewDraft.replacing(
            query, with: FilterState(clauses: [Self.clause("field.status", .is, ["done"])]), targets: Self.targets, seededTypes: nil, catalogue: Self.catalogue)
        #expect(result.query.filter == #"id eq "x" AND properties.owner eq "ann" AND state eq "active" AND properties.status eq "done""#)
        #expect(seed.filter.clauses.count == 1)
    }

    // MARK: What a clause keeps in the window

    private static func item(
        _ title: String, status: String? = nil, priority: String? = nil, due: String? = nil, estimate: Double? = nil, notes: String? = nil,
        people: [String]? = nil, tags: Set<String> = [], created: Date = .distantPast, parent: String? = nil, collections: [String] = [],
        source: String? = nil
    ) -> ItemTableRow {
        var properties: [Property] = [Property(key: "title", value: .string(title))]
        if let status { properties.append(Property(key: "status", value: .string(status))) }
        if let priority { properties.append(Property(key: "priority", value: .string(priority))) }
        if let due { properties.append(Property(key: "due_at", value: .string(due))) }
        if let estimate { properties.append(Property(key: "estimate", value: .number(Decimal(estimate)))) }
        if let notes { properties.append(Property(key: "notes", value: .string(notes))) }
        if let people {
            properties.append(Property(key: "assignees", value: .array(people.map { .object(["name": .string($0)]) })))
        }
        var item = Item(
            id: ItemID(title), type: task, title: title, titleRule: .property("title"), properties: properties, tags: tags,
            version: ItemVersion(1), created: created, modified: created)
        item.source = source
        func link(_ id: String) -> RelatedItem { .init(id: ItemID(id), title: id, icon: "folder") }
        return ItemTableRow(
            item: item, typeLabel: "Task", typeIcon: nil, parent: parent.map(link), collections: collections.map(link))
    }

    private static func titles(_ rows: [ItemTableRow], _ state: FilterState, now: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> [String] {
        FilterMatching.filter(
            rows, by: state, targets: targets, catalogue: catalogue, clock: .init(now: now, calendar: london())).map(\.item.title)
    }

    @Test func wordsGroupsAndTheEmptyCellKeepTheRowsTheyNameAndIsNotLeavesTheRestOut() {
        let rows = [Self.item("A", status: "todo"), Self.item("B", status: "doing"), Self.item("C", status: "done"), Self.item("D"), Self.item("E", status: "odd")]
        func titles(_ op: FilterOp, _ values: [String]) -> [String] { Self.titles(rows, FilterState(clauses: [Self.clause("field.status", op, values)])) }
        #expect(titles(.is, ["todo"]) == ["A"])
        #expect(titles(.is, ["todo", ""]) == ["A", "D"])
        #expect(titles(.is, [FilterClause.groupValue(.inProgress)]) == ["B"])
        #expect(titles(.is, [FilterClause.groupValue(.inProgress), "todo"]) == ["A", "B"])
        // Marfa's `neq` is false where the property is absent, so the empty cell goes with the rest.
        #expect(titles(.isNot, ["todo"]) == ["B", "C", "E"])
        #expect(titles(.isNot, [""]) == ["A", "B", "C", "E"])
        // A group left out keeps only rows whose own type puts their word in another group.
        #expect(titles(.isNot, [FilterClause.groupValue(.completed)]) == ["A", "B"])
        #expect(titles(.isSet, []) == ["A", "B", "C", "E"])
        #expect(titles(.isEmpty, []) == ["D"])
    }

    @Test func theRewriteSelectsTheSameRowsAsTheChipItReplaces() {
        let rows = [Self.item("A", status: "todo", priority: "high"), Self.item("B", status: "doing", priority: "high"), Self.item("C", status: "done", priority: "high"),
                    Self.item("D", status: "dropped", priority: "high"), Self.item("E", status: "todo", priority: "low")]
        let chip = FilterState(clauses: [Self.clause("field.status", .is, ["doing", "todo"]), Self.clause("field.priority", .is, ["high"])])
        let saved = FilterState(clauses: [Self.clause("field.status", .isNot, ["done", "dropped"]), Self.clause("field.priority", .is, ["high"])])
        #expect(Self.titles(rows, chip) == ["A", "B"])
        #expect(Self.titles(rows, saved) == Self.titles(rows, chip))
    }

    @Test func datesKeepTheDaysTheyNameOnThePersonsClockAcrossAChangeOfClocks() {
        let rows = [
            Self.item("Before", due: "2026-03-28"), Self.item("Spring", due: "2026-03-29"), Self.item("After", due: "2026-03-30"),
            Self.item("Late", due: "2026-03-29T23:30:00Z"), Self.item("Autumn", due: "2026-10-25"), Self.item("Never"),
        ]
        func titles(_ op: FilterOp, _ values: [String]) -> [String] { Self.titles(rows, FilterState(clauses: [Self.clause("field.due_at", op, values)])) }
        #expect(titles(.on, ["2026-03-29"]) == ["Spring"], "a 23-hour day is one day; 23:30 UTC is already 00:30 on the 30th")
        #expect(titles(.before, ["2026-03-29"]) == ["Before"])
        #expect(titles(.after, ["2026-03-29"]) == ["After", "Late", "Autumn"])
        #expect(titles(.between, ["2026-03-29", "2026-03-30"]) == ["Spring", "After", "Late"])
        #expect(titles(.isSet, []) == ["Before", "Spring", "After", "Late", "Autumn"])
        #expect(titles(.isEmpty, []) == ["Never"])
        #expect(titles(.on, ["2026-10-25"]) == ["Autumn"])
    }

    @Test func relativeDatesAreWorkedOutFromTheDayTheyAreAskedOn() {
        // 30 March 2026, noon in London, just after the clocks went forward.
        let now = Self.london().date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 12))!
        let rows = [
            Self.item("Old", due: "2026-03-20"), Self.item("Sunday", due: "2026-03-29"), Self.item("Today", due: "2026-03-30"),
            Self.item("Tomorrow", due: "2026-03-31"), Self.item("Later", due: "2026-04-12"),
        ]
        func titles(_ op: FilterOp, _ values: [String] = []) -> [String] {
            Self.titles(rows, FilterState(clauses: [Self.clause("field.due_at", op, values)]), now: now)
        }
        #expect(titles(.beforeToday) == ["Old", "Sunday"])
        #expect(titles(.afterToday) == ["Tomorrow", "Later"])
        #expect(titles(.inLast, ["1"]) == ["Today"], "the last day is today")
        #expect(titles(.inLast, ["2"]) == ["Sunday", "Today"], "the last two days are across the 23-hour day")
        #expect(titles(.inNext, ["2"]) == ["Today", "Tomorrow"])
        #expect(titles(.inNext, ["30"]) == ["Today", "Tomorrow", "Later"])
        // Tomorrow it is another day.
        let next = Self.london().date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 9))!
        #expect(Self.titles(rows, FilterState(clauses: [Self.clause("field.due_at", .inLast, ["1"])]), now: next) == ["Tomorrow"])
    }

    @Test func numbersTextPeopleTagsAndLinksKeepTheRowsTheyNameInTheWindow() {
        let rows = [
            Self.item("A", estimate: 3, notes: "Café menu", people: ["Rui Alves"], tags: ["kitchen"], parent: "P", collections: ["C1"], source: "mail"),
            Self.item("B", estimate: 8, notes: "CAFE rota", people: ["Mira Castell", "Rui Alves"], tags: ["garden"], parent: "Q", collections: ["C1", "C2"]),
            Self.item("C", notes: "plain"),
        ]
        func titles(_ field: String, _ op: FilterOp, _ values: [String] = []) -> [String] {
            Self.titles(rows, FilterState(clauses: [Self.clause(field, op, values)]))
        }
        #expect(titles("field.estimate", .greater, ["3"]) == ["B"])
        #expect(titles("field.estimate", .lessOrEqual, ["3"]) == ["A"])
        #expect(titles("field.estimate", .equal, ["8"]) == ["B"])
        #expect(titles("field.estimate", .notEqual, ["8"]) == ["A"], "an empty estimate is not unequal")
        #expect(titles("field.estimate", .isEmpty) == ["C"])
        #expect(titles("field.notes", .contains, ["cafe"]) == ["B"], "only the letters A to Z are folded")
        #expect(titles("field.notes", .contains, ["CAF"]) == ["A", "B"])
        #expect(titles("field.notes", .startsWith, ["plain"]) == ["C"])
        #expect(titles("field.notes", .is, ["plain"]) == ["C"])
        #expect(titles("field.notes", .isNot, ["plain"]) == ["A", "B"])
        #expect(titles("field.assignees", .includes, ["Rui Alves"]) == ["A", "B"])
        #expect(titles("field.assignees", .includes, ["Mira Castell"]) == ["B"])
        #expect(titles("field.assignees", .isEmpty) == ["C"])
        #expect(titles("tags", .includes, ["kitchen", "garden"]) == ["A", "B"])
        #expect(titles("tags", .isEmpty) == ["C"])
        #expect(titles("parent", .is, ["P"]) == ["A"])
        #expect(titles("parent", .isNot, ["P"]) == ["B", "C"], "a row with no parent is not that parent")
        #expect(titles("collections", .is, ["C2"]) == ["B"])
        #expect(titles("collections", .isNot, ["C1"]) == ["C"])
        #expect(titles("collections", .isSet) == ["A", "B"])
        #expect(titles("source", .is, ["mail"]) == ["A"])
    }

    @Test func allNeedsEveryClauseAndAnyOne() {
        let rows = [Self.item("A", status: "todo", priority: "high"), Self.item("B", status: "todo", priority: "low"), Self.item("C", status: "done", priority: "high"),
                    Self.item("D", status: "done", priority: "low")]
        let clauses = [Self.clause("field.status", .is, ["todo"]), Self.clause("field.priority", .is, ["high"])]
        #expect(Self.titles(rows, FilterState(clauses: clauses)) == ["A"])
        #expect(Self.titles(rows, FilterState(clauses: clauses, matchesAny: true)) == ["A", "B", "C"])
        // A clause that says too little filters nothing, and does not make Any of one.
        let waiting = [Self.clause("field.status", .is, ["todo"]), Self.clause("field.priority", .is)]
        #expect(Self.titles(rows, FilterState(clauses: waiting, matchesAny: true)) == ["A", "B"])
        // A clause whose field no type declares any more keeps every row.
        #expect(Self.titles(rows, FilterState(clauses: [Self.clause("field.gone", .is, ["x"])])).count == 4)
    }

    // MARK: Kept in a place's default view

    @Test func aPlaceKeepsItsClausesIncludingARelativeDateAndDropsAFieldNoTypeDeclares() throws {
        var options = ItemTableOptions()
        options.filter = FilterState(
            clauses: [
                Self.clause("field.due_at", .inLast, ["7"]), Self.clause("field.gone", .is, ["x"]), Self.clause("field.priority", .is, ["high"]),
                Self.clause("field.notes", .contains, [#"say "hi" \ x"#]),
            ], matchesAny: true)
        var stored = PlaceDefault()
        stored.keep(options)
        // It is kept as the encoder writes it and read back the same.
        let data = try JSONEncoder().encode(stored)
        let back = try JSONDecoder().decode(PlaceDefault.self, from: data)
        #expect(back == stored)
        let opened = back.options(replacing: nil, in: .itemType("core.task"), catalogue: Self.catalogue)
        #expect(opened.filter.clauses.map(\.field) == ["field.due_at", "field.priority", "field.notes"])
        #expect(opened.filter.matchesAny)
        #expect(opened.filter.relative.count == 1)
    }

    @Test func aClauseThatSaysTooLittleIsNotKept() {
        var options = ItemTableOptions()
        options.filter = FilterState(clauses: [Self.clause("field.due_at", .inLast), Self.clause("field.priority", .is, ["high"])])
        var stored = PlaceDefault()
        stored.keep(options)
        #expect(stored.filter == [Self.clause("field.priority", .is, ["high"])])
    }

    // MARK: Changing the row

    @Test func aNewFilterStartsWithItsOperatorAndIsDroppedIfLeftWithoutAValue() {
        let browser = Browser()
        let index = browser.addFilter(on: Self.targets["field.due_at"]!)
        let held = { browser.tableOptions[browser.item]?.filter ?? FilterState() }
        #expect(held().clauses == [Self.clause("field.due_at", .before)])
        #expect(browser.showsFilterRow)
        #expect(browser.tableOptions[browser.item]?.isFiltering == false, "it hides nothing until it has a day")
        browser.changeFilter(at: index) { $0.values = ["2026-01-01"] }
        #expect(browser.tableOptions[browser.item]?.isFiltering == true)
        browser.addFilter(on: Self.targets["field.priority"]!)
        browser.dropUnfinishedFilters()
        #expect(held().clauses == [Self.clause("field.due_at", .before, ["2026-01-01"])])
        // A second condition on a field already filtered is another chip.
        browser.addFilter(on: Self.targets["field.due_at"]!)
        #expect(held().clauses.count == 2)
    }

    @Test func anotherOperatorKeepsTheValueWhereItAsksForTheSameKindAndStartsAgainWhereItDoesNot() {
        let browser = Browser()
        let kind = FilterKind.date
        let index = browser.addFilter(on: Self.targets["field.due_at"]!)
        browser.changeFilter(at: index) { $0.values = ["2026-01-01"] }
        func clause() -> FilterClause { browser.tableOptions[browser.item]!.filter.clauses[index] }
        browser.setFilterOperator(at: index, to: .after, kind: kind)
        #expect(clause() == Self.clause("field.due_at", .after, ["2026-01-01"]))
        browser.setFilterOperator(at: index, to: .between, kind: kind)
        #expect(clause() == Self.clause("field.due_at", .between, ["2026-01-01"]), "the day stays as the first bound, which needs a second")
        #expect(!clause().isComplete)
        browser.setFilterOperator(at: index, to: .inLast, kind: kind)
        #expect(clause() == Self.clause("field.due_at", .inLast, ["7"]))
        browser.setFilterOperator(at: index, to: .isSet, kind: kind)
        #expect(clause() == Self.clause("field.due_at", .isSet))
        #expect(clause().isComplete)

        let word = browser.addFilter(on: Self.targets["field.status"]!)
        browser.changeFilter(at: word) { $0.values = ["done"] }
        browser.setFilterOperator(at: word, to: .isNot, kind: .status)
        #expect(browser.tableOptions[browser.item]!.filter.clauses[word] == Self.clause("field.status", .isNot, ["done"]))

        let text = browser.addFilter(on: Self.targets["field.notes"]!)
        browser.changeFilter(at: text) { $0.values = ["x"] }
        browser.setFilterOperator(at: text, to: .isNot, kind: .text)
        #expect(browser.tableOptions[browser.item]!.filter.clauses[text] == Self.clause("field.notes", .isNot, ["x"]), "a text is one text under every operator")
    }

    @Test func theRowIsAllAgainOnceItHoldsOneFilter() {
        let browser = Browser()
        browser.addFilter(on: Self.targets["field.priority"]!)
        browser.addFilter(on: Self.targets["field.status"]!)
        browser.setFiltersMatchAny(true)
        #expect(browser.tableOptions[browser.item]?.filter.matchesAny == true)
        browser.removeFilter(at: 1)
        #expect(browser.tableOptions[browser.item]?.filter.matchesAny == false)
    }

    @Test func aRelativeDateStaysTheMacsAndAChangeOfDayMakesTheTableAgain() {
        let browser = Browser()
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("A", modified: .now)], now: Date(timeIntervalSince1970: 1_790_000_000))
        browser.tableOptions[.allItems] = ItemTableOptions(filter: FilterState(clauses: [Self.clause("edited", .inLast, ["7"])]))
        let first = browser.tableContent(in: library)
        #expect(browser.tableContent(in: library) === first)
        library.now = { Date(timeIntervalSince1970: 1_790_000_000 + 86_400 * 2) }
        #expect(browser.tableContent(in: library) !== first)
    }
}
