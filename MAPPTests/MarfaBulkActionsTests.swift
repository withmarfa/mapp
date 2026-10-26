import Foundation
import Testing
@testable import MAPP

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

    @Test func aBatchIsOneUndoStep() async throws {
        let (library, _) = try await loaded([Self.note(a), Self.note(b)])
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        library.changeType([a, b], to: F.task, filling: [:], undoManager: undo)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == String(localized: "Change Type"))
        undo.undo()
        #expect(!undo.canUndo)
        #expect(undo.canRedo)
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
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        library.changeType(Set(items.map(\.id)), to: F.task, filling: [:], undoManager: undo)
        undo.endUndoGrouping()
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
