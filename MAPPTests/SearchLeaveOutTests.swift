import Foundation
import Testing
@testable import MAPP

@MainActor
@Suite struct SearchLeaveOutsStoreTests {
    private func defaults() -> UserDefaults {
        let suite = "SearchLeaveOuts-\(UUID())"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aServerLeavesNothingOutUntilTheChoiceIsMade() {
        let store = SearchLeaveOuts(defaults: defaults())
        #expect(store.leaveOut(for: "marfa:https://one.example").isEmpty)
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

@Suite struct SearchLeftOutLineTests {
    typealias F = LibraryFixture

    private let sources = SourceDirectory(infos: [
        "github": SourceInfo(code: "github", name: "GitHub", mark: nil, hasChosenName: true),
        "rss": SourceInfo(code: "rss", name: "Feeds", mark: nil, hasChosenName: true),
    ])

    private func item(_ number: Int, _ type: TypeID = F.note, source: String? = nil) -> Item {
        var item = F.item(ItemID("i\(number)"), type, "Item \(number)", age: number)
        item.source = source
        return item
    }

    private func line(_ found: [Item], capped: Bool = false, _ leave: SearchLeaveOut) -> String? {
        SearchLeftOutLine.text(
            for: found, isCapped: capped, narrowing: SearchNarrowing(leaveOut: leave), catalogue: F.catalogue, sources: sources)
    }

    @Test func nothingLeftOutMatchingSaysNothing() {
        #expect(line([], SearchLeaveOut(sources: ["github"])) == nil)
    }

    @Test func aSourceIsNamedAsTheServerNamesIt() {
        let found = (1...36).map { item($0, source: "github") }
        #expect(line(found, SearchLeaveOut(sources: ["github"])) == "36 more in GitHub, left out of search.")
    }

    @Test func aFullAnswerSaysAtLeast() {
        let found = (1...100).map { item($0, source: "github") }
        #expect(line(found, capped: true, SearchLeaveOut(sources: ["github"])) == "At least 100 more in GitHub, left out of search.")
    }

    @Test func aTypeIsNamedByItsPluralAndItsSubtypesCountUnderIt() {
        let found = [item(1, F.task), item(2, F.bug), item(3, F.ticket)]
        #expect(line(found, SearchLeaveOut(types: [F.ticket])) == "3 more in Tickets, left out of search.")
    }

    @Test func twoNamesJoinWithAnd() {
        let found = [item(1, F.ticket), item(2, source: "github")]
        #expect(line(found, SearchLeaveOut(types: [F.ticket], sources: ["github"])) == "2 more in Tickets and GitHub, left out of search.")
    }

    @Test func moreThanThreeNamesOnlyGiveTheCount() {
        let types = [F.ticket, F.project, F.entity, F.image]
        let found = types.enumerated().map { item($0.offset, $0.element) }
        #expect(line(found, SearchLeaveOut(types: Set(types))) == "4 more left out of search.")
    }
}

@Suite struct PaletteFiltersAfterSearchTests {
    @Test func theTypeFilterGoesIntoTheSearchAndTheRestAreLeftToApply() {
        var filters = PaletteFilters(types: [TypeID("core.note")], collections: [ItemID("c")], period: .today)
        filters.negated = [.type, .collection]
        let rest = filters.afterSearch
        #expect(rest.types.isEmpty)
        #expect(!rest.negated.contains(.type))
        #expect(rest.collections == [ItemID("c")])
        #expect(rest.negated.contains(.collection))
        #expect(rest.period == .today)
    }
}
