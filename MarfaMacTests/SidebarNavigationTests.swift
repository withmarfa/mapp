import Foundation
import Testing
@testable import MarfaMac

@Suite(.hangLimit)
struct SidebarNavigationTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aSnapshotWithAnyOtherUnreadablePlaceFailsToDecode() {
        let saved = Data(#"{"place":{"pinned":{}},"selection":[],"opensItem":true,"scrollOffset":10}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Browser.Snapshot.self, from: saved) }
    }

    @Test func aStoredSidebarLayoutNamingRecentlyDeletedStillReadsAndPlans() throws {
        #expect(SidebarPlace(key: "recentlyDeleted") == nil)
        let json = #"{"hidden":["recentlyDeleted","inbox"],"order":["recentlyDeleted","all"],"collapsed":[]}"#
        let layout = try JSONDecoder().decode(SidebarLayout.self, from: Data(json.utf8))
        let plan = SidebarPlan(FakeItemLibrary(items: []), layout: layout)
        #expect(!plan.isShown(.feed))
        #expect(plan.section(.places)?.shown == [.library])
    }

    @Test func aSnapshotWithNoPlaceFailsToDecodeSoTheWindowOpensAtItsDefault() {
        let saved = Data(#"{"showing":{"pinned":{}},"selection":[]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Browser.Snapshot.self, from: saved) }
    }
}
