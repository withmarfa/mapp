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
        #expect(ListRowStyle.resolve(view: .compact, type: .task, fields: .person, rowStyle: .withPictures) == .compact)
    }

    @Test func theTypesChoiceWinsOverItsFieldsAndTheRowStyle() {
        #expect(ListRowStyle.resolve(type: .standard, fields: .task, rowStyle: .compact) == .standard)
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
        var choices = ListTypeStyles()
        choices[TypeID("core.note")] = .compact
        let types = [TypeID("core.note"), TypeID("core.task"), TypeID("core.file.image")]
        let own = ListRowStyle.styles(of: types, choices: choices, rowStyle: .standard, in: catalogue)
        #expect(own == [TypeID("core.note"): .compact, TypeID("core.task"): .task, TypeID("core.file.image"): .withPictures])
        let chosen = ListRowStyle.styles(of: types, view: .standard, choices: choices, rowStyle: .compact, in: catalogue)
        #expect(Set(chosen.values) == [.standard])
    }

    @Test func typeChoicesAreKeptAsOneSettingAndASpoiledOneReadsAsNone() throws {
        var choices = ListTypeStyles()
        choices[TypeID("core.task")] = .compact
        let again = try #require(ListTypeStyles(rawValue: choices.rawValue))
        #expect(again[TypeID("core.task")] == .compact)
        #expect(ListTypeStyles(rawValue: "not json")?[TypeID("core.task")] == nil)
        #expect(ListTypeStyles(rawValue: #"{"core.task":"gone"}"#)?[TypeID("core.task")] == nil)
    }

    @Test func theListSettingsAreAllResetTogether() {
        #expect(Set(ListKey.all) == [
            ListKey.previewLines, ListKey.showsPictures, ListKey.rowStyle, ListKey.typeStyles, ListKey.showsTypeWhenMixed,
        ])
    }

    @Test func aPriorityIsColoredAsTheValuePanelColorsIt() {
        #expect(OptionTone.tone(ofOption: "low") == .purple)
        #expect(OptionTone.tone(ofOption: "medium") == .yellow)
        #expect(OptionTone.tone(ofOption: "urgent") == .blue)
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
        TaskRowFacts.make(for: item, catalogue: catalogue, now: now, format: .automatic, calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    @Test func dueDatesReadAsWords() {
        #expect(facts(task(["due_at": .string("2026-11-10")])).due == .init(label: "Due today", isPressing: true))
        #expect(facts(task(["due_at": .string("2026-11-08")])).due == .init(label: "2 days late", isPressing: true))
        #expect(facts(task(["due_at": .string("2026-11-09")])).due == .init(label: "1 day late", isPressing: true))
        #expect(facts(task(["due_at": .string("2026-11-11")])).due == .init(label: "Due tomorrow", isPressing: false))
        #expect(facts(task(["due_at": .string("2026-11-12")])).due == .init(label: "Due Thu", isPressing: false))
    }

    @Test func aFinishedTaskShowsWhenItFinishedAndNoDueDate() {
        let done = facts(task(["status": .string("done"), "due_at": .string("2026-11-01")]))
        #expect(done.due == nil)
        #expect(done.finish == "Yesterday")
        let dropped = facts(task(["status": .string("dropped"), "completed_at": .string("2026-06-15")]))
        #expect(dropped.finish == "Canceled 15 Jun")
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
