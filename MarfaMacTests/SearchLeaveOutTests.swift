import Foundation
import Testing
@testable import MarfaMac

@MainActor
@Suite struct SearchLeaveOutsStoreTests {
    private func defaults() -> UserDefaults {
        let defaults = ThrowawayDefaults.make("SearchLeaveOuts")
        return defaults
    }

    @Test func eachServerKeepsItsOwnChoiceAcrossLaunches() {
        let defaults = defaults()
        let store = SearchLeaveOuts(defaults: defaults)
        store.update("marfa:https://one.example") { $0.types = [TypeID("core.highlight")]; $0.sources = ["github"] }
        store.update("marfa:https://two.example") { $0.sources = ["rss"] }
        let again = SearchLeaveOuts(defaults: defaults)
        #expect(again.leaveOut(for: "marfa:https://one.example") == SearchLeaveOut(types: [TypeID("core.highlight")], sources: ["github"]))
        #expect(again.leaveOut(for: "marfa:https://two.example") == SearchLeaveOut(sources: ["rss"]))
    }

    @Test func takingEverythingBackLeavesNothingStored() throws {
        let defaults = defaults()
        let store = SearchLeaveOuts(defaults: defaults)
        store.update("marfa:a") { $0.sources = ["github"] }
        store.update("marfa:a") { $0 = SearchLeaveOut() }
        let stored = try #require(defaults.data(forKey: "searchLeaveOuts"))
        #expect(String(data: stored, encoding: .utf8) == "{}")
    }

    @Test func storedTextThatCannotBeReadIsSetAsideAndNeverRemoved() throws {
        let defaults = defaults()
        let junk = Data("not json".utf8)
        defaults.set(junk, forKey: "searchLeaveOuts")
        let store = SearchLeaveOuts(defaults: defaults)
        #expect(store.leaveOut(for: "marfa:a").isEmpty)
        #expect(defaults.array(forKey: SearchLeaveOuts.setAsideKey) as? [Data] == [junk])
    }

    @Test func oneServersUnreadableEntryIsSetAsideAndTheOthersAreKept() throws {
        let defaults = defaults()
        let saved = Data(#"{"marfa:good":{"types":[],"sources":["github"]},"marfa:bad":{"types":"oops"}}"#.utf8)
        defaults.set(saved, forKey: "searchLeaveOuts")
        let store = SearchLeaveOuts(defaults: defaults)
        #expect(store.leaveOut(for: "marfa:good") == SearchLeaveOut(sources: ["github"]))
        #expect(store.leaveOut(for: "marfa:bad").isEmpty)
        let aside = try #require((defaults.array(forKey: SearchLeaveOuts.setAsideKey) as? [Data])?.first)
        #expect(String(data: aside, encoding: .utf8)?.contains("oops") == true)
    }
}
