import Foundation
import Testing
@testable import MarfaMac

struct ItemViewModeTests {
    private static let task = TypeID("example.task")
    private static let event = TypeID("example.event")
    private static let plain = TypeID("example.plain")
    @Test func aStoredLayoutThisVersionDoesNotHaveReadsAsTheList() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(ItemViewMode.self, from: Data(#""agenda""#.utf8)) == .list)
        #expect(try decoder.decode(ItemViewMode.self, from: Data(#""timeline""#.utf8)) == .timeline)
        let kept = try decoder.decode([String: ItemViewMode].self, from: Data(#"{"a":"agenda","b":"table"}"#.utf8))
        #expect(kept == ["a": .list, "b": .table])
    }

    @Test func aWindowKeptOnTheOldLayoutNameOpensInTheListAtItsPlace() throws {
        let (library, _, _, favorite) = BrowserTests().makeFakeLibrary()
        let kept = Browser.Snapshot(place: .library, selection: [favorite.id], viewMode: .table)
        let json = try #require(String(data: JSONEncoder().encode(kept), encoding: .utf8))
        let oldName = json.replacingOccurrences(of: #""viewMode":"table""#, with: #""viewMode":"agenda""#)
        try #require(oldName != json)
        let saved = Data(oldName.utf8)
        let browser = Browser()
        browser.restore(from: saved, in: library, order: ItemOrder())
        #expect(browser.viewMode == .list)
        #expect(browser.shown == .library)
        #expect(browser.selection == [favorite.id])
    }
}
