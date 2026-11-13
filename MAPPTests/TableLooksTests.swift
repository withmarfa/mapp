import Foundation
import Testing
@testable import MAPP

/// Which columns the table starts with: the name, then what the types' looks show, and the rest behind View Options.
struct TableLooksTests {
    private static let catalogue = LookFixture.catalogue()
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)

    private static func row(_ type: String, _ properties: [String: String] = [:], tags: Set<String> = []) -> ItemTableRow {
        let item = Item(
            id: .mint(), type: TypeID(type), title: "Title", name: "Title", titleRule: .firstLine,
            properties: properties.sorted { $0.key < $1.key }.map { Property(key: $0.key, value: .string($0.value)) }, tags: tags,
            version: ItemVersion(1), created: now, modified: now)
        return ItemTableRow(item: item, typeLabel: type, typeIcon: nil, parent: nil)
    }

    private static let taskLook = TypeLook(date: .field("due_at"), secondary: [], facts: [.field("priority"), .field("place")])
    private static let eventLook = TypeLook(date: .field("starts_at"), secondary: [], facts: [.field("place"), .field("url")])

    private static func columns(_ rows: [ItemTableRow], _ looks: [String: TypeLook]) -> [ItemTableColumn] {
        ItemTableLayout.columns(
            for: rows, catalogue: catalogue, hidden: [], looks: Dictionary(uniqueKeysWithValues: looks.map { (TypeID($0.key), $0.value) }))
    }

    private static func shown(_ columns: [ItemTableColumn]) -> [String] { columns.filter(\.isShownByDefault).map(\.id) }

    @Test func aTableOfOneTypeShowsTheNameThenTheStatusThenTheLooksFactsAndDate() {
        let rows = [Self.row("core.task", ["status": "todo", "priority": "high", "place": "Home", "due_at": "2026-11-20"])]
        let columns = Self.columns(rows, ["core.task": Self.taskLook])
        #expect(Self.shown(columns) == ["title", "field.status", "field.priority", "field.place", "field.due_at"])
    }

    @Test func everyOtherColumnWaitsBehindViewOptions() {
        let rows = [Self.row("core.task", ["status": "todo", "priority": "high", "completed_at": "2026-11-01"])]
        let columns = Self.columns(rows, ["core.task": Self.taskLook])
        let hidden = columns.filter { !$0.isShownByDefault }.map(\.id)
        #expect(hidden.contains("parent") && hidden.contains("created") && hidden.contains("edited") && hidden.contains("field.completed_at"))
        #expect(hidden.contains("field.body") == false, "the page's own title and body are no columns")
    }

    @Test func aTableOfSeveralTypesNamesTheTypeThenTheUnionOfTheLooksStatusFirst() {
        let rows = [
            Self.row("core.event", ["place": "Room", "starts_at": "2026-11-20T10:00:00Z", "url": "https://example.com"]),
            Self.row("core.task", ["status": "todo", "priority": "high", "place": "Home", "due_at": "2026-11-20"]),
        ]
        let columns = Self.columns(rows, ["core.task": Self.taskLook, "core.event": Self.eventLook])
        // A shared fact shows once, and the types' dates follow the facts.
        #expect(Self.shown(columns) == ["title", "type", "field.status", "field.place", "field.url", "field.priority", "field.starts_at", "field.due_at"])
    }

    @Test func aColumnNoRowFillsStartsHiddenAndAFilledOneShows() {
        let columns = Self.columns([Self.row("core.task", ["status": "todo"])], ["core.task": Self.taskLook])
        #expect(Self.shown(columns) == ["title", "field.status"])
        #expect(columns.first { $0.id == "field.priority" }?.isShownByDefault == false)
    }

    @Test func aTypeWithNoneOfItsPresetsFieldsShowsOnlyTheName() {
        let columns = Self.columns([Self.row("test.bare")], ["test.bare": Self.taskLook])
        #expect(Self.shown(columns) == ["title"])
    }

    @Test func tagsShowOnlyWhereAnItemHoldsOneApartFromTheFavoriteMark() {
        let look = TypeLook(date: .off, secondary: [], facts: [.tags])
        #expect(Self.shown(Self.columns([Self.row("core.note")], ["core.note": look])) == ["title"])
        #expect(Self.shown(Self.columns([Self.row("core.note", tags: [ItemTag.favorite])], ["core.note": look])) == ["title"])
        #expect(Self.shown(Self.columns([Self.row("core.note", tags: ["work"])], ["core.note": look])) == ["title", "tags"])
    }

    @Test func theLooksDateIsACreatedEditedOrHappenedColumn() {
        for (date, id) in [(LookDate.created, "created"), (.edited, "edited"), (.occurred, "occurred")] {
            let look = TypeLook(date: date, secondary: [], facts: [])
            #expect(Self.shown(Self.columns([Self.row("core.note")], ["core.note": look])) == ["title", id])
        }
        #expect(Self.shown(Self.columns([Self.row("core.note")], ["core.note": .empty])) == ["title"])
    }

    @Test func aSavedViewsChosenColumnsWinOverTheLook() {
        let rows = [Self.row("core.task", ["status": "todo", "priority": "high", "completed_at": "2026-11-01"])]
        let columns = Self.columns(rows, ["core.task": Self.taskLook])
        var chosen = ViewColumns()
        for column in columns where column.id == "field.priority" || column.id == "field.completed_at" {
            chosen.setShown(column, !column.isShownByDefault)
        }
        let ids = chosen.shownColumns(columns).map(\.id)
        #expect(!ids.contains("field.priority"), "a column the look shows, hidden by the view")
        #expect(ids.contains("field.completed_at"), "a column the look leaves out, shown by the view")
        #expect(ids.contains("field.status"))
    }

    @Test func aTypeWithoutAStatusFieldLeadsWithItsFacts() {
        let look = TypeLook(date: .off, secondary: [], facts: [.field("language")])
        let columns = Self.columns([Self.row("core.note", ["language": "English"])], ["core.note": look])
        #expect(Self.shown(columns) == ["title", "field.language"])
    }
}
