import Foundation
import Testing
@testable import MarfaMac

/// The Properties list of a view or place: As in Layouts until changed, the list's own looks once it is, Use Layouts, the
/// properties a type does not declare skipped for it, and the table's columns in the list's order with the name locked.
struct ViewPropertiesTests {
    private static let catalogue = LookFixture.catalogue()
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)
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

    @Test func aHeaderDragReordersTheShownPropertiesAndLeavesAHiddenOneAndAStaleName() throws {
        let columns: [ItemTableColumn] = [.title, .type, .edited, .created, .tags]
        var properties = ViewProperties(order: ["gone", "created"], shown: ["created": true])
        properties.adoptHeaderOrder(["title", "edited", "type", "created"], in: columns)
        #expect(Self.ids(properties.shownColumns(columns)) == ["title", "edited", "type", "created"])
        let stored = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(properties)) as? [String: Any])
        #expect(stored["order"] as? [String] == ["gone", "edited", "type", "created", "tags"])
    }

    @Test func aHeaderDragBackToThePlacesOrderClearsTheStoredOrder() {
        let columns: [ItemTableColumn] = [.title, .type, .edited, .created, .tags]
        var properties = ViewProperties(order: ["edited", "type", "created", "tags"])
        properties.adoptHeaderOrder(["type", "edited"], in: columns)
        #expect(properties == ViewProperties())
    }

    @Test func aHeaderDragThatIsNotTheShownColumnsIsIgnored() {
        let columns: [ItemTableColumn] = [.title, .type, .edited, .created, .tags]
        var properties = ViewProperties()
        properties.adoptHeaderOrder(["edited"], in: columns)
        properties.adoptHeaderOrder(["title"], in: columns)
        properties.adoptHeaderOrder(["edited", "edited"], in: columns)
        #expect(properties == ViewProperties())
        properties.adoptHeaderOrder(["edited", "type"], in: columns)
        #expect(Self.ids(properties.shownColumns(columns)) == ["title", "edited", "type"])
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
}
