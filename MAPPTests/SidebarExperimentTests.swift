import Foundation
import Testing
@testable import MAPP

/// The sidebar variants kept in the defaults, and the rules they add to the sidebar's rows and a type's list.
@MainActor
struct SidebarExperimentTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func library() async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        let ticket = LibraryFixture.item(ItemID("k1"), LibraryFixture.ticket, "A ticket", age: 10)
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items + [ticket], catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    // MARK: Stored value

    @Test func theExperimentRoundTripsThroughItsStoredText() throws {
        var experiment = SidebarExperiment()
        experiment.chevron = .leading
        experiment.rowClick = .opensThenFolds
        experiment.setStacked("aic.ticket", true)
        #expect(SidebarExperiment(rawValue: experiment.rawValue) == experiment)
        experiment.setStacked("aic.ticket", false)
        #expect(experiment.stackedTypes.isEmpty)
    }

    @Test func aValueThisBuildDoesNotKnowReadsAsTheDefault() throws {
        let stored = #"{"chevron":"somewhere","rowClick":"opensOnly","stackedTypes":["aic.ticket"]}"#
        let experiment = try #require(SidebarExperiment(rawValue: stored))
        #expect(experiment.chevron == .trailing)
        #expect(experiment.stackedTypes == ["aic.ticket"])
        #expect(SidebarExperiment(rawValue: "{}") == SidebarExperiment())
        #expect(SidebarExperiment(rawValue: "not json") == nil)
    }

    @Test func theDefaultsHoldTheExperimentUnderOneKey() throws {
        let suite = "MAPP.SidebarExperimentTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SidebarExperiment.stored(in: defaults) == SidebarExperiment())
        SidebarExperiment.update(in: defaults) { $0.setStacked("aic.ticket", true) }
        SidebarExperiment.update(in: defaults) { $0.chevron = .afterName }
        let stored = SidebarExperiment.stored(in: defaults)
        #expect(stored.stackedTypes == ["aic.ticket"])
        #expect(stored.chevron == .afterName)
    }

    // MARK: Clicking an open row

    @Test func aSecondClickFoldsOnlyARowThatWasAlreadyOpen() {
        var experiment = SidebarExperiment()
        let press = start
        #expect(!experiment.foldsOnClick(pressBegan: press, selectedAt: nil))

        experiment.rowClick = .opensThenFolds
        // Nothing selected since the window began, or long before this press: the row was open already.
        #expect(experiment.foldsOnClick(pressBegan: press, selectedAt: nil))
        #expect(experiment.foldsOnClick(pressBegan: press, selectedAt: press.addingTimeInterval(-5)))
        // The press itself opened the row, whichever the list reported first.
        #expect(!experiment.foldsOnClick(pressBegan: press, selectedAt: press))
        #expect(!experiment.foldsOnClick(pressBegan: press, selectedAt: press.addingTimeInterval(0.05)))
        #expect(!experiment.foldsOnClick(pressBegan: press, selectedAt: press.addingTimeInterval(-SidebarExperiment.selectionSlack / 2)))
    }

    // MARK: Rows

    func node(_ id: String, opens: Bool = true, _ children: [TypeNode] = []) -> TypeNode {
        TypeNode(id: id, type: opens ? TypeID(id) : nil, label: id, symbol: "doc", count: opens ? 1 : 0, total: 1, children: children)
    }

    func rows(_ nodes: [TypeNode], depth: Int = 0) -> [SidebarPlan.TypeRow] {
        nodes.flatMap { [SidebarPlan.TypeRow(node: $0, depth: depth, isExpanded: true)] + rows($0.children, depth: depth + 1) }
    }

    @Test func onlySubtypesLoseTheirMarkAndOnlyWhileTheSettingIsOff() {
        // a (a1 (a1x), group (g1)), with `group` a fold-only row.
        let listed = rows([node("a", [node("a1", [node("a1x")]), node("group", opens: false, [node("g1")])])])
        #expect(listed.map(\.id) == ["a", "a1", "a1x", "group", "g1"])
        #expect(listed.map { SidebarTypeRow.showsIcon($0, subtypeIcons: false) } == [true, false, false, true, false])
        #expect(listed.map { SidebarTypeRow.showsIcon($0, subtypeIcons: true) } == [true, true, true, true, true])
    }

    @Test func aColumnStepsInOnlyWhereItsParentHasNoMark() {
        let listed = rows([node("a", [node("a1", [node("a1x")]), node("group", opens: false, [node("g1")])])])
        let indent = SidebarTypeRow.indent

        let bare = SidebarTypeRow.steps(for: listed, subtypeIcons: false)
        #expect(bare[0].isEmpty)
        // a1 has no mark, and its name starts where a's does.
        #expect(bare[1] == [.init(continues: true, bends: true, spansParentMark: true, extra: 0)])
        // a1x has no mark under a1, which has none either: a step alone, since there is no mark to leave from.
        #expect(
            bare[2] == [
                .init(continues: true, bends: false, spansParentMark: true, extra: 0),
                .init(continues: false, bends: true, spansParentMark: false, extra: indent),
            ])
        // g1 has no mark under a group that keeps its own.
        #expect(bare[4].last == .init(continues: false, bends: true, spansParentMark: true, extra: 0))

        // With marks, every row sits under its parent's name: no step beyond the parent's mark.
        let marked = SidebarTypeRow.steps(for: listed, subtypeIcons: true)
        #expect(marked.flatMap { $0 }.allSatisfy { $0.spansParentMark && $0.extra == 0 })
    }

    // MARK: Including subtypes

    @Test func aTypeWithSubtypesHoldingItemsOffersToIncludeThem() async throws {
        let library = try await library()
        let browser = Browser()
        browser.sidebarItem = .itemType(LibraryFixture.ticket.rawValue)
        #expect(browser.stackableType(in: library) == LibraryFixture.ticket.rawValue)

        // A type with no subtypes, and a place that is no type, have nothing to include.
        browser.sidebarItem = .itemType(LibraryFixture.project.rawValue)
        #expect(browser.stackableType(in: library) == nil)
        browser.sidebarItem = .allNotes
        #expect(browser.stackableType(in: library) == nil)
    }

    @Test func includingSubtypesAddsTheirItemsToTheTypesOwnAndLeavesOtherTypesAlone() async throws {
        let library = try await library()
        let browser = Browser()
        let ticket = LibraryFixture.ticket.rawValue
        browser.sidebarItem = .itemType(ticket)
        // Opening a parent type lists its own items only.
        let own = browser.items(in: library)
        #expect(own.map(\.type) == [LibraryFixture.ticket])

        browser.stackedTypes = [ticket]
        let stacked = browser.items(in: library)
        #expect(Set(stacked.map(\.type)) == [LibraryFixture.ticket, LibraryFixture.bug, LibraryFixture.task])
        #expect(stacked.count == 3)
        #expect(Set(stacked.map(\.id)).isSuperset(of: own.map(\.id)))
        // The layouts on offer follow what is listed.
        #expect(browser.availableViewModes(in: library) == ItemViewMode.available(forTypes: Set(stacked.map(\.type)), catalogue: library.catalogue))

        // Another type is not stacked by it, and a type with no subtypes lists as ever.
        let project = SidebarItem.itemType(LibraryFixture.project.rawValue)
        browser.sidebarItem = project
        #expect(browser.items(in: library) == library.items(in: project))
        browser.stackedTypes = [LibraryFixture.project.rawValue]
        #expect(browser.items(in: library) == library.items(in: project))
    }
}
