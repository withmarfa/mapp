import Foundation
import Marfa
import Synchronization
import MarfaTesting
import Testing
@testable import MarfaMac

/// The filter a search is asked with for the types and sources kept and left out. The catalogue is the fixture's: a
/// note with a ticket and a project below it, and a task and a bug below the ticket.
@Suite struct SearchNarrowingExpressionTests {
    typealias F = LibraryFixture

    /// The conditions a filter text holds, as `field operator value`, in order.
    private func conditions(_ text: String?) throws -> [String] {
        try FilterExpression(decoding: try #require(text)).conditions.map { condition in
            let field = switch condition.field {
            case .system(.type): "type"
            case .system(.source): "source"
            default: "other"
            }
            let value = if case .text(let text) = condition.value { text } else { "" }
            return "\(field) \(condition.operator) \(value)"
        }
    }

    private func narrowing(
        types: Set<TypeID> = [], withSubtypes: Set<TypeID> = [], isNot: Bool = false, leavingOut: SearchLeaveOut = SearchLeaveOut()
    ) -> SearchNarrowing {
        SearchNarrowing(types: types, typesWithSubtypes: withSubtypes, excludesTypes: isNot, leaveOut: leavingOut)
    }

    @Test func anEmptyNarrowingSendsNoTypeAndNoClause() throws {
        let expression = try SearchNarrowing.none.kept(in: F.catalogue)
        #expect(expression == SearchNarrowing.Expression())
        #expect(expression.filter == nil)
        #expect(SearchNarrowing.none.isEmpty)
    }

    @Test func aTypeKeptWithItsSubtypesIsTheTypeAlone() throws {
        let expression = try narrowing(types: [F.ticket], withSubtypes: [F.ticket]).kept(in: F.catalogue)
        #expect(expression.types == [F.ticket])
        #expect(expression.filter == nil)
    }

    @Test func aTypeKeptWithoutItsSubtypesIsOneExactTypeCondition() throws {
        let expression = try narrowing(types: [F.ticket]).kept(in: F.catalogue)
        // The `types` key takes the subtree, so it stays empty and `type eq` names the type alone.
        #expect(expression.types.isEmpty)
        #expect(try conditions(expression.filter) == ["type eq aic.ticket"])
    }

    @Test func aTypeKeptWithoutItsSubtypesStaysOneConditionWhateverItsSubtreeHolds() throws {
        let root = ItemTypeInfo(id: TypeID("t.root"), label: "Root", fields: [], titleField: nil, bodyField: nil, parent: nil)
        let below = (0..<12).map {
            ItemTypeInfo(id: TypeID("t.root.\($0)"), label: "Sub", fields: [], titleField: nil, bodyField: nil, parent: root.id)
        }
        let big = Catalogue(itemTypes: [root] + below)
        let leave = SearchLeaveOut(sources: ["a", "b", "c"])
        let expression = try narrowing(types: [root.id], leavingOut: leave).kept(in: big)
        #expect(expression.types.isEmpty)
        #expect(try conditions(expression.filter) == ["type eq t.root", "source neq a", "source neq b", "source neq c"])
    }

    @Test func aTypeKeptWithoutItsSubtypesThatIsLeftOutMatchesNothing() throws {
        let leave = SearchLeaveOut(types: [F.ticket])
        #expect(try narrowing(types: [F.ticket], leavingOut: leave).kept(in: F.catalogue).matchesNothing)
        // A type with no subtypes below it, left out through a type above it, keeps the plain form: the copy answers none.
        let leaf = try narrowing(types: [F.bug], leavingOut: SearchLeaveOut(types: [F.ticket])).kept(in: F.catalogue)
        #expect(leaf.types == [F.bug])
        #expect(try conditions(leaf.filter) == ["type neq aic.ticket.bug"])
    }

    @Test func tooManyConditionsAreToldAsTheirOwnCause() {
        let message = SearchNarrowing.Refusal.tooManyConditions.message
        #expect(message.contains("chosen"), "the chosen types count too, so the message must not blame the leave-out alone")
        #expect(message.contains("left out"))
    }

    @Test func severalTypesWithoutSubtypesStillSkipEachSubtype() throws {
        let expression = try narrowing(types: [F.ticket, F.project]).kept(in: F.catalogue)
        #expect(expression.types == [F.ticket, F.project])
        #expect(try conditions(expression.filter) == ["type neq aic.ticket.bug", "type neq aic.ticket.task"])
    }

    @Test func aSubtypeAlsoChosenIsNotSkipped() throws {
        let expression = try narrowing(types: [F.note, F.task]).kept(in: F.catalogue)
        #expect(expression.types == [F.note, F.task])
        // The task's own items stay; the ticket, the bug and the project are the note's subtypes.
        #expect(try conditions(expression.filter) == ["type neq aic.project", "type neq aic.ticket", "type neq aic.ticket.bug"])
    }

    @Test func aTypeNotInTheCatalogueMatchesNothing() throws {
        let expression = try narrowing(types: [TypeID("gone.type")]).kept(in: F.catalogue)
        #expect(expression.matchesNothing)
    }

    @Test func aTypeLeftOutTakesItsSubtypesWithIt() throws {
        let leave = SearchLeaveOut(types: [F.ticket])
        let expression = try narrowing(leavingOut: leave).kept(in: F.catalogue)
        #expect(expression.types.isEmpty)
        #expect(try conditions(expression.filter) == ["type neq aic.ticket", "type neq aic.ticket.bug", "type neq aic.ticket.task"])
    }

    @Test func aSourceLeftOutIsOneClauseWhetherOrNotTheCopyKnowsIt() throws {
        let expression = try narrowing(leavingOut: SearchLeaveOut(sources: ["github", "never-seen"])).kept(in: F.catalogue)
        #expect(try conditions(expression.filter) == ["source neq github", "source neq never-seen"])
    }

    @Test func aTypeNoItemCanHaveNeedsNoClause() throws {
        let expression = try narrowing(leavingOut: SearchLeaveOut(types: [TypeID("gone.type")])).kept(in: F.catalogue)
        #expect(expression.filter == nil)
    }

    @Test func aLeaveOutOutsideTheChosenTypesNeedsNoClause() throws {
        let expression = try narrowing(types: [F.project], leavingOut: SearchLeaveOut(types: [F.task])).kept(in: F.catalogue)
        #expect(expression.filter == nil)
    }

    @Test func aTypeFilterThatReadsIsNotSkipsTheTypeAndWithSubtypesItsSubtypes() throws {
        let alone = try narrowing(types: [F.ticket], isNot: true).kept(in: F.catalogue)
        #expect(alone.types.isEmpty)
        #expect(try conditions(alone.filter) == ["type neq aic.ticket"])
        let with = try narrowing(types: [F.ticket], withSubtypes: [F.ticket], isNot: true).kept(in: F.catalogue)
        #expect(try conditions(with.filter) == ["type neq aic.ticket", "type neq aic.ticket.bug", "type neq aic.ticket.task"])
    }

    @Test func typesAndSourcesLeftOutJoinWithAndAlongsideTheTypesKept() throws {
        let leave = SearchLeaveOut(types: [F.bug], sources: ["github"])
        let expression = try narrowing(types: [F.ticket], withSubtypes: [F.ticket], leavingOut: leave).kept(in: F.catalogue)
        #expect(expression.types == [F.ticket])
        #expect(try conditions(expression.filter) == ["type neq aic.ticket.bug", "source neq github"])
        #expect(try #require(expression.filter).contains(" AND "))
    }

    @Test func moreThanTenConditionsAreRefusedAndSoAreMoreThanTenTypes() throws {
        let many = SearchLeaveOut(sources: Set((0..<11).map { "source-\($0)" }))
        #expect(throws: SearchNarrowing.Refusal.tooManyConditions) { try narrowing(leavingOut: many).kept(in: F.catalogue) }
        #expect(throws: SearchNarrowing.Refusal.tooManyConditions) { try narrowing(leavingOut: many).leftOutOfSearch(in: F.catalogue) }
        let ten = SearchLeaveOut(sources: Set((0..<10).map { "source-\($0)" }))
        #expect(try conditions(narrowing(leavingOut: ten).kept(in: F.catalogue).filter).count == 10)

        let infos = (0..<11).map {
            ItemTypeInfo(id: TypeID("t.\($0)"), label: "T", fields: [], titleField: nil, bodyField: nil, parent: nil)
        }
        let big = Catalogue(itemTypes: infos)
        let chosen = Set(infos.map(\.id))
        #expect(throws: SearchNarrowing.Refusal.tooManyTypes) { try narrowing(types: chosen).kept(in: big) }
    }

    // MARK: What is left out

    @Test func theLeftOutSearchWritesTheLeaveOutAsOneOrOfEveryTypeAndSource() throws {
        let leave = SearchLeaveOut(types: [F.ticket], sources: ["github"])
        let expression = try narrowing(leavingOut: leave).leftOutOfSearch(in: F.catalogue)
        #expect(expression.types.isEmpty)
        #expect(try conditions(expression.filter) == ["type eq aic.ticket", "type eq aic.ticket.bug", "type eq aic.ticket.task", "source eq github"])
        #expect(try #require(expression.filter).contains(" OR "))
    }

    @Test func theLeftOutSearchKeepsTheChosenTypesAsTheTypesKey() throws {
        let leave = SearchLeaveOut(types: [F.bug, F.project])
        let expression = try narrowing(types: [F.ticket], withSubtypes: [F.ticket], leavingOut: leave).leftOutOfSearch(in: F.catalogue)
        #expect(expression.types == [F.ticket])
        // The project is not under the ticket, so only the bug is asked for.
        #expect(try conditions(expression.filter) == ["type eq aic.ticket.bug"])
        // Without Include Subtypes the bug is not among the items chosen, so nothing left out can match.
        #expect(try narrowing(types: [F.ticket], leavingOut: leave).leftOutOfSearch(in: F.catalogue).matchesNothing)
    }

    @Test func theLeftOutSearchOfOneTypeAloneNamesThatTypeExactlySoItsSubtypesDoNotFillTheCap() throws {
        // One source left out: both conditions are ANDed, so the copy answers only the type's own items.
        let source = try narrowing(types: [F.ticket], leavingOut: SearchLeaveOut(sources: ["github"])).leftOutOfSearch(in: F.catalogue)
        #expect(source.types.isEmpty)
        #expect(try conditions(source.filter) == ["type eq aic.ticket", "source eq github"])
        #expect(try #require(source.filter).contains(" AND "))
        // The type itself left out: every one of its own items is left out, whatever the sources.
        let leaveType = SearchLeaveOut(types: [F.ticket], sources: ["github", "other"])
        let own = try narrowing(types: [F.ticket], leavingOut: leaveType).leftOutOfSearch(in: F.catalogue)
        #expect(own.types.isEmpty)
        #expect(try conditions(own.filter) == ["type eq aic.ticket"])
    }

    @Test func nothingLeftOutMeansNothingToAsk() throws {
        #expect(try SearchNarrowing.none.leftOutOfSearch(in: F.catalogue).matchesNothing)
        #expect(try narrowing(types: [F.ticket]).leftOutOfSearch(in: F.catalogue).matchesNothing)
    }

    // MARK: Judging an item

    @Test func aTypeFilterAdmitsTheTypeAndOnlyItsSubtypesWhenAsked() {
        let alone = narrowing(types: [F.ticket])
        #expect(alone.admitsType(F.ticket, in: F.catalogue))
        #expect(!alone.admitsType(F.task, in: F.catalogue))
        let with = narrowing(types: [F.ticket], withSubtypes: [F.ticket])
        #expect(with.admitsType(F.task, in: F.catalogue))
        #expect(!with.admitsType(F.project, in: F.catalogue))
        #expect(!with.admitsType(F.note, in: F.catalogue))
        #expect(SearchNarrowing.none.admitsType(F.note, in: F.catalogue))
        let isNot = narrowing(types: [F.ticket], isNot: true)
        #expect(!isNot.admitsType(F.ticket, in: F.catalogue))
        #expect(isNot.admitsType(F.task, in: F.catalogue))
    }

    @Test func anItemIsLeftOutByItsSourceElseByTheTypeLeftOutItSitsUnder() {
        let leave = SearchNarrowing(leaveOut: SearchLeaveOut(types: [F.ticket], sources: ["github"]))
        var item = F.item(F.n1, F.task, "A task", age: 1)
        item.source = nil
        #expect(leave.leftOutBy(item, in: F.catalogue) == .type(F.ticket))
        item.source = "github"
        #expect(leave.leftOutBy(item, in: F.catalogue) == .source("github"))
        item.type = F.note
        item.source = "other"
        #expect(leave.leftOutBy(item, in: F.catalogue) == nil)
    }
}

/// The narrowing goes into the copy's one search call, so what the limit counts is what the person asked to see.
@MainActor
@Suite(.serialized, .hangLimit) struct SearchNarrowingLibraryTests {
    private static let stamp = "2026-10-06T00:00:00Z"

    private static func row(_ id: String, type: String, title: String, body: String) -> Marfa.Item {
        Marfa.Item(
            id: id, type: type, properties: ["title": .string(title), "body": .string(body)], state: .active,
            tier: .library, version: 1, schemaVersion: 1, source: "test", sourceId: nil, occurredAt: stamp,
            createdAt: stamp, updatedAt: stamp, tags: [])
    }

    private func settled(_ library: MarfaLibrary, _ run: () -> SearchResults) async -> SearchResults {
        _ = await eventually { !run().isPending }
        return run()
    }

    @Test func anItemPastTheFiveHundredthHitIsFoundOnceTheTypeFilterIsInTheSearch() async throws {
        var rows = (0..<(SearchResults.limit + 20)).map {
            Self.row("note-\($0)", type: "core.note", title: "Zebra \($0)", body: "zebra zebra crossing")
        }
        rows.append(Self.row("task-late", type: "core.task", title: "Errand", body: "a zebra"))
        let source = SampleLibrary.open(SampleLibrary.connection, items: rows, edges: [])
        defer { Task { await source.close() } }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.events.yield(.paint)
        try #require(await eventually { library.isLoaded })

        let unfiltered = await settled(library) { library.search("zebra", in: .everywhere) }
        #expect(unfiltered.isCapped)
        #expect(unfiltered.items.count == SearchResults.limit)
        #expect(!unfiltered.items.contains { $0.id == ItemID("task-late") }, "the witness: the cut leaves the task out")

        let narrowing = SearchNarrowing(types: [TypeID("core.task")])
        let narrowed = await settled(library) { library.search("zebra", narrowedBy: narrowing) }
        #expect(narrowed.items.map(\.id.rawValue) == ["task-late"])
        #expect(!narrowed.isCapped)
    }

    @Test func theNarrowingReachesTheSourceAsItsTypesAndFilter() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        let narrowing = SearchNarrowing(
            types: [LibraryFixture.ticket], typesWithSubtypes: [LibraryFixture.ticket],
            leaveOut: SearchLeaveOut(types: [LibraryFixture.bug], sources: ["github"]))
        _ = await settled(library) { library.search("alpha", narrowedBy: narrowing) }
        let target = try #require(source.targets.withLock { $0.last })
        guard case .items(let query, let filter, let limit) = target else { Issue.record("not an items search"); return }
        #expect(query.types == [LibraryFixture.ticket])
        #expect(query.states == MarfaLibrary.searchScope.states)
        #expect(filter == "type neq \"aic.ticket.bug\" AND source neq \"github\"")
        #expect(limit == SearchResults.limit)
    }

    @Test func aSearchWithNothingLeftOutAsksNoLeftOutSearchAndSendsNoClause() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        _ = await settled(library) { library.search("alpha", narrowedBy: SearchNarrowing()) }
        let kept = try #require(source.targets.withLock { $0.last })
        #expect(kept == .items(MarfaLibrary.searchScope))
        let before = source.searches.withLock { $0 }
        #expect(library.searchLeftOut("alpha", narrowedBy: SearchNarrowing()).items.isEmpty)
        #expect(source.searches.withLock { $0 } == before, "nothing left out, so the copy is not asked")
    }

    @Test func aLeftOutSearchAsksTheLimitedCallWithTheLeaveOutInverted() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        let narrowing = SearchNarrowing(leaveOut: SearchLeaveOut(sources: ["github"]))
        _ = await settled(library) { library.searchLeftOut("alpha", narrowedBy: narrowing) }
        let target = try #require(source.targets.withLock { $0.last })
        guard case .items(_, let filter, let limit) = target else { Issue.record("not an items search"); return }
        #expect(filter == "source eq \"github\"")
        #expect(limit == SearchResults.leftOutLimit)
    }

    @Test func whileANarrowedSearchIsPendingTheLastAnswerShowsOnlyWhatTheNarrowingAdmits() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        source.hits.withLock { $0["body"] = [LibraryFixture.n1, LibraryFixture.p1] }
        let first = await settled(library) { library.search("body", narrowedBy: SearchNarrowing()) }
        #expect(first.items.map(\.id) == [LibraryFixture.n1, LibraryFixture.p1])

        // The new key has no answer yet: the earlier one stands, cut to the project.
        let narrowing = SearchNarrowing(types: [LibraryFixture.project])
        let pending = library.search("body", narrowedBy: narrowing)
        #expect(pending.isPending)
        #expect(pending.items.map(\.id) == [LibraryFixture.p1])
        // Excluding the project reads the same way.
        let excluding = library.search("body", narrowedBy: SearchNarrowing(types: [LibraryFixture.project], excludesTypes: true))
        #expect(excluding.items.map(\.id) == [LibraryFixture.n1])
    }

    @Test func aNarrowingThatAdmitsNothingIsNotCompleteWhileTheCopyIsFilling() async throws {
        let source = FakeItemSource()
        source.report.update { $0.fill = LibraryFill(state: .filling, listed: 1, expected: 9) }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        let nothing = SearchNarrowing(types: [TypeID("gone.type")])
        let filling = await settled(library) { library.search("alpha", narrowedBy: nothing) }
        #expect(filling.items.isEmpty)
        #expect(filling.isIncomplete, "a copy still filling may hold items the narrowing admits")

        source.report.update { $0.fill = LibraryFill(state: .complete, listed: 9, expected: 9) }
        #expect(await eventually {
            let whole = library.search("alpha", narrowedBy: nothing)
            return !whole.isPending && !whole.isIncomplete
        })
        #expect(source.searches.withLock { $0 } == 0, "a narrowing that admits nothing asks the copy nothing")
    }

    // MARK: A real copy answers the filter

    /// A real copy, since the fake working copy answers no `filter`: a parent type with a subtype, each holding one
    /// item that matches "zebra", and the source the copy stamps on them.
    private func withTypedLibrary(
        _ body: (MarfaLibrary, _ parent: TypeID, _ child: TypeID, _ source: String) async throws -> Void
    ) async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        let marfaSource = MarfaSource(copy: copy, connection: SampleLibrary.connection)
        let library = MarfaLibrary(source: marfaSource, notices: Notices())
        defer { Task { await marfaSource.close() } }
        marfaSource.events.yield(.paint)
        try #require(await eventually { library.isLoaded })
        let catalogue = library.catalogue
        let pair = try #require(
            catalogue.itemTypes.values.sorted { $0.id.rawValue < $1.id.rawValue }.first { child in
                guard let parent = child.parent.flatMap({ catalogue.itemTypes[$0] }) else { return false }
                return [child, parent].allSatisfy { $0.titleKey != nil && $0.bodyKey != nil && catalogue.isCreatable($0.id) }
            }, "the built-in catalogue has no type with a parent that takes a title and text")
        let parent = try #require(pair.parent)
        for (id, type) in [("own", parent), ("sub", pair.id)] {
            let info = try #require(catalogue.itemTypes[type])
            _ = try await copy.items.create(Draft(
                type: type.rawValue,
                properties: [try #require(info.titleKey): .string("Zebra \(id)"), try #require(info.bodyKey): .string("zebra crossing")], id: ItemID.mint().rawValue))
        }
        try #require(await eventually { library.items(in: .allItems).count >= 2 })
        let stamped = try #require(library.items(in: .allItems).compactMap(\.source).first, "the copy stamps a source")
        try await body(library, parent, pair.id, stamped)
    }

    private func titles(_ results: SearchResults) -> [String] { results.items.map(\.title).sorted() }

    @Test func aTypeLeftOutTakesItsSubtypesAndASubtypeLeftOutTakesOnlyItself() async throws {
        try await withTypedLibrary { library, parent, child, _ in
            let none = await settled(library) { library.search("zebra", narrowedBy: SearchNarrowing()) }
            #expect(titles(none) == ["Zebra own", "Zebra sub"])

            let parentOut = SearchNarrowing(leaveOut: SearchLeaveOut(types: [parent]))
            let gone = await settled(library) { library.search("zebra", narrowedBy: parentOut) }
            #expect(gone.items.isEmpty)
            let counted = await settled(library) { library.searchLeftOut("zebra", narrowedBy: parentOut) }
            #expect(titles(counted) == ["Zebra own", "Zebra sub"])

            let childOut = SearchNarrowing(leaveOut: SearchLeaveOut(types: [child]))
            let rest = await settled(library) { library.search("zebra", narrowedBy: childOut) }
            #expect(titles(rest) == ["Zebra own"])
            let more = await settled(library) { library.searchLeftOut("zebra", narrowedBy: childOut) }
            #expect(titles(more) == ["Zebra sub"])
        }
    }

    @Test func aTypeChosenFollowsIncludeSubtypes() async throws {
        try await withTypedLibrary { library, parent, _, _ in
            let alone = SearchNarrowing(types: [parent])
            let own = await settled(library) { library.search("zebra", narrowedBy: alone) }
            #expect(titles(own) == ["Zebra own"])
            let with = SearchNarrowing(types: [parent], typesWithSubtypes: [parent])
            let both = await settled(library) { library.search("zebra", narrowedBy: with) }
            #expect(titles(both) == ["Zebra own", "Zebra sub"])
        }
    }

    @Test func aSourceLeftOutIsSkippedAndASourceTheCopyDoesNotKnowSkipsNothing() async throws {
        try await withTypedLibrary { library, _, _, source in
            let known = SearchNarrowing(leaveOut: SearchLeaveOut(sources: [source]))
            let skipped = await settled(library) { library.search("zebra", narrowedBy: known) }
            #expect(skipped.items.isEmpty)
            let counted = await settled(library) { library.searchLeftOut("zebra", narrowedBy: known) }
            #expect(titles(counted) == ["Zebra own", "Zebra sub"])

            let unknown = SearchNarrowing(leaveOut: SearchLeaveOut(sources: ["never-seen"]))
            let all = await settled(library) { library.search("zebra", narrowedBy: unknown) }
            #expect(titles(all) == ["Zebra own", "Zebra sub"])
            let nothing = await settled(library) { library.searchLeftOut("zebra", narrowedBy: unknown) }
            #expect(nothing.items.isEmpty)
        }
    }

    @Test func aLeftOutSearchHonorsTheTypeChosenToTheLetter() async throws {
        try await withTypedLibrary { library, parent, child, source in
            // The sub's source is left out, and only the parent type's own items are wanted.
            let narrowing = SearchNarrowing(types: [parent], leaveOut: SearchLeaveOut(sources: [source]))
            let counted = await settled(library) { library.searchLeftOut("zebra", narrowedBy: narrowing) }
            #expect(titles(counted) == ["Zebra own"])
            #expect(child != parent)
        }
    }

    @Test func aLeaveOutTooBigForOneSearchFindsNothingAndAsksNothing() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        let narrowing = SearchNarrowing(leaveOut: SearchLeaveOut(sources: Set((0..<11).map { "s\($0)" })))
        let found = await settled(library) { library.search("alpha", narrowedBy: narrowing) }
        #expect(found.items.isEmpty)
        #expect(source.searches.withLock { $0 } == 0)
    }
}
