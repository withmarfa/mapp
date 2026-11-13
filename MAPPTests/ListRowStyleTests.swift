import Foundation
import Testing
@testable import MAPP

struct ListRowStyleTests {
    private func info(_ id: String, parent: String? = nil, fields: [ItemTypeInfo.Field] = []) -> ItemTypeInfo {
        ItemTypeInfo(id: TypeID(id), label: id, fields: fields, titleField: nil, bodyField: nil, parent: parent.map { TypeID($0) })
    }

    private func status(_ owner: String) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(
            key: "state", label: "State", kind: .status([StatusWord(value: "open", group: .notStarted)]), declaredBy: TypeID(owner))
    }

    private var catalogue: Catalogue {
        Catalogue(itemTypes: [
            info("core.note"), info("core.highlight"), info("core.entity"), info("core.entity.person", parent: "core.entity"),
            info("acme.contact", parent: "core.entity.person"), info("core.file"), info("core.file.image", parent: "core.file"),
            info("core.task", fields: [status("core.task")]), info("acme.ticket", fields: [status("acme.ticket")]),
        ])
    }

    @Test func theViewsChoiceWinsOverEverythingBelowIt() {
        #expect(ListRowStyle.resolve(view: .compact, fields: .person, rowStyle: .withPictures) == .compact)
    }

    @Test func theFieldsWinOverTheRowStyle() {
        #expect(ListRowStyle.resolve(fields: .person, rowStyle: .compact) == .person)
    }

    @Test func rowStyleIsTheLastResortAndNamesOnlyAStyleForEveryList() {
        #expect(ListRowStyle.resolve(rowStyle: .compact) == .compact)
        #expect(ListRowStyle.resolve(rowStyle: .task) == .standard)
    }

    @Test func aTypeStartsFromItsFields() {
        #expect(ListRowStyle.fromFields(of: TypeID("core.task"), in: catalogue) == .task)
        #expect(ListRowStyle.fromFields(of: TypeID("acme.ticket"), in: catalogue) == .task)
        #expect(ListRowStyle.fromFields(of: TypeID("core.highlight"), in: catalogue) == .highlight)
        #expect(ListRowStyle.fromFields(of: TypeID("acme.contact"), in: catalogue) == .person)
        #expect(ListRowStyle.fromFields(of: TypeID("core.file.image"), in: catalogue) == .withPictures)
        #expect(ListRowStyle.fromFields(of: TypeID("core.note"), in: catalogue) == nil)
        #expect(ListRowStyle.fromFields(of: TypeID("unknown.type"), in: catalogue) == nil)
    }

    @Test func aListResolvesEachTypeOnceAndAViewsChoiceTakesAllOfThem() {
        let types = [TypeID("core.note"), TypeID("core.task"), TypeID("core.file.image")]
        let own = ListRowStyle.styles(of: types, rowStyle: .compact, in: catalogue)
        #expect(own == [TypeID("core.note"): .compact, TypeID("core.task"): .task, TypeID("core.file.image"): .withPictures])
        let chosen = ListRowStyle.styles(of: types, view: .standard, rowStyle: .compact, in: catalogue)
        #expect(Set(chosen.values) == [.standard])
    }

    @Test func theListSettingsAreAllResetTogether() {
        #expect(Set(ListKey.all) == [
            ListKey.previewLines, ListKey.showsPictures, ListKey.rowStyle, ListKey.showsTypeWhenMixed,
        ])
    }

    private func priority(_ options: [String], declaredBy owner: String = "core.task") -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(options), declaredBy: TypeID(owner))
    }

    @Test func aPriorityTakesItsColorFromItsRankNotItsWord() {
        let four = priority(["low", "medium", "high", "urgent"])
        #expect(["low", "medium", "high", "urgent"].map { OptionTone.tone(of: $0, in: four, isPriority: true) } == [.purple, .yellow, .red, .blue])
        let words = priority(["minor", "normal", "major", "blocker"])
        #expect(["minor", "normal", "major", "blocker"].map { OptionTone.tone(of: $0, in: words, isPriority: true) } == [.purple, .yellow, .red, .blue])
        #expect(OptionTone.tone(of: "high", in: four, isPriority: false) == OptionTone.tone(for: "High"))
    }

    @Test func otherCountsSpreadOverThePriorityColorsFromLowestToHighest() {
        func tones(_ options: [String]) -> [TypeTone] {
            let field = priority(options)
            return options.map { OptionTone.tone(of: $0, in: field, isPriority: true) }
        }
        #expect(tones(["only"]) == [.purple])
        #expect(tones(["a", "b"]) == [.purple, .blue])
        #expect(tones(["a", "b", "c"]) == [.purple, .red, .blue])
        #expect(tones(["a", "b", "c", "d", "e"]) == [.purple, .yellow, .red, .red, .blue])
    }

    @Test func aPriorityOptionTheFieldDoesNotDeclareTakesTheLabelsColor() {
        let field = priority(["low", "high"])
        #expect(OptionTone.tone(of: "urgent", in: field, isPriority: true) == OptionTone.tone(for: "Urgent"))
    }

    @Test func aPanelsChoiceRowsAndAListRowsPriorityAgree() {
        let field = priority(["low", "medium", "high", "urgent"])
        let rows = ValueEditOptions.choiceRows(field: field, current: "high", isPriority: true)
        #expect(rows.map(\.mark) == [.dot(.purple), .dot(.yellow), .dot(.red), .dot(.blue)])
        let plain = ValueEditOptions.choiceRows(field: field, current: nil, isPriority: false)
        #expect(plain.map(\.mark) == ["Low", "Medium", "High", "Urgent"].map { .dot(OptionTone.tone(for: $0)) })
    }

    @Test func aRowWithNoPictureDrawsTheListsRowStyleNotAlwaysStandard() {
        for fallback in [ListRowStyle.standard, .compact] {
            let types = ListRowType.types(
                of: [TypeID("acme.scan"), TypeID("core.note")], rowStyle: fallback,
                in: Catalogue(itemTypes: [info("core.file"), info("acme.scan", parent: "core.file"), info("core.note")]))
            let scan = types[TypeID("acme.scan")]!
            #expect(scan.style == .withPictures)
            #expect(scan.drawnStyle(hasPicture: true) == .withPictures)
            #expect(scan.drawnStyle(hasPicture: false) == fallback)
            #expect(types[TypeID("core.note")]!.drawnStyle(hasPicture: false) == fallback)
        }
        let tasks = ListRowType(style: .task, pictureless: .compact)
        #expect(tasks.drawnStyle(hasPicture: false) == .task)
    }

    @Test func aFileTypeStartsWithPicturesWithoutNamingAnImageType() {
        let catalogue = Catalogue(itemTypes: [
            info("core.file"), info("core.file.image", parent: "core.file"), info("acme.scan", parent: "core.file"), info("core.note"),
        ])
        #expect(ListRowStyle.fromFields(of: TypeID("acme.scan"), in: catalogue) == .withPictures)
        #expect(ListRowStyle.fromFields(of: TypeID("core.file.image"), in: catalogue) == .withPictures)
        #expect(ListRowStyle.fromFields(of: TypeID("core.note"), in: catalogue) == nil)
    }
}

struct TaskRowFactsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))! }

    private var catalogue: Catalogue {
        let task = TypeID("core.task")
        let fields = [
            ItemTypeInfo.Field(
                key: "status", label: "Status",
                kind: .status([StatusWord(value: "todo", group: .notStarted), StatusWord(value: "done", group: .completed), StatusWord(value: "dropped", group: .canceled)]),
                declaredBy: task),
            ItemTypeInfo.Field(key: "due_at", label: "Due", kind: .date(includesTime: true), declaredBy: task),
            ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(["low", "high"]), declaredBy: task),
        ]
        return Catalogue(itemTypes: [
            ItemTypeInfo(id: task, label: "Task", fields: fields, titleField: "title", bodyField: nil, parent: nil),
            ItemTypeInfo(id: TypeID("core.note"), label: "Note", fields: [], titleField: "title", bodyField: nil, parent: nil),
        ])
    }

    private func task(_ properties: [String: PropertyValue], type: String = "core.task") -> Item {
        Item(
            id: .mint(), type: TypeID(type), title: "T", titleRule: .firstLine,
            properties: properties.map { Property(key: $0.key, value: $0.value) }, version: ItemVersion(1),
            created: now, modified: calendar.date(byAdding: .day, value: -1, to: now)!)
    }

    private func facts(_ item: Item) -> TaskRowFacts {
        TaskRowFacts.make(for: item, type: ListRowType(item.type, style: .task, in: catalogue), now: now, format: .automatic, calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    @Test func dueDatesReadAsWords() {
        #expect(facts(task(["due_at": .string("2026-11-10")])).due == .init(label: "Due today", isPressing: true))
        #expect(facts(task(["due_at": .string("2026-11-08")])).due == .init(label: "2 days late", isPressing: true))
        #expect(facts(task(["due_at": .string("2026-11-09")])).due == .init(label: "1 day late", isPressing: true))
        #expect(facts(task(["due_at": .string("2026-11-11")])).due == .init(label: "Due tomorrow", isPressing: false))
        #expect(facts(task(["due_at": .string("2026-11-12")])).due == .init(label: "Due Thu", isPressing: false))
    }

    @Test func aFinishedTaskShowsWhenItFinishedAndNoDueDate() {
        let done = facts(task(["status": .string("done"), "due_at": .string("2026-11-01"), "completed_at": .string("2026-11-09")]))
        #expect(done.due == nil)
        #expect(done.finish == "Yesterday")
        let dropped = facts(task(["status": .string("dropped"), "completed_at": .string("2026-06-15")]))
        #expect(dropped.finish == "Canceled 15 Jun")
    }

    @Test func aFinishedTaskWithNoFinishTimeNeverShowsItsEditDayAsOne() {
        let done = facts(task(["status": .string("done")]))
        #expect(done.finish == nil)
        #expect(done.due == nil)
        #expect(facts(task(["status": .string("dropped")])).finish == "Canceled")
    }

    @Test func aRowHasOnlyWhatTheItemHolds() {
        let bare = facts(task([:]))
        #expect(!bare.hasLine)
        #expect(bare.statusGroup == nil)
        let full = facts(task([
            "status": .string("todo"), "priority": .string("high"),
            "assignees": .array([.object(["name": .string("Rachel Kim")]), .object(["email": .string("a@b.c")])]),
            "recurrence": .array([.string("RRULE:FREQ=YEARLY")]),
        ]))
        #expect(full.statusGroup == .notStarted)
        #expect(full.priority == "high")
        #expect(full.priorityTone == .blue)
        #expect(full.people == .init(initials: "RK", label: "2 people"))
        #expect(full.repeats == "Yearly")
    }

    @Test func oneAssigneeIsNamedAndRepeatsKeepTheirInterval() {
        let one = facts(task(["assignees": .array([.object(["name": .string("mcastell")])])]))
        #expect(one.people == .init(initials: "M", label: "mcastell"))
        #expect(TaskRowFacts.repeatWords(.array([.string("RRULE:FREQ=WEEKLY;INTERVAL=2")])) == "Every 2 weeks")
        #expect(TaskRowFacts.repeatWords(.array([.string("RDATE:20261201T000000Z")])) == "Repeats")
        #expect(TaskRowFacts.repeatWords(.array([])) == nil)
    }

    @Test func onlyATaskHasADueDateAndAPriority() {
        let other = facts(task(["due_at": .string("2026-11-10"), "priority": .string("high")], type: "core.note"))
        #expect(other.due == nil)
        #expect(other.priority == nil)
    }
}
