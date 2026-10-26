import Foundation
import Testing
@testable import MAPP

/// An undo manager as a window has one: it groups by event and is given no group of its own, so a batch is one step
/// only if the library registers it as one. The library names each step it registers, so the names counted are the
/// steps.
final class StepCountingUndoManager: UndoManager {
    private(set) var steps = 0

    override func setActionName(_ actionName: String) {
        steps += 1
        super.setActionName(actionName)
    }
}

/// A command on a selection: what it writes for the items that take it, and how it tells the person about the rest.
@MainActor
@Suite struct MarfaBulkActionsTests {
    typealias F = TypeChangeFixture

    private static func note(_ id: ItemID, state: ItemState = .active) -> Item {
        let date = Date(timeIntervalSince1970: 1_000_000)
        var item = Item(
            id: id, type: F.note, title: id.rawValue, titleRule: .property("title"),
            properties: [Property(key: "title", value: .string(id.rawValue))], version: ItemVersion(1),
            created: date, modified: date)
        item.state = state
        return item
    }

    private func loaded(_ items: [Item]) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for item in items { source.setBody("Text of \(item.id.rawValue)", of: item.id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        // Pages other suites leave open are not this test's to wait on.
        library.handOverEdits = { $0(true) }
        source.send(.loaded(SourceSnapshot(items: items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private func skips(_ reasons: BatchSkips.Reason...) -> String? {
        var skips = BatchSkips()
        for reason in reasons { skips.skip(reason) }
        return skips.message
    }

    private let a = ItemID("a"), b = ItemID("b"), binned = ItemID("binned"), ghost = ItemID("ghost")

    @Test func aTypeChangeTakesWhatItCanAndTellsHowManyItSkipped() async throws {
        let (library, source) = try await loaded([Self.note(a), Self.note(b), Self.note(binned, state: .trashed)])
        #expect(library.changeType([a, b, binned, ghost], to: F.task, filling: [:], undoManager: nil))
        #expect(Set(source.writes.compactMap { if case .retype(let id, _, _, _) = $0 { id } else { nil } }) == [a, b])
        #expect(source.writes.count == 2)
        #expect(library.notices.waiting.last?.title == String(localized: "Some Items Were Skipped"))
        #expect(library.notices.waiting.last?.message == skips(.gone, .inBin))
    }

    @Test func aTypeChangeThatTakesNothingSendsNothingAndSaysWhy() async throws {
        let (library, source) = try await loaded([Self.note(binned, state: .trashed)])
        #expect(!library.changeType([binned], to: F.task, filling: [:], undoManager: nil))
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Change Type"))
        #expect(library.notices.waiting.last?.message == skips(.inBin))
    }

    @Test func anEmptySelectionChangesAndTellsNothing() async throws {
        let (library, source) = try await loaded([Self.note(a)])
        library.changeType([], to: F.task, filling: [:], undoManager: nil)
        library.setFavorite([], true, undoManager: nil)
        library.delete([], undoManager: nil)
        #expect(source.writes.isEmpty)
        #expect(library.notices.told == 0)
    }

    /// The source reporting what a write did, as the server's answer does: an undo acts on what the items hold then.
    private func applied(_ ids: [ItemID], to library: MarfaLibrary, via source: FakeItemSource, _ change: (inout Item) -> Void) async throws {
        var changed: [Item] = []
        for id in ids {
            var item = try #require(library.item(id))
            change(&item)
            changed.append(item)
        }
        source.send(.upserted(changed))
        let expected = Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0) })
        try #require(await eventually { ids.allSatisfy { library.item($0)?.type == expected[$0]?.type && library.item($0)?.tags == expected[$0]?.tags } })
    }

    private func tagWrites(_ source: FakeItemSource) -> [ItemWrite] {
        source.writes.filter { if case .tag = $0 { true } else { false } }
    }

    @Test func aTypeChangeIsOneUndoStep() async throws {
        let (library, source) = try await loaded([Self.note(a), Self.note(b)])
        let undo = StepCountingUndoManager()
        #expect(library.changeType([a, b], to: F.task, filling: [:], undoManager: undo))
        #expect(undo.steps == 1)
        #expect(undo.undoActionName == String(localized: "Change Type"))
        try await applied([a, b], to: library, via: source) { $0.type = F.task }
        source.clearWrites()
        undo.undo()
        let retyped = source.writes.compactMap { write -> ItemID? in if case .retype(let id, F.note, _, _) = write { id } else { nil } }
        #expect(Set(retyped) == [a, b])
        #expect(source.writes.count == 2, "one write for each item, back to its type")
        #expect(!undo.canUndo)
        #expect(undo.canRedo)
    }

    @Test func favoritingIsOneUndoStepAndUndoLeavesWhatWasSkippedAlone() async throws {
        let (library, source) = try await loaded([Self.note(a), Self.note(b), Self.note(binned, state: .trashed)])
        let undo = StepCountingUndoManager()
        library.setFavorite([a, b, binned, ghost], true, undoManager: undo)
        #expect(undo.steps == 1, "the items skipped add no step of their own")
        source.clearWrites()
        undo.undo()
        #expect(Set(source.writes) == [.tag(a, ItemTag.favorite, on: false), .tag(b, ItemTag.favorite, on: false)])
        #expect(!undo.canUndo)
        source.clearWrites()
        undo.redo()
        #expect(Set(source.writes) == [.tag(a, ItemTag.favorite, on: true), .tag(b, ItemTag.favorite, on: true)])
    }

    @Test func addingATagIsOneUndoStepAndUndoRemovesItOnlyFromWhatTookIt() async throws {
        let (library, source) = try await loaded([Self.note(a), Self.note(b), Self.note(binned, state: .trashed)])
        let undo = StepCountingUndoManager()
        #expect(library.addTag("work", to: [a, b, binned, ghost], undoManager: undo) == nil)
        #expect(undo.steps == 1)
        #expect(Set(tagWrites(source)) == [.tag(a, "work", on: true), .tag(b, "work", on: true)])
        #expect(library.notices.waiting.last?.message == skips(.gone, .inBin))
        try await applied([a, b], to: library, via: source) { $0.tags.insert("work") }
        source.clearWrites()
        undo.undo()
        #expect(Set(source.writes) == [.tag(a, "work", on: false), .tag(b, "work", on: false)])
        #expect(!undo.canUndo)
    }

    @Test func removingATagIsOneUndoStep() async throws {
        var tagged = Self.note(a)
        tagged.tags = ["work"]
        var alsoTagged = Self.note(b)
        alsoTagged.tags = ["work"]
        let (library, source) = try await loaded([tagged, alsoTagged])
        let undo = StepCountingUndoManager()
        library.removeTag("work", from: [a, b], undoManager: undo)
        #expect(undo.steps == 1)
        try await applied([a, b], to: library, via: source) { $0.tags.remove("work") }
        source.clearWrites()
        undo.undo()
        #expect(Set(source.writes) == [.tag(a, "work", on: true), .tag(b, "work", on: true)])
    }

    @Test func movingToTheBinIsOneUndoStepAndUndoRecoversOnlyWhatMoved() async throws {
        let (library, source) = try await loaded([Self.note(a), Self.note(b), Self.note(binned, state: .trashed)])
        let undo = StepCountingUndoManager()
        library.delete([a, b, binned], undoManager: undo)
        #expect(undo.steps == 1)
        source.clearWrites()
        undo.undo()
        #expect(Set(source.writes) == [.transition(a, .active), .transition(b, .active)])
    }

    @Test func favoritingLeavesItemsInTheBinAndTellsHowMany() async throws {
        let (library, source) = try await loaded([Self.note(a), Self.note(b), Self.note(binned, state: .trashed)])
        library.setFavorite([a, b, binned], true, undoManager: nil)
        #expect(source.writes.count == 2)
        #expect(source.writes.allSatisfy { if case .tag(_, _, on: true) = $0 { true } else { false } })
        #expect(library.notices.waiting.last?.message == skips(.inBin))
    }

    @Test func aVeryLargeSelectionQueuesOneWriteForEachItemUnderOneUndoStep() async throws {
        let items = (0..<500).map { Self.note(ItemID("n\($0)")) }
        let (library, source) = try await loaded(items)
        let undo = StepCountingUndoManager()
        library.changeType(Set(items.map(\.id)), to: F.task, filling: [:], undoManager: undo)
        #expect(undo.steps == 1)
        #expect(await eventually { source.writes.count == 500 })
        undo.undo()
        #expect(!undo.canUndo)
        #expect(library.notices.told == 0)
    }

    @Test func movingSeveralItemsToTheBinAsksFirstAndOneDoesNot() {
        let library = FakeItemLibrary()
        let first = library.add("First"), second = library.add("Second")
        var asked: Set<ItemID>?
        Browser.delete([first.id, second.id], in: library, undoManager: nil, asking: { asked = $0 })
        #expect(asked == [first.id, second.id])
        #expect(library.item(first.id)?.state == .active)

        asked = nil
        Browser.delete([first.id], in: library, undoManager: nil, asking: { asked = $0 })
        #expect(asked == nil)
        #expect(library.item(first.id)?.state == .trashed)
    }
}
