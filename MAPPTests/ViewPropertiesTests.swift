import Foundation
import Testing
@testable import MAPP

/// The Properties list of a view or place: As in Layouts until changed, the list's own looks once it is, Use Layouts, the
/// properties a type does not declare skipped for it, and the table's columns in the list's order with the name locked.
struct ViewPropertiesTests {
    private static let catalogue = LookFixture.catalogue()
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func item(_ type: String, _ properties: [String: String] = [:], tags: Set<String> = []) -> Item {
        Item(
            id: .mint(), type: TypeID(type), title: "Title", name: "Title", titleRule: .firstLine,
            properties: properties.sorted { $0.key < $1.key }.map { Property(key: $0.key, value: .string($0.value)) }, tags: tags,
            version: ItemVersion(1), created: now, modified: now)
    }

    private static let taskLook = TypeLook(date: .field("due_at"), secondary: [.field("place")], facts: [.field("priority"), .tags])
    private static let eventLook = TypeLook(date: .field("starts_at"), secondary: [], facts: [.field("place"), .field("url")])
    private static let looks: [TypeID: TypeLook] = [TypeID("core.task"): taskLook, TypeID("core.event"): eventLook]

    private static let rows: [ItemTableRow] = [
        ItemTableRow(
            item: item("core.task", ["status": "todo", "priority": "high", "place": "Home", "due_at": "2026-11-20"], tags: ["work"]),
            typeLabel: "Task", typeIcon: nil, parent: nil),
        ItemTableRow(
            item: item("core.event", ["place": "Room", "url": "https://example.com", "starts_at": "2026-11-20T10:00:00Z", "status": "confirmed"]),
            typeLabel: "Event", typeIcon: nil, parent: nil),
    ]

    private static var columns: [ItemTableColumn] {
        ItemTableLayout.columns(for: rows, catalogue: catalogue, hidden: [], looks: looks)
    }

    private static func column(_ id: String) -> ItemTableColumn { columns.first { $0.id == id }! }

    private static func ids(_ columns: [ItemTableColumn]) -> [String] { columns.map(\.id) }

    private static func resolve(_ properties: ViewProperties) -> [TypeID: TypeLook] {
        properties.looks(looks, columns: columns, catalogue: catalogue)
    }

    // MARK: As in Layouts, and changed

    @Test func anUnchangedListIsTheLooksUntouched() {
        let properties = ViewProperties()
        #expect(!properties.isChanged)
        #expect(Self.resolve(properties) == Self.looks)
    }

    @Test func aChangeMakesTheListTheViewsOwnWithTheFactsInItsOrder() {
        var properties = ViewProperties()
        properties.setShown(Self.column("field.attendees"), true)
        properties.setShown(Self.column("field.priority"), false)
        #expect(properties.isChanged)
        let looks = Self.resolve(properties)
        // The task keeps what the list shows that it declares; the priority is hidden and the event has no priority.
        #expect(looks[TypeID("core.task")]?.facts.contains(.tags) == true)
        #expect(looks[TypeID("core.task")]?.facts.contains(.field("priority")) == false)
        #expect(looks[TypeID("core.event")]?.facts.contains(.field("url")) == true)
        #expect(looks[TypeID("core.event")]?.facts.contains(.field("priority")) == false)
        // A status is the row's first chip, never a fact.
        #expect(looks[TypeID("core.task")]?.facts.contains(.field("status")) == false)
        // The date and the Secondary line stay the type's.
        #expect(looks[TypeID("core.task")]?.date == Self.taskLook.date)
        #expect(looks[TypeID("core.task")]?.secondary == Self.taskLook.secondary)
    }

    @Test func aPropertyATypeDoesNotDeclareIsSkippedForItAndKeptForTheOthers() {
        var properties = ViewProperties()
        properties.setShown(Self.column("field.completed_at"), true)
        properties.move("field.completed_at", before: "field.priority", in: Self.columns)
        let looks = Self.resolve(properties)
        let task = looks[TypeID("core.task")]?.facts ?? []
        #expect(task.firstIndex(of: .field("completed_at"))! < task.firstIndex(of: .field("priority"))!)
        #expect(looks[TypeID("core.event")]?.facts.contains(.field("completed_at")) == false)
    }

    @Test func aFieldTheLookSaysAsItsDateOrOnItsSecondaryLineIsNotRepeated() {
        var properties = ViewProperties()
        // Both are shown by default as the table's date and a task's fact, so the list is the looks' and changes nothing.
        properties.setShown(Self.column("tags"), false)
        let task = Self.resolve(properties)[TypeID("core.task")]
        #expect(task?.facts.contains(.field("due_at")) == false)
        #expect(task?.facts.contains(.field("place")) == false)
        // The event says its place only as a fact, so it keeps it.
        #expect(Self.resolve(properties)[TypeID("core.event")]?.facts.contains(.field("place")) == true)
    }

    @Test func theStatusAndTheTypeShowOrHideAsTheirPropertiesDo() {
        var properties = ViewProperties()
        properties.setShown(Self.column("field.status"), false)
        properties.setShown(Self.column("type"), false)
        let looks = Self.resolve(properties)
        // Only a task has a status field; an event's is a plain choice.
        #expect(looks[TypeID("core.task")]?.showsStatus == false)
        #expect(looks[TypeID("core.event")]?.showsStatus == true)
        for type in ["core.task", "core.event"] { #expect(looks[TypeID(type)]?.showsType == false) }
        var shown = ViewProperties()
        shown.setShown(Self.column("field.priority"), false)
        #expect(Self.resolve(shown)[TypeID("core.task")]?.showsStatus == true)
        #expect(Self.resolve(shown)[TypeID("core.task")]?.showsType == true)
    }

    @Test func useLayoutsPutsTheFallbackBack() {
        var properties = ViewProperties()
        properties.setShown(Self.column("field.priority"), false)
        properties.move("tags", before: "field.priority", in: Self.columns)
        #expect(Self.resolve(properties) != Self.looks)
        properties.reset()
        #expect(!properties.isChanged)
        #expect(Self.resolve(properties) == Self.looks)
    }

    @Test func aStoredPropertyNoTypeDeclaresAnyMoreIsSkippedAndTheRestKept() {
        let properties = ViewProperties(order: ["field.gone", "tags", "field.priority"], shown: ["field.gone": true, "field.priority": false])
        #expect(Self.ids(properties.arranged(Self.columns)).contains("field.gone") == false)
        let looks = Self.resolve(properties)
        // Tags lead, the priority is hidden, and nothing is made of the stored property no type declares.
        #expect(looks[TypeID("core.task")]?.facts.first == .tags)
        #expect(looks[TypeID("core.task")]?.facts.contains(.field("priority")) == false)
        #expect(Self.ids(properties.shownColumns(Self.columns)).contains("tags"))
    }

    // MARK: The table

    @Test func theTableShowsTheShownPropertiesInTheListsOrderWithTheNameFirstAndLocked() {
        var properties = ViewProperties()
        properties.setShown(.title, false)
        properties.move("title", before: "field.priority", in: Self.columns)
        properties.move("field.priority", before: "field.status", in: Self.columns)
        let shown = Self.ids(properties.shownColumns(Self.columns))
        #expect(shown.first == "title")
        #expect(shown.firstIndex(of: "field.priority")! < shown.firstIndex(of: "field.status")!)
    }

    // MARK: What a layout lists

    @Test func aTableListsEveryColumnAndAnotherLayoutOnlyWhatAChipCanSay() {
        let columns = Self.columns
        #expect(ViewProperties.offered(columns, in: .table) == columns)
        let chips = Self.ids(ViewProperties.offered(columns, in: .list))
        #expect(!chips.contains("title"))
        #expect(!chips.contains("edited") && !chips.contains("created") && !chips.contains("occurred"))
        #expect(chips.contains("type") && chips.contains("field.status") && chips.contains("tags") && chips.contains("field.priority"))
    }

    @Test func aBoardOrATimelineLeavesOutWhatItsLanesOrDaysAreMadeOf() {
        let chips = ViewProperties.offered(Self.columns, in: .board, leaving: ["field.priority"])
        #expect(!Self.ids(chips).contains("field.priority"))
        #expect(Self.ids(chips).contains("tags"))
    }

    @Test func aFieldEveryDeclaringTypeSaysAlreadyIsNotListed() {
        // Only a task declares due_at, and its look says it as the date, so no chip could ever show it.
        let listed = Self.ids(ViewProperties.offered(
            Self.columns, in: .list, looks: Self.looks, types: [TypeID("core.task"), TypeID("core.event")], catalogue: Self.catalogue))
        #expect(!listed.contains("field.due_at"))
        // The place is the task's Secondary line but the event's fact, so it stays.
        #expect(listed.contains("field.place"))
    }

    // MARK: Where it is kept

    @Test func aViewKeepsItsPropertiesUnderTheKeyTheColumnsUsed() throws {
        var properties = ViewProperties()
        properties.setShown(Self.column("tags"), false)
        let data = try JSONEncoder().encode(ViewMacSettings(properties: properties))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["columns"] != nil)
        #expect(try JSONDecoder().decode(ViewMacSettings.self, from: data).properties == properties)
    }

    @Test func aPlacesDefaultKeepsItsPropertiesAndIsEmptyWithoutThem() throws {
        var stored = PlaceDefault()
        #expect(stored.isEmpty)
        stored.properties.setShown(Self.column("tags"), false)
        #expect(!stored.isEmpty)
        #expect(stored.isChanged(naturalLayout: .list))
        let again = try JSONDecoder().decode(PlaceDefault.self, from: JSONEncoder().encode(stored))
        #expect(again.properties == stored.properties)
    }

    // MARK: What a row says

    private static func content(
        _ item: Item, look: TypeLook, mixed: Bool, shape: CardShape? = nil
    ) -> RowContent {
        let list = RowList(mixesTypes: mixed, day: calendar.startOfDay(for: now))
        if let shape {
            return RowContent.card(for: item, look: look, catalogue: catalogue, list: list, shape: shape, calendar: calendar, locale: Locale(identifier: "en_GB"))
        }
        return RowContent.make(for: item, look: look, catalogue: catalogue, list: list, calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    private static func kinds(_ content: RowContent) -> [String] {
        content.chips.map {
            switch $0 {
            case .type: "type"
            case .status: "status"
            case .option: "option"
            case .person: "person"
            case .tag: "tag"
            case .linked: "linked"
            case .text: "text"
            case .count: "count"
            }
        }
    }

    @Test func aBoardOfOneTypeShowsNoTypeOnItsCardsAndOneOfSeveralDoes() {
        let task = Self.rows[0].item
        #expect(!Self.kinds(Self.content(task, look: Self.taskLook, mixed: false, shape: CardShape())).contains("type"))
        #expect(Self.kinds(Self.content(task, look: Self.taskLook, mixed: true, shape: CardShape())).contains("type"))
    }

    @Test func aLookWithTheStatusOrTheTypeOffSaysNeither() {
        let task = Self.rows[0].item
        var look = Self.taskLook
        #expect(Self.kinds(Self.content(task, look: look, mixed: true)).prefix(2) == ["type", "status"])
        look.showsStatus = false
        look.showsType = false
        #expect(!Self.kinds(Self.content(task, look: look, mixed: true)).contains("status"))
        #expect(!Self.kinds(Self.content(task, look: look, mixed: true)).contains("type"))
    }

    // MARK: The timeline's row

    @Test func theTimelineRowTakesTheTypeOffTheChipsPutsAPersonLastAndLeadsTheSecondLineWithTheType() {
        var content = RowContent(title: "T", date: nil, secondary: "Kiln House", typeIcon: nil, typeLabel: "Event", mixesTypes: true)
        content.chips = [.type(icon: nil, label: "Event"), .person(initials: "MC", name: "Mira"), .status(.inProgress, label: "In Progress"), .tag("pdf")]
        content.more = 2
        let face = TimelineRowFace(content)
        #expect(Self.kinds(RowContent(title: "", date: nil, secondary: nil, typeIcon: nil, typeLabel: "", mixesTypes: false, chips: face.chips)) == ["status", "tag", "person"])
        #expect(face.more == 2)
        #expect(face.typeName == "Event")
        #expect(face.secondary == "Kiln House")
    }

    @Test func aTimelineRowOfOneTypeNamesNoTypeAndAnEmptySecondLineStillExists() {
        let content = RowContent(title: "T", date: nil, secondary: nil, typeIcon: nil, typeLabel: "Task", mixesTypes: false)
        let face = TimelineRowFace(content)
        #expect(face.typeName == nil)
        #expect(!face.hasSecondLine)
    }
}
