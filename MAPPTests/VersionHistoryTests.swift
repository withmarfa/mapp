import Foundation
import Synchronization
import Testing
@testable import MAPP

/// A history that answers from a list the test gives it, one answer for each request, and keeps what it was asked.
nonisolated final class FakeHistory: ItemHistorySource {
    private let answers: Mutex<[Result<ItemHistoryPage, ItemHistoryFailure>]>
    let cursors = Mutex<[String?]>([])

    init(_ answers: [Result<ItemHistoryPage, ItemHistoryFailure>]) {
        self.answers = Mutex(answers)
    }

    func set(_ next: [Result<ItemHistoryPage, ItemHistoryFailure>]) {
        answers.withLock { $0 = next }
    }

    func page(of id: ItemID, after cursor: String?, limit: Int) async throws(ItemHistoryFailure) -> ItemHistoryPage {
        cursors.withLock { $0.append(cursor) }
        let answer = answers.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        return try (answer ?? .success(ItemHistoryPage(snapshots: [], next: nil))).get()
    }
}

private func snapshot(
    _ version: Int, body: String? = "Old", title: String? = nil, type: TypeID = TypeChangeFixture.note
) -> ItemSnapshot {
    var properties: [String: PropertyValue] = [:]
    if let body { properties["body"] = .string(body) }
    if let title { properties["title"] = .string(title) }
    return ItemSnapshot(id: "v\(version)", version: version, type: type, properties: properties, written: nil, writer: nil)
}

private func page(_ versions: [Int], next: String? = nil) -> Result<ItemHistoryPage, ItemHistoryFailure> {
    .success(ItemHistoryPage(snapshots: versions.map { snapshot($0) }, next: next))
}

/// What the Version History sheet lists, and when a version can be put back.
@MainActor
@Suite struct VersionHistoryTests {
    private static let id = ItemID("launch")

    private func loaded(_ source: FakeHistory?) async -> ItemHistoryModel {
        let model = ItemHistoryModel(id: Self.id, source: source)
        model.load()
        _ = await eventually { model.phase != .loading }
        return model
    }

    @Test func versionsWithGapsAreListedOldestFirstAndNeverRepeated() async {
        let source = FakeHistory([page([7, 3], next: "a"), page([], next: "b"), page([7, 12], next: nil)])
        let model = await loaded(source)
        // An empty page with a cursor is followed without the person asking again.
        model.loadMore()
        _ = await eventually { !model.hasMore && !model.isLoadingMore }
        #expect(model.snapshots.map(\.version) == [3, 7, 12])
        #expect(source.cursors.withLock { $0 } == [nil, "a", "b"])
    }

    @Test func aLongHistoryIsReadOnePageAtATime() async {
        let source = FakeHistory([page([1, 2], next: "more")])
        let model = await loaded(source)
        #expect(model.hasMore)
        #expect(source.cursors.withLock { $0.count } == 1)

        source.set([page([3], next: nil)])
        model.loadMore()
        #expect(await eventually { !model.hasMore })
        #expect(model.snapshots.map(\.version) == [1, 2, 3])
    }

    @Test func aCursorThatLeadsBackToItselfEndsTheList() async {
        let source = FakeHistory([page([1], next: "a"), page([], next: "a")])
        let model = await loaded(source)
        model.loadMore()
        _ = await eventually { !model.isLoadingMore && !model.hasMore }
        #expect(!model.hasMore)
        #expect(model.snapshots.count == 1)
    }

    @Test func noServerOrNoPermissionIsSaidPlainlyAndCanBeTriedAgain() async {
        let source = FakeHistory([.failure(.unreachable)])
        let model = await loaded(source)
        #expect(model.phase == .failed(.unreachable))
        #expect(!ItemHistoryFailure.unreachable.message.isEmpty)

        source.set([.failure(.notPermitted)])
        model.load()
        #expect(await eventually { model.phase == .failed(.notPermitted) })

        source.set([page([4])])
        model.load()
        #expect(await eventually { model.phase == .loaded })
        #expect(model.snapshots.map(\.version) == [4])
    }

    @Test func aFailedLoadMoreKeepsTheVersionsAlreadyListed() async {
        let source = FakeHistory([page([1], next: "more")])
        let model = await loaded(source)
        source.set([.failure(.unreachable)])
        model.loadMore()
        #expect(await eventually { model.moreFailure == .unreachable })
        #expect(model.snapshots.count == 1)
        #expect(model.phase == .loaded)
    }

    @Test func aLibraryWithNoHistoryHasNothingToLoad() async {
        let model = await loaded(nil)
        #expect(model.phase == .failed(.unsupported))
    }

    @Test func aLongTextIsCutForReadingAndSaysHowMuch() {
        let excerpt = TextExcerpt(String(repeating: "a", count: 25), limit: 10)
        #expect(excerpt.text.count == 10)
        #expect(excerpt.omitted == 15)
    }

    // MARK: Whether a version can be put back

    @Test func restoreIsOfferedOnlyWhereTheVersionDiffersAndTheItemCanTakeIt() {
        let library = FakeItemLibrary(items: [])
        library.catalogue = TypeChangeFixture.catalogue
        let note = library.add("Agenda")
        let deleted = library.add("Gone", state: .trashed)

        #expect(library.restoreCheck(of: snapshot(1, body: "Agenda"), for: note.id) == .unchanged)
        #expect(library.restoreCheck(of: snapshot(1, body: "Old"), for: note.id) == .ready(RestorePlan(text: "Old")))
        // Recently Deleted is for reading only.
        if case .unavailable = library.restoreCheck(of: snapshot(1), for: deleted.id) {} else { Issue.record("restorable in the bin") }
        // A version of a kind with no text or title MAPP edits can be read, not restored.
        let unknown = snapshot(1, body: nil, type: TypeID("elsewhere.kind"))
        if case .unavailable = library.restoreCheck(of: unknown, for: note.id) {} else { Issue.record("restorable without text") }
        // An item deleted elsewhere while the sheet was open.
        if case .unavailable = library.restoreCheck(of: snapshot(1), for: ItemID("missing")) {} else { Issue.record("restorable when gone") }
    }

    @Test func restoringFromTheFakeLibraryChangesTheTextOnce() {
        let library = FakeItemLibrary(items: [])
        library.catalogue = TypeChangeFixture.catalogue
        let note = library.add("Agenda")
        #expect(library.restoreVersion(snapshot(1, body: "Old"), of: note.id, undoManager: nil))
        #expect(library.body(of: note.id)?.text == "Old")
        // The version now current is not written again.
        #expect(library.restoreVersion(snapshot(1, body: "Old"), of: note.id, undoManager: nil))
        #expect(library.restored.count == 1)
    }
}

/// Restoring a version through `MarfaLibrary`: the edit it sends, its undo, and what it refuses.
@MainActor
@Suite struct MarfaRestoreTests {
    typealias F = TypeChangeFixture
    private static let launch = ItemID("launch")

    private static func note(title: String, version: Int64 = 1) -> MAPP.Item {
        let date = Date(timeIntervalSince1970: 1_000_000)
        return MAPP.Item(
            id: launch, type: F.note, title: title, titleRule: .property("title"),
            properties: [Property(key: "title", value: .string(title))], version: ItemVersion(version), created: date, modified: date)
    }

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        source.setBody("Agenda", of: Self.launch)
        let library = MarfaLibrary(source: source, notices: Notices())
        library.handOverEdits = { $0(true) }
        source.send(.loaded(SourceSnapshot(items: [Self.note(title: "Launch")], catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private let earlier = snapshot(1, body: "Old agenda", title: "Old launch")

    @Test func restoringSendsTheTextAndTitleAsNewEditsOnTheCurrentVersion() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        #expect(library.restoreVersion(earlier, of: Self.launch, undoManager: undo))
        #expect(undo.undoActionName == String(localized: "Restore Version"))
        guard case .editBody(Self.launch, "Old agenda", let base, _)? = source.writes.first(where: { if case .editBody = $0 { true } else { false } })
        else { Issue.record("no text edit"); return }
        #expect(base == ItemVersion(1))
        #expect(source.writes.contains(.editProperties(Self.launch, ["title": .string("Old launch")], base: ItemVersion(1), undoing: nil)))
    }

    @Test func undoPutsBackWhatWasReplacedOnlyWhileItIsUnchanged() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.restoreVersion(earlier, of: Self.launch, undoManager: undo)
        source.setBody("Old agenda", of: Self.launch, version: 3)
        source.send(.upserted([Self.note(title: "Old launch", version: 3)]))
        try #require(await eventually { library.item(Self.launch)?.title == "Old launch" })

        undo.undo()
        #expect(source.writes.contains { if case .editBody(_, "Agenda", _, _) = $0 { true } else { false } })

        // Typed over meanwhile, so Undo says so rather than replace it.
        let (second, other) = try await loaded()
        let again = UndoManager()
        second.restoreVersion(earlier, of: Self.launch, undoManager: again)
        for write in other.submitted { other.send(.answered(write.id, .accepted)) }
        let before = other.writes.count
        other.setBody("Typed since", of: Self.launch, version: 3)
        other.send(.upserted([Self.note(title: "Old launch", version: 3)]))
        try #require(await eventually { second.body(of: Self.launch)?.text == "Typed since" })
        try #require(await eventually { second.item(Self.launch)?.title == "Old launch" })
        again.undo()
        // The title is still what the restore made it, so it alone is put back; the typed text is left, and told.
        try #require(await eventuallyAsking {
            other.writes.dropFirst(before).contains { if case .editProperties(_, let changes, _, _) = $0 { changes["title"] == .string("Launch") } else { false } }
        })
        #expect(!other.writes.dropFirst(before).contains { if case .editBody = $0 { true } else { false } })
        #expect(second.notices.waiting.last?.title == String(localized: "Can’t Restore Version"))
    }

    @Test func aVersionTheItemAlreadyHoldsIsNotWrittenAgain() async throws {
        let (library, source) = try await loaded()
        #expect(library.restoreVersion(snapshot(1, body: "Agenda", title: "Launch"), of: Self.launch, undoManager: nil))
        #expect(source.writes.isEmpty)
    }

    @Test func anItemDeletedElsewhereRefusesTheRestoreWithTheNoticeAndKeepsItsText() async throws {
        let (library, source) = try await loaded()
        source.send(.removed([Self.launch]))
        try #require(await eventually { library.item(Self.launch) == nil })
        #expect(!library.restoreVersion(earlier, of: Self.launch, undoManager: nil))
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Restore Version"))
        #expect(source.writes.isEmpty)
    }
}
