import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MarfaMac

private func item(
    _ id: String, type: TypeID = LibraryFixture.note, source: String? = nil, state: MarfaMac.ItemState = .active, tier: MarfaMac.Tier = .library,
    modified: Double = 0
) -> MarfaMac.Item {
    var item = MarfaMac.Item(
        id: ItemID(id), type: type, title: id, titleRule: .property("title"), properties: [], version: ItemVersion(1),
        created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: modified))
    item.source = source
    item.state = state
    item.tier = tier
    return item
}

/// What the Search page's choices do to a search and to the items the palette matches by title.
@Suite(.hangLimit) struct SearchOptionsTests {
    typealias F = LibraryFixture

    @Test func theChoicesAreMacSettingsThatResetClears() {
        for key in SearchOptions.keys { #expect(MacSettings.keys.contains(key)) }
        #expect(MacSettings.keys.contains(SearchLeaveOuts.defaultsKey))
    }

    @Test func bestMatchKeepsTheCopysOrderAndMostRecentSortsByDateKeepingTiesInOrder() {
        let items = [item("a", modified: 5), item("b", modified: 9), item("c", modified: 5), item("d", modified: 1)]
        #expect(SearchOptions.Order.bestMatch.ordered(items).map(\.id.rawValue) == ["a", "b", "c", "d"])
        #expect(SearchOptions.Order.mostRecent.ordered(items).map(\.id.rawValue) == ["b", "a", "c", "d"])
    }

    @Test func anOrderThisVersionDoesNotKnowIsBestMatch() throws {
        let defaults = try #require(UserDefaults(suiteName: "SearchOptions-\(UUID())"))
        #expect(SearchOptions.order(in: defaults) == .bestMatch)
        defaults.set("newest", forKey: SearchOptions.orderKey)
        #expect(SearchOptions.order(in: defaults) == .bestMatch)
        defaults.set("mostRecent", forKey: SearchOptions.orderKey)
        #expect(SearchOptions.order(in: defaults) == .mostRecent)
    }

    @Test func archivedAndInboxItemsAreKeptOnlyWhileTheirChoicesAreOn() {
        let archived = item("archived", state: .archived)
        let feed = item("feed", tier: .feed)
        var narrowing = SearchNarrowing()
        #expect(narrowing.isEmpty)
        #expect(narrowing.admitsOptions(archived) && narrowing.admitsOptions(feed))
        narrowing.includesArchived = false
        #expect(!narrowing.isEmpty)
        #expect(!narrowing.admitsOptions(archived) && narrowing.admitsOptions(feed))
        narrowing.includesInbox = false
        #expect(!narrowing.admitsOptions(feed))
        #expect(narrowing.searchedStates == [.active])
        #expect(narrowing.searchedTier == .library)
    }

    @Test func theChoicesReachTheCopyInsideTheSearchCall() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: F.items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        var narrowing = SearchNarrowing()
        narrowing.includesArchived = false
        narrowing.includesInbox = false
        _ = await eventually { !library.search("alpha", narrowedBy: narrowing).isPending }
        let target = try #require(source.targets.withLock { $0.last })
        guard case .items(let query, _, _) = target else { Issue.record("not an items search"); return }
        #expect(query.states == [.active])
        #expect(query.tier == .library)
    }

    @Test func aTypedPaletteKeepsWhatIsLeftOutApartAndCountsIt() {
        let kept = item("kept")
        let bug = item("bug", type: F.bug)
        let github = item("github", source: "github")
        let archived = item("archived", state: .archived)
        var narrowing = SearchNarrowing(leaveOut: SearchLeaveOut(types: [F.ticket], sources: ["github"]))
        let split = narrowing.split([kept, bug, github, archived], in: F.catalogue)
        #expect(split.kept.map(\.id.rawValue) == ["kept", "archived"])
        #expect(split.leftOut.map(\.id.rawValue) == ["bug", "github"], "a type left out takes its subtypes with it")
        narrowing.includesArchived = false
        #expect(narrowing.split([kept, archived], in: F.catalogue).kept.map(\.id.rawValue) == ["kept"])
        let line = SearchLeftOutLine.text(
            for: split.leftOut, isCapped: false, narrowing: narrowing, catalogue: F.catalogue, sources: SourceDirectory())
        #expect(line == "2 more in Tickets and github, left out of search.")
    }
}

/// The list the Search page shows of what a server leaves out.
@Suite struct SearchLeaveOutListTests {
    typealias F = LibraryFixture

    private func entries(
        _ leaveOut: SearchLeaveOut, catalogue: Catalogue = F.catalogue, sources: SourceDirectory = SourceDirectory(), offered: [TypeID] = []
    ) -> [SearchLeaveOutList.Entry] {
        let labels = SearchLeaveOutList.labels(offered: offered, leaveOut: leaveOut, catalogue: catalogue)
        return SearchLeaveOutList.entries(for: leaveOut, catalogue: catalogue, sources: sources, labels: labels)
    }

    @Test func aTypeLeftOutListsItsSubtypesAsLeftOutToo() {
        let entries = entries(SearchLeaveOut(types: [F.ticket]))
        #expect(entries.map(\.title) == ["Tickets", "Bugs", "Tasks"])
        #expect(entries.map(\.kind) == [.type(F.ticket), .subtype(F.bug, parent: F.ticket), .subtype(F.task, parent: F.ticket)])
    }

    @Test func aSourceTheCopyNoLongerHasIsKeptAndShownAsUnknown() {
        var directory = SourceDirectory()
        directory.infos = ["github": SourceInfo(code: "github", name: "GitHub", mark: nil, hasChosenName: false)]
        directory.counts = ["github": 1_840]
        let entries = entries(SearchLeaveOut(sources: ["github", "gone"]), sources: directory)
        let github = entries.first { $0.kind == .source("github") }
        let gone = entries.first { $0.kind == .source("gone") }
        #expect(github?.isKnown == true && github?.count == 1_840)
        #expect(gone?.isKnown == false)
        #expect(gone?.title == "gone")
    }

    @Test func beforeTheServerHasAnsweredNoSourceIsCalledUnknown() {
        #expect(entries(SearchLeaveOut(sources: ["github"])).map(\.isKnown) == [true])
    }

    @MainActor @Test func anUnknownSourceCanBeRemovedAndTheRestStays() throws {
        let defaults = try #require(UserDefaults(suiteName: "SearchLeaveOutList-\(UUID())"))
        let store = SearchLeaveOuts(defaults: defaults)
        store.update("marfa:a") { $0.sources = ["gone", "github"]; $0.types = [F.ticket] }
        store.update("marfa:a") { $0.sources.remove("gone") }
        #expect(store.leaveOut(for: "marfa:a") == SearchLeaveOut(types: [F.ticket], sources: ["github"]))
    }

    @Test func aTypeOrSourceAlreadyLeftOutIsNotOffered() {
        let counts = [
            ItemTypeCount(id: F.note, label: "Notes", icon: nil, count: 3), ItemTypeCount(id: F.ticket, label: "Tickets", icon: nil, count: 2),
            ItemTypeCount(id: F.bug, label: "Bugs", icon: nil, count: 1), ItemTypeCount(id: F.project, label: "Projects", icon: nil, count: 1),
        ]
        let leaveOut = SearchLeaveOut(types: [F.ticket])
        let labels = SearchLeaveOutList.labels(offered: counts.map(\.id), leaveOut: leaveOut, catalogue: F.catalogue)
        let offered = SearchLeaveOutList.typesToAdd(counts, leaveOut: leaveOut, catalogue: F.catalogue, labels: labels)
        #expect(offered.map(\.id) == [F.note, F.project], "Tickets is left out and Bugs go with it, Notes before Projects")
        let sources = SearchLeaveOutList.sourcesToAdd(
            [SourceCount(code: "a", name: "A", count: 1), SourceCount(code: "b", name: "B", count: 2)], leaveOut: SearchLeaveOut(sources: ["a"]))
        #expect(sources.map(\.code) == ["b"])
    }

    @Test func theMenuIsAToZAsTheListIsAndSaysWhichTypesTakeSubtypes() {
        let counts = [
            ItemTypeCount(id: F.project, label: "Projects", icon: nil, count: 9), ItemTypeCount(id: F.note, label: "Notes", icon: nil, count: 3),
            ItemTypeCount(id: F.bug, label: "Bugs", icon: nil, count: 1), ItemTypeCount(id: F.entity, label: "Entities", icon: nil, count: 1),
        ]
        let labels = SearchLeaveOutList.labels(offered: counts.map(\.id), leaveOut: SearchLeaveOut(), catalogue: F.catalogue)
        let offered = SearchLeaveOutList.typesToAdd(counts, leaveOut: SearchLeaveOut(), catalogue: F.catalogue, labels: labels)
        #expect(offered.map(\.label) == ["Bugs", "Entities", "Notes", "Projects"])
        #expect(offered.map(\.title) == ["Bugs", "Entities", "Notes, with 4 subtypes", "Projects"])
        let sources = SearchLeaveOutList.sourcesToAdd(
            [SourceCount(code: "z", name: "Zeta", count: 1), SourceCount(code: "a", name: "Alpha", count: 1)], leaveOut: SearchLeaveOut())
        #expect(sources.map(\.name) == ["Alpha", "Zeta"])
    }

    /// Two types that share a name are told apart the same way in the menu and in the list: "Tasks (Tickets)".
    @Test func twoTypesWithOneNameAreToldApartInTheMenuAndTheList() {
        let fields = F.ticketFields
        func type(_ id: String, _ plural: String, parent: TypeID?) -> ItemTypeInfo {
            ItemTypeInfo(id: TypeID(id), label: plural, plural: plural, fields: fields, titleField: "title", bodyField: "body", parent: parent)
        }
        let tickets = type("aic.ticket", "Tickets", parent: nil), chores = type("aic.chore", "Chores", parent: nil)
        let catalogue = Catalogue(itemTypes: [
            tickets, chores, type("aic.ticket.task", "Tasks", parent: tickets.id), type("aic.chore.task", "Tasks", parent: chores.id),
        ])
        let counts = [tickets, chores, catalogue.itemTypes[TypeID("aic.ticket.task")]!, catalogue.itemTypes[TypeID("aic.chore.task")]!]
            .map { ItemTypeCount(id: $0.id, label: $0.plural, icon: nil, count: 1) }
        let leaveOut = SearchLeaveOut(types: [TypeID("aic.ticket.task")])
        let labels = SearchLeaveOutList.labels(offered: counts.map(\.id), leaveOut: leaveOut, catalogue: catalogue)
        let offered = SearchLeaveOutList.typesToAdd(counts, leaveOut: leaveOut, catalogue: catalogue, labels: labels)
        #expect(offered.map(\.label) == ["Chores", "Tasks (Chores)", "Tickets"])
        let listed = SearchLeaveOutList.entries(for: leaveOut, catalogue: catalogue, sources: SourceDirectory(), labels: labels)
        #expect(listed.map(\.title) == ["Tasks (Tickets)"])
    }

    /// Every condition is a type or a source, and a filter holds ten: past that every search fails, so the page stops short.
    @Test func anAdditionThatWouldMakeMoreConditionsThanASearchHoldsIsNotOffered() throws {
        let sources = Set((0..<6).map { "source-\($0)" })
        let leaveOut = SearchLeaveOut(sources: sources)
        // Notes take a ticket, a project, a task and a bug with them: five types and six sources are eleven.
        #expect(!SearchLeaveOutList.fits(.type(F.note), in: leaveOut, catalogue: F.catalogue))
        #expect(SearchLeaveOutList.fits(.type(F.ticket), in: leaveOut, catalogue: F.catalogue), "three types and six sources are nine")
        #expect(SearchLeaveOutList.fits(.source("seventh"), in: leaveOut, catalogue: F.catalogue))
        let full = SearchLeaveOut(sources: Set((0..<10).map { "source-\($0)" }))
        #expect(!SearchLeaveOutList.fits(.source("eleventh"), in: full, catalogue: F.catalogue))
        #expect(!SearchLeaveOutList.fits(.type(F.bug), in: full, catalogue: F.catalogue))
        // What fits is what a search can be asked with.
        for addition in [SearchLeaveOutList.Addition.type(F.ticket), .source("seventh")] {
            var next = leaveOut
            if case .type(let type) = addition { next.types.insert(type) }
            if case .source(let code) = addition { next.sources.insert(code) }
            let narrowing = SearchNarrowing(leaveOut: next)
            _ = try narrowing.kept(in: F.catalogue)
            _ = try narrowing.leftOutOfSearch(in: F.catalogue)
        }
    }

    /// More than one is dimmed once the limit is close, not only the one that crosses it first.
    @Test func everyAdditionThatWouldCrossTheLimitIsTold() {
        let leaveOut = SearchLeaveOut(sources: Set((0..<9).map { "source-\($0)" }))
        let crossing: [SearchLeaveOutList.Addition] = [.type(F.note), .type(F.ticket), .source("tenth"), .type(F.bug)]
        let dimmed = crossing.filter { !SearchLeaveOutList.fits($0, in: leaveOut, catalogue: F.catalogue) }
        #expect(dimmed == [.type(F.note), .type(F.ticket)], "a ticket takes two subtypes, so three conditions; a source or a bug is one and fits")
        let full = SearchLeaveOut(sources: Set((0..<10).map { "source-\($0)" }))
        #expect(crossing.allSatisfy { !SearchLeaveOutList.fits($0, in: full, catalogue: F.catalogue) })
    }

    @Test func aTypeCountsForEveryTypeTheCopyHoldsBelowIt() {
        #expect(SearchNarrowing(leaveOut: SearchLeaveOut(types: [F.bug])).leaveOutConditionCount(in: F.catalogue) == 1)
        #expect(SearchNarrowing(leaveOut: SearchLeaveOut(types: [F.ticket])).leaveOutConditionCount(in: F.catalogue) == 3)
        #expect(SearchNarrowing(leaveOut: SearchLeaveOut(types: [F.ticket, F.bug], sources: ["github"])).leaveOutConditionCount(in: F.catalogue) == 4)
    }
}
