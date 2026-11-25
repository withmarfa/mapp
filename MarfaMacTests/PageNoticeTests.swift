import Foundation
import Marfa
import Testing
@testable import MarfaMac

private typealias Item = MarfaMac.Item

@Suite struct PageNoticeTests {
    private static let copy = ItemID("10000000-0000-0000-0000-000000000009")
    private static let id = ItemID("10000000-0000-0000-0000-000000000001")
    private static let tooLarge = SyncProblem(code: "over_request_limit", unsent: .tooLarge(size: 1_111_069, limit: 1_048_576))
    private static let refusal = SyncProblem(code: "invalid", message: "No.")
    private static let unreadable = ItemProblem(message: "Why.", withholdsText: true)

    private static func item(_ change: (inout Item) -> Void = { _ in }) -> Item {
        var item = Item(
            id: id, type: TypeID("core.note"), title: "Kiln log",
            titleRule: .property("title"), version: ItemVersion(1), created: Date(timeIntervalSince1970: 0),
            modified: Date(timeIntervalSince1970: 0))
        change(&item)
        return item
    }

    private struct Row {
        let state: String
        let item: Item
        var fileIsMissing = false
        var waitingPictures = 0
        let kinds: [PageNotice.Kind]
        var actions: [PageNotice.Action?] = []
    }

    @Test func eachStateGivesItsLines() {
        let rows = [
            Row(state: "an ordinary item", item: Self.item(), kinds: []),
            Row(state: "deleted", item: Self.item { $0.state = .trashed }, kinds: [.deleted], actions: [.recover]),
            Row(
                state: "a copy saved beside it", item: Self.item { $0.sync = .conflicted(sibling: Self.copy, fields: []) },
                kinds: [.copySaved], actions: [.openCopy(Self.copy)]),
            Row(state: "a conflict whose copy is not read yet", item: Self.item { $0.sync = .conflicted(sibling: nil, fields: []) }, kinds: []),
            Row(state: "text that cannot be read", item: Self.item { $0.problem = Self.unreadable }, kinds: [.unreadable]),
            Row(state: "values that could not be read", item: Self.item { $0.problem = ItemProblem(message: "x") }, kinds: [.syncProblem]),
            Row(state: "a write held for its size", item: Self.item { $0.sync = .blocked(Self.tooLarge) }, kinds: [.held], actions: [.showChanges]),
            Row(state: "a write the server refused", item: Self.item { $0.sync = .refused(Self.refusal) }, kinds: [.held], actions: [nil]),
            Row(
                state: "a refused key with no detail",
                item: Self.item { $0.sync = .blocked(SyncProblem(code: BlockedReason.credentialRefused.rawValue)) }, kinds: [.held],
                actions: [nil]),
            Row(state: "writes on their way", item: Self.item { $0.sync = .waiting(writes: 2) }, kinds: []),
            Row(state: "a missing file", item: Self.item(), fileIsMissing: true, kinds: [.fileMissing]),
            Row(state: "pictures not loaded", item: Self.item(), waitingPictures: 2, kinds: [.picturesWaiting], actions: [.loadPictures]),
            // Each pair: neither hides the other.
            Row(
                state: "deleted and unreadable", item: Self.item { $0.state = .trashed; $0.problem = Self.unreadable },
                kinds: [.deleted, .unreadable]),
            Row(
                state: "deleted with a write held", item: Self.item { $0.state = .trashed; $0.sync = .blocked(Self.tooLarge) },
                kinds: [.deleted, .held]),
            Row(
                state: "unreadable with a write held", item: Self.item { $0.problem = Self.unreadable; $0.sync = .refused(Self.refusal) },
                kinds: [.unreadable, .held]),
            Row(state: "deleted and its file missing", item: Self.item { $0.state = .trashed }, fileIsMissing: true, kinds: [.deleted, .fileMissing]),
            Row(
                state: "a write held and its file missing", item: Self.item { $0.sync = .refused(Self.refusal) }, fileIsMissing: true,
                kinds: [.held, .fileMissing]),
            Row(
                state: "unreadable and its file missing", item: Self.item { $0.problem = Self.unreadable }, fileIsMissing: true,
                kinds: [.unreadable, .fileMissing]),
            Row(state: "a held write and pictures not loaded", item: Self.item { $0.sync = .blocked(Self.tooLarge) }, waitingPictures: 2, kinds: [.held]),
            Row(
                state: "values unread with a file missing", item: Self.item { $0.problem = ItemProblem(message: "x") }, fileIsMissing: true,
                kinds: [.syncProblem, .fileMissing]),
        ]
        for row in rows {
            let notices = PageNotice.all(for: row.item, fileIsMissing: row.fileIsMissing, waitingPictures: row.waitingPictures)
            #expect(notices.map(\.kind) == row.kinds, "\(row.state)")
            if !row.actions.isEmpty { #expect(notices.map(\.action) == row.actions, "\(row.state)") }
            #expect(notices.allSatisfy { !$0.words.isEmpty && $0.item == Self.id }, "\(row.state)")
        }
    }

    @Test func aWriteTooLargeSaysWhereTheLatestChangesAre() throws {
        let item = Self.item { $0.sync = .blocked(Self.tooLarge) }
        let words = try #require(PageNotice.all(for: item).first?.words)
        #expect(words.contains("too large to save to Marfa"))
        #expect(words.contains("where you can copy them"))
        #expect(!words.contains("Make it smaller"))
        #expect(PageNotice.all(for: item).first?.actionLabel == "Show Changes")
    }

    /// A block outranks a refusal in the queue's one state per item, which must not hide where the oversized text is.
    @Test func aBlockedWriteBesideAnOversizedOneStillOffersShowChanges() throws {
        let oversized = Refusal(
            reason: "Too big.", requestLimit: RequestLimit(size: 1_111_069, limit: 1_048_576))
        let queue = [
            QueuedWrite(
                id: "1", kind: .updateItem, itemId: Self.id.rawValue, idempotencyKey: "1", verdict: .refused(oversized),
                queuedAt: "2026-10-06T00:00:00Z"),
            QueuedWrite(
                id: "2", kind: .updateItem, itemId: Self.id.rawValue, idempotencyKey: "2",
                verdict: .blocked(reason: .credentialRefused), queuedAt: "2026-10-06T00:00:01Z")
        ]
        let state = try #require(MarfaMapping.syncStates(queue: queue)[Self.id])
        guard case .blocked(let problem) = state else {
            Issue.record("the block ranks first")
            return
        }
        #expect(problem.unsent == nil)
        let notice = try #require(PageNotice.all(for: Self.item { $0.sync = state }).first)
        #expect(notice.action == .showChanges)
        #expect(notice.words.contains("where you can copy them"))
        // Alone, the same block offers nothing to show.
        let alone = try #require(MarfaMapping.syncStates(queue: [queue[1]])[Self.id])
        #expect(PageNotice.all(for: Self.item { $0.sync = alone }).first?.action == nil)
    }

    @Test func aDeletedItemWhoseTextCannotBeReadKeepsItsReason() {
        let item = Self.item { $0.state = .trashed; $0.problem = Self.unreadable }
        #expect(PageNotice.all(for: item).compactMap(\.reason) == ["Why."])
    }
}
