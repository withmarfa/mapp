import Foundation
import Marfa
import struct MarfaCore.Item
import enum MarfaCore.ItemState
import enum MarfaCore.Tier
import enum MarfaCore.JsonValue
import Testing
@testable import MAPP

struct MarfaProblemsTests {
    private static let catalogue = MarfaMapping.catalogue(
        itemTypes: [
            ItemType(
                id: "core.task", label: "Task",
                fields: [
                    TypeField(name: "title", type: "string", declaredBy: "core.task"),
                    TypeField(name: "body", type: "string", declaredBy: "core.task"),
                    TypeField(name: "status", type: "enum", declaredBy: "core.task"),
                    TypeField(name: "due_at", type: "datetime", declaredBy: "core.task")
                ],
                titleField: "title", bodyField: "body"),
            ItemType(id: "core.entity", label: "Entity", titleField: "name"),
            ItemType(id: "system.folder", label: "Folder", fields: [TypeField(name: "title", type: "string", declaredBy: "system.folder")])
        ],
        edgeTypes: [])

    private static func write(
        _ id: String, _ verdict: Verdict? = nil, kind: WriteKind = .updateItem, on item: String? = "item",
        body: JSONObject = [:], dependsOn: [String] = [], at time: String = "2026-10-06T10:00:00Z"
    ) -> QueuedWrite {
        QueuedWrite(
            id: id, kind: kind, itemId: item, idempotencyKey: id, dependsOn: dependsOn, verdict: verdict, body: body,
            queuedAt: time)
    }

    private static let task: JSONObject = [
        "type": "core.task", "id": "item", "tier": "library",
        "properties": ["title": "Plan the launch", "body": "Line one\nLine two", "status": "done", "due_at": .null]
    ]

    private static func report(_ queue: [QueuedWrite], kept: [QueuedWrite] = [], types: [String: TypeID] = [:])
        -> SyncReport
    {
        MarfaProblems.report(queue: queue, kept: kept, catalogue: catalogue, types: types)
    }

    @Test func aRefusalKeepsWhatThePersonWroteAndItsReasons() throws {
        let refusal = Refusal(
            reason: "validation_error", code: "validation_error", message: "Some values are not allowed.",
            fields: [FieldRefusal(field: "status", message: "not one of open, closed")], trashed: true)
        let report = Self.report([Self.write("w1", .refused(refusal), kind: .createItem, body: Self.task)])
        let entry = try #require(report.problems.first)
        #expect(entry.id == .write("w1"))
        #expect(entry.itemID == ItemID("item"))
        #expect(entry.kind == .refused)
        #expect(entry.change == .create)
        #expect(entry.reason?.code == "validation_error")
        #expect(entry.reason?.message == "Some values are not allowed.")
        #expect(entry.reason?.fields == ["status": "not one of open, closed"])
        #expect(entry.reason?.isTrashed == true)
        #expect(entry.actions == [.discard])
        #expect(entry.content.title == "Plan the launch")
        #expect(entry.content.body == "Line one\nLine two")
        #expect(entry.content.properties == [SyncContent.Line(label: "Status", value: "done")])
        #expect(entry.copyText == "Plan the launch\n\nLine one\nLine two\n\nStatus: done")
        #expect(report.waiting == 0)
        #expect(report.changesNotSent == 1)
    }

    @Test func aMissingGrantIsReadIntoTheRefusal() throws {
        let refusal = Refusal(
            reason: "forbidden", code: "forbidden", grant: MissingGrant(kind: .type, name: "core.task", level: .write))
        let report = Self.report([Self.write("w1", .blocked(reason: .credentialRefused, refusal: refusal), body: Self.task)])
        let entry = try #require(report.problems.first)
        #expect(entry.kind == .blocked(.credentialRefused))
        #expect(entry.reason?.code == "credential_refused")
        #expect(entry.reason?.grant == SyncProblem.Grant(kind: .type, name: "core.task", level: .write))
        // The next drain sends it again once the grant returns.
        #expect(entry.actions.isEmpty)
    }

    @Test func eachBlockedReasonOffersWhatTheContractAllows() {
        let cases: [(Marfa.BlockedReason, SyncProblemEntry.Kind, [SyncAction])] = [
            (.keySpent, .blocked(.keySpent), [.tryAgain]),
            (.ancestorUnavailable, .blocked(.ancestorUnavailable), [.withdraw]),
            (.conflictUnresolved, .blocked(.conflictUnresolved), [.withdraw]),
            (.failingAlone, .blocked(.failingAlone), [.tryAgain, .withdraw])
        ]
        for (reason, kind, actions) in cases {
            let report = Self.report([Self.write("w", .blocked(reason: reason))])
            #expect(report.problems.map(\.kind) == [kind])
            #expect(report.problems.first?.actions == actions)
            #expect(report.problems.first?.reason?.code == MarfaMapping.blockedReason(reason).rawValue)
        }
        let dead = Self.report([Self.write("w", .dead)])
        #expect(dead.problems.map(\.kind) == [.dead])
        #expect(dead.problems.first?.actions == [.tryAgain])
        #expect(dead.problems.first?.reason?.code == "dead")
    }

    /// A refused key parks the whole queue, which the connection reports once; each write still waits.
    @Test func writesParkedForARefusedKeyStillWait() {
        let report = Self.report([
            Self.write("1", .blocked(reason: .credentialRefused), at: "2026-10-06T09:00:00Z"),
            Self.write("2", at: "2026-10-06T11:00:00Z"),
            Self.write("3", at: "2026-10-06T10:00:00Z"),
            Self.write("4", .accepted), Self.write("5", .merged(fields: ["body"]))
        ])
        #expect(report.problems.isEmpty)
        #expect(report.waiting == 3)
        #expect(report.oldestWaiting == MarfaMapping.date("2026-10-06T09:00:00Z"))
        #expect(report.changesNotSent == 3)
        #expect(report.queueRead)
    }

    @Test func aPropertyEditShowsTheValuesItWrote() throws {
        let body: JSONObject = ["properties": ["status": "open", "due_at": "2026-10-07"], "version": 3]
        let report = Self.report(
            [Self.write("w", .refused(Refusal(reason: "x", code: "x")), body: body)], types: ["item": TypeID("core.task")])
        let entry = try #require(report.problems.first)
        #expect(entry.change == .edit)
        #expect(entry.content.title == nil)
        #expect(entry.content.properties == [
            SyncContent.Line(label: "Status", value: "open"), SyncContent.Line(label: "Due at", value: "2026-10-07")
        ])
        #expect(entry.copyText == "Status: open\nDue at: 2026-10-07")
    }

    @Test func titleAndBodyFollowTheType() {
        let entity = MarfaProblems.content(
            of: ["type": "core.entity", "properties": ["name": "Ada", "role": "Engineer"]], type: TypeID("core.entity"),
            catalogue: Self.catalogue)
        #expect(entity.title == "Ada")
        #expect(entity.body == nil)
        #expect(entity.properties == [SyncContent.Line(label: "Role", value: "Engineer")])
        // A type with neither hint is read under the `title` it declares.
        let folder = MarfaProblems.content(
            of: ["properties": ["title": "Archive"]], type: TypeID("system.folder"), catalogue: Self.catalogue)
        #expect(folder.title == "Archive")
        let unknown = MarfaProblems.content(
            of: ["properties": ["title": "T", "body": "B", "flag": true, "count": 2, "list": ["a", "b"]]], type: nil,
            catalogue: Self.catalogue)
        #expect(unknown.plainText == "T\n\nB\n\nCount: 2\nFlag: true\nList: a, b")
    }

    @Test func aTagWriteShowsItsTags() throws {
        let report = Self.report([Self.write("w", .dead, kind: .addTag, body: ["tags": ["favorite"]])])
        let entry = try #require(report.problems.first)
        #expect(entry.change == .tag)
        #expect(entry.content.tags == ["favorite"])
        #expect(entry.copyText == "Tags: favorite")
    }

    /// A write the queue refused only because the create it waited on was refused, or died, goes with it.
    @Test func writesRefusedForAnotherAreShownWithIt() throws {
        let server = Refusal(reason: "type_not_permitted", code: "type_not_permitted")
        let unsent = Refusal(reason: "the create_item it waits for was refused")
        let report = Self.report([
            Self.write("create", .refused(server), kind: .createItem, body: Self.task, at: "2026-10-06T08:00:00Z"),
            Self.write("tag", .refused(unsent), kind: .addTag, body: ["tags": ["x"]], dependsOn: ["create"]),
            Self.write("edit", .refused(unsent), dependsOn: ["tag"]),
            Self.write("dead", .dead, kind: .createItem, on: "other", at: "2026-10-06T09:00:00Z"),
            Self.write("behind", .refused(unsent), kind: .addTag, on: "other", dependsOn: ["dead"]),
            Self.write("lone", .refused(unsent), kind: .addTag, on: "third", dependsOn: ["forgotten"], at: "2026-10-06T12:00:00Z")
        ])
        #expect(report.problems.map(\.id) == [.write("create"), .write("dead"), .write("lone")])
        #expect(report.problems[0].dependents.sorted() == ["edit", "tag"])
        #expect(report.problems[1].dependents == ["behind"])
        #expect(report.problems[2].dependents.isEmpty)
        #expect(report.problems[2].actions == [.discard])
    }

    /// Each later write's values win, field by field, as the queue would have sent them.
    @Test func whatWasTypedAfterARefusedCreateIsPartOfIt() throws {
        let server = Refusal(reason: "type_not_permitted", code: "type_not_permitted")
        let unsent = Refusal(reason: "the create_item it waits for was refused")
        let report = Self.report([
            Self.write("create", .refused(server), kind: .createItem, body: [
                "type": "core.task", "id": "item", "properties": ["title": "Plan", "body": "First words", "status": "open"]
            ], at: "2026-10-06T08:00:00Z"),
            Self.write("edit", .refused(unsent), body: [
                "properties": ["body": "First words, then everything typed after"], "version": 0
            ], dependsOn: ["create"], at: "2026-10-06T08:01:00Z"),
            Self.write("later", .refused(unsent), body: ["properties": ["status": "done"], "version": 0],
                dependsOn: ["create"], at: "2026-10-06T08:02:00Z"),
            Self.write("tag", .refused(unsent), kind: .addTag, body: ["tags": ["favorite"]], dependsOn: ["create"],
                at: "2026-10-06T08:03:00Z")
        ])
        let entry = try #require(report.problems.first)
        #expect(report.problems.count == 1)
        #expect(entry.copyText == "Plan\n\nFirst words, then everything typed after\n\nStatus: done\nTags: favorite")
    }

    @Test func refusalsTheQueueForgotAreKept() {
        let refusal = Refusal(reason: "item_not_found", code: "item_not_found", trashed: true)
        let forgotten = Self.write("gone", .refused(refusal), kind: .addTag, body: ["tags": ["a"]])
        let queued = Self.write("held", .refused(refusal), kind: .createItem, body: Self.task)
        let report = Self.report([queued], kept: [forgotten, queued])
        #expect(report.problems.count == 2)
        #expect(Set(report.problems.map(\.id)) == [.write("gone"), .write("held")])
    }

    @Test func aConflictedCopyIsShownWithTheItemItCameFrom() throws {
        let row = Marfa.Item(
            id: "copy", type: "core.task", properties: ["title": "Plan", "body": "Their words"], state: .active,
            tier: .library, version: 1, schemaVersion: 1, source: "test", sourceId: nil,
            occurredAt: "2026-10-06T10:00:00Z", createdAt: "2026-10-06T10:00:00Z", updatedAt: "2026-10-06T10:00:00Z",
            tags: [MarfaProblems.conflictedCopyTag, "work"])
        let report = MarfaProblems.report(
            queue: [Self.write("w")],
            conflictedCopies: [MarfaProblems.ConflictedCopy(row: row, original: ItemID("original"))],
            catalogue: Self.catalogue)
        let entry = try #require(report.problems.first)
        #expect(entry.id == .conflictedCopy(ItemID("copy")))
        #expect(entry.kind == .conflicted(sibling: ItemID("copy"), original: ItemID("original")))
        #expect(entry.actions == [.keep, .discard])
        #expect(entry.reason == nil)
        #expect(entry.copyText == "Plan\n\nTheir words")
        // The copy is on the server already, so leaving the copy loses only the write still waiting.
        #expect(report.changesNotSent == 1)
    }

    @Test func problemsAreOldestFirst() {
        let refusal = Refusal(reason: "x", code: "x")
        let report = Self.report([
            Self.write("late", .refused(refusal), at: "2026-10-06T12:00:00Z"),
            Self.write("early", .dead, at: "2026-10-06T08:00:00Z")
        ])
        #expect(report.problems.map(\.id) == [.write("early"), .write("late")])
    }
}

/// What the person wrote in the writes that would be lost with a copy.
struct UnsentTextsTests {
    private static let catalogue = MarfaMapping.catalogue(
        itemTypes: [
            ItemType(
                id: "core.note", label: "Note",
                fields: [
                    TypeField(name: "title", type: "string", declaredBy: "core.note"),
                    TypeField(name: "body", type: "string", declaredBy: "core.note")
                ],
                titleField: "title", bodyField: "body")
        ],
        edgeTypes: [])

    private static func write(
        _ id: String, _ verdict: Verdict? = nil, kind: WriteKind = .updateItem, body: JSONObject = [:], at time: String
    ) -> QueuedWrite {
        QueuedWrite(
            id: id, kind: kind, itemId: "item", idempotencyKey: id, dependsOn: [], verdict: verdict, body: body, queuedAt: time)
    }

    @Test func eachWriteNotSentThatCarriedTextIsShownOldestFirst() {
        let queue = [
            Self.write("late", kind: .updateItem, body: ["properties": ["body": "Second thought"]], at: "2026-10-06T10:05:00Z"),
            Self.write(
                "early", kind: .createItem, body: ["type": "core.note", "properties": ["title": "Trip", "body": "Book the hotel"]],
                at: "2026-10-06T10:00:00Z"),
            Self.write("taken", .accepted, body: ["properties": ["body": "Already on the server"]], at: "2026-10-06T10:01:00Z"),
            Self.write("tag", kind: .addTag, body: ["tags": ["favorite"]], at: "2026-10-06T10:02:00Z")
        ]
        let texts = MarfaProblems.unsentTexts(queue, catalogue: Self.catalogue, types: ["item": TypeID("core.note")])
        #expect(texts.map(\.id) == ["early", "late"])
        #expect(texts.map(\.change) == [.create, .edit])
        #expect(texts.map(\.content.plainText) == ["Trip\n\nBook the hotel", "Second thought"])
    }

    @Test func aRefusedWriteIsStillNotSentAndItsTextStillShown() {
        let refused = Self.write(
            "refused", .refused(Refusal(reason: "validation_error")), body: ["properties": ["body": "Kept"]], at: "2026-10-06T10:00:00Z")
        let texts = MarfaProblems.unsentTexts([refused], catalogue: Self.catalogue, types: ["item": TypeID("core.note")])
        #expect(texts.map(\.id) == ["refused"])
    }

    @Test func aWriteWithNothingWrittenInItShowsNothing() {
        let empty = Self.write("empty", body: ["properties": ["body": .null]], at: "2026-10-06T10:00:00Z")
        #expect(MarfaProblems.unsentTexts([empty], catalogue: Self.catalogue).isEmpty)
    }

    @Test func whatIsShownDoesNotChangeWhatTheyAgreedTo() {
        #expect(UnsentWrites(ids: ["a"], texts: []) == UnsentWrites(ids: ["a"]))
        #expect(UnsentWrites(ids: ["a"]) != UnsentWrites(ids: ["a", "b"]))
    }
}
