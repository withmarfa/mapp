import Foundation
import Testing
@testable import MarfaMac

@Suite struct PageNoticeTests {
    private static let copy = ItemID("10000000-0000-0000-0000-000000000009")

    private static func item(_ change: (inout Item) -> Void = { _ in }) -> Item {
        var item = Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID("core.note"), title: "Kiln log",
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
        let kind: PageNotice.Kind?
        var action: PageNotice.Action?
    }

    @Test func eachStateGivesItsNotice() {
        let tooLarge = SyncProblem(code: "over_request_limit", unsent: .tooLarge(size: 1_111_069, limit: 1_048_576))
        let rows = [
            Row(state: "an ordinary item", item: Self.item(), kind: nil),
            Row(state: "deleted", item: Self.item { $0.state = .trashed }, kind: .deleted, action: .recover),
            Row(
                state: "deleted and unreadable", item: Self.item { $0.state = .trashed; $0.problem = ItemProblem(message: "x", withholdsText: true) },
                kind: .deleted, action: .recover),
            Row(
                state: "a copy saved beside it", item: Self.item { $0.sync = .conflicted(sibling: Self.copy, fields: []) },
                kind: .copySaved, action: .openCopy(Self.copy)),
            Row(state: "a conflict whose copy is not read yet", item: Self.item { $0.sync = .conflicted(sibling: nil, fields: []) }, kind: nil),
            Row(state: "text that cannot be read", item: Self.item { $0.problem = ItemProblem(message: "x", withholdsText: true) }, kind: .unreadable),
            Row(state: "a write held for its size", item: Self.item { $0.sync = .blocked(tooLarge) }, kind: .held),
            Row(state: "a write the server refused", item: Self.item { $0.sync = .refused(SyncProblem(code: "invalid", message: "No.")) }, kind: .held),
            Row(
                state: "a refused key, which the connection says",
                item: Self.item { $0.sync = .blocked(SyncProblem(code: BlockedReason.credentialRefused.rawValue)) }, kind: nil),
            Row(state: "writes on their way", item: Self.item { $0.sync = .waiting(writes: 2) }, kind: nil),
            Row(state: "values that could not be read", item: Self.item { $0.problem = ItemProblem(message: "x") }, kind: .syncProblem),
            Row(state: "a missing file", item: Self.item(), fileIsMissing: true, kind: .fileMissing),
            Row(state: "pictures not loaded", item: Self.item(), waitingPictures: 2, kind: .picturesWaiting, action: .loadPictures),
            Row(
                state: "a held write and pictures not loaded", item: Self.item { $0.sync = .blocked(tooLarge) }, waitingPictures: 2,
                kind: .held),
        ]
        for row in rows {
            let notice = PageNotice.of(row.item, fileIsMissing: row.fileIsMissing, waitingPictures: row.waitingPictures)
            #expect(notice?.kind == row.kind, "\(row.state)")
            #expect(notice?.action == row.action, "\(row.state)")
            #expect(notice.map { !$0.words.isEmpty } ?? true, "\(row.state)")
        }
    }
}
