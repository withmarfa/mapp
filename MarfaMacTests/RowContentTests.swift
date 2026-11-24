import Foundation
import Testing
@testable import MarfaMac

/// What a row says, from an item and the look of its type: the pure model under the row, with nothing drawn.
@MainActor
struct RowContentTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
    /// Friday 13 November 2026, mid-afternoon.
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)
    private static let longAgo = now.addingTimeInterval(-86_400 * 90)

    private static func item(
        _ type: String, title: String = "Title", _ properties: [Property] = [], modified: Date = longAgo, tags: Set<String> = [],
        preview: String = ""
    ) -> Item {
        var item = Item(
            id: .mint(), type: TypeID(type), title: title, name: title, titleRule: .firstLine, properties: properties, preview: preview,
            tags: tags, version: ItemVersion(1), created: modified, modified: modified)
        item.occurred = nil
        return item
    }

    // MARK: The list

    @Test func contentIsWorkedOutOncePerItemValueAndRebuiltWhenTheItemChanges() {
        let note = Self.item("core.note", title: "First", modified: Self.now)
        let library = FakeItemLibrary(items: [note], now: Self.now)
        let contents = RowContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let entries = [RowContents.Entry(item: note, showsTime: false)]
        let first = contents.contents(of: entries, in: library, looks: [:], list: list)
        #expect(first[note.id]?.title == "First")
        var renamed = note
        renamed.name = "Second"
        let second = contents.contents(of: [RowContents.Entry(item: renamed, showsTime: false)], in: library, looks: [:], list: list)
        #expect(second[note.id]?.title == "Second")
        #expect(contents.contents(of: [], in: library, looks: [:], list: list).isEmpty)
    }

    @Test func anItemThatIsGoneIsLetGoAndOneThatStaysIsKept() {
        let kept = Self.item("core.note", title: "Kept", modified: Self.now)
        let gone = Self.item("core.note", title: "Gone", modified: Self.now)
        let library = FakeItemLibrary(items: [kept, gone], now: Self.now)
        let contents = RowContents()
        let list = RowList(day: Self.calendar.startOfDay(for: Self.now))
        let both = contents.contents(
            of: [kept, gone].map { RowContents.Entry(item: $0, showsTime: false) }, in: library, looks: [:], list: list)
        #expect(Set(both.keys) == [kept.id, gone.id])
        let one = contents.contents(of: [RowContents.Entry(item: kept, showsTime: false)], in: library, looks: [:], list: list)
        #expect(Set(one.keys) == [kept.id])
        #expect(one[kept.id] == both[kept.id])
        let again = contents.contents(of: [RowContents.Entry(item: kept, showsTime: true)], in: library, looks: [:], list: list)
        #expect(again[kept.id]?.title == "Kept")
    }
}
