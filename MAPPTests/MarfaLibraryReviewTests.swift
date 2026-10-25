import Foundation
import Marfa
import struct MarfaCore.Item
import enum MarfaCore.JsonValue
import Observation
import Synchronization
import Testing
@testable import MAPP

/// Reviewer's adversarial tests for the Marfa library. Each states what should hold.
@MainActor
@Suite struct MarfaLibraryReviewFakeTests {
    typealias F = LibraryFixture

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for (id, text) in F.texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source)
        source.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    /// Contract queue-and-verdicts 43: the next edit is based on the version the copy holds, with the earlier one
    /// laid over it; a second edit said to be read from the same version comes back conflicted against the same
    /// person's earlier save.
    @Test func aSecondEditAfterTheCopyMovedIsBasedOnTheVersionTheCopyHolds() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "A")
        // The copy took the first edit's answer and moved to version 2, which the library hears before the answer.
        var moved = try #require(library.item(F.n1))
        moved.version = ItemVersion(2)
        source.setBody("A", of: F.n1, version: 2)
        source.send(.upserted([moved]))
        #expect(await eventually { library.item(F.n1)?.version == ItemVersion(2) })
        library.updateBody(of: F.n1, to: "AB")
        let second = try #require(source.writes.last)
        guard case .editBody(_, _, let base, let merge) = second else { Issue.record("not a body edit"); return }
        #expect(
            base == ItemVersion(2) || merge != .asRead,
            "second edit sent as read at \(base.rawValue) while the library holds the item at 2")
    }

    /// A conflicted answer, where the server kept its own text, changes what `body(of:)` says without changing the
    /// version. The page follows `body(of:)` as well as the version (NotePage), so it shows the server's text, the
    /// item says the person's went to a copy, and the next save starts from the server's text at the version the
    /// copy holds rather than being merged as read over it.
    @Test func aConflictShowsTheServersTextAndTheNextSaveStartsFromIt() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Mine")
        let write = try #require(source.submitted.last?.id)
        // Another device's edit arrives first, at version 5.
        var theirs = try #require(library.item(F.n1))
        theirs.version = ItemVersion(5)
        source.setBody("Theirs", of: F.n1, version: 5)
        source.send(.upserted([theirs]))
        #expect(await eventually { library.item(F.n1)?.version == ItemVersion(5) })
        #expect(library.body(of: F.n1)?.text == "Mine")
        let page = observes { _ = library.body(of: F.n1) }
        // The server keeps its own text and puts the person's on a copy; the row's version does not move.
        var conflicted = try #require(library.item(F.n1))
        conflicted.sync = .conflicted(sibling: F.n2, fields: ["body"])
        source.send(.answered(write, .conflicted(sibling: F.n2, fields: ["body"])))
        source.send(.upserted([conflicted]))
        #expect(await eventually { library.body(of: F.n1)?.text == "Theirs" })
        #expect(page.isSet, "the page is not told the text changed")
        #expect(library.body(of: F.n1)?.version == ItemVersion(5))
        #expect(await eventually { library.item(F.n1)?.sync == .conflicted(sibling: F.n2, fields: ["body"]) })
        // The page reloads to the server's text; the person's next save is based on it.
        library.updateBody(of: F.n1, to: "Theirs!")
        #expect(source.writes.last == .editBody(F.n1, "Theirs!", base: ItemVersion(5), merge: .asRead))
    }

    /// Replacing an end that holds one link would be two writes if it were a delete and a create, and when the
    /// create is refused the delete has already removed the old link. It is one move of the edge's end instead, so a
    /// refusal leaves the edge where it was.
    @Test func aReplacementIsOneMoveRatherThanTwoWrites() async throws {
        let (library, source) = try await loaded()
        #expect(library.setItemRelationship(F.e1, field: "child-of", targetIDs: [F.p2], undoManager: nil))
        #expect(source.writes == [.moveEdge(EdgeID("c1"), end: .source, to: F.p2)], "replacement sent as \(source.writes)")
        #expect(library.failure == nil)
    }

    /// Choosing one item in place of another on a field that holds many adds the new link first and removes the old
    /// one only once the new one is taken, so a refusal never leaves the field with neither.
    @Test func aRefusedLinkInAReplacementKeepsTheOldLink() async throws {
        let (library, source) = try await loaded()
        #expect(library.setItemRelationship(F.n1, field: "about", targetIDs: [F.p2], undoManager: nil))
        #expect(source.writes == [.link(EdgeDraft(type: "about", source: F.n1, target: F.p2), undoing: nil)])
        let link = try #require(source.submitted.last?.id)
        source.send(.answered(link, .refused(SyncProblem(code: "type_not_permitted", message: "Not permitted."))))
        #expect(await eventually { library.failure != nil })
        // Time for an unlink the refusal should not set off.
        try await Task.sleep(for: .milliseconds(200))
        #expect(!source.writes.contains(.unlink(EdgeID("a1"))), "sent \(source.writes)")
    }

    /// Queue-and-verdicts 43: text typed on version 1 but reported after the library took in another device's text
    /// at version 2 is sent as typed on version 1, so the server keeps both. The library goes on holding the other
    /// device's text, and what the person types on it next is the first save typed on version 2.
    @Test func anEditTypedBeforeAnotherDevicesTextIsSentAsTypedOnTheOlderVersion() async throws {
        let (library, source) = try await loaded()
        var theirs = try #require(library.item(F.n1))
        theirs.version = ItemVersion(2)
        source.setBody("Theirs", of: F.n1, version: 2)
        source.send(.upserted([theirs]))
        #expect(await eventually { library.body(of: F.n1)?.text == "Theirs" })
        library.updateBody(of: F.n1, to: "Note body, mine", readAt: ItemVersion(1))
        #expect(source.writes.last == .editBody(F.n1, "Note body, mine", base: ItemVersion(1), merge: .asRead))
        #expect(library.body(of: F.n1) == ItemBody(id: F.n1, text: "Theirs", version: ItemVersion(2)))
        library.updateBody(of: F.n1, to: "Theirs, mine", readAt: ItemVersion(2))
        #expect(source.writes.last == .editBody(F.n1, "Theirs, mine", base: ItemVersion(2), merge: .asRead))
    }

    /// A late report that continues the person's own saves follows them, so the source decides it against the
    /// person's own last edit rather than against the other device's text.
    @Test func aLateEditContinuingThePersonsOwnSavesFollowsThem() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Mine", readAt: ItemVersion(1))
        let write = try #require(source.submitted.last?.id)
        var theirs = try #require(library.item(F.n1))
        theirs.version = ItemVersion(3)
        source.setBody("Theirs", of: F.n1, version: 3)
        source.send(.answered(write, .accepted))
        source.send(.upserted([theirs]))
        #expect(await eventually { library.body(of: F.n1)?.text == "Theirs" })
        library.updateBody(of: F.n1, to: "Mine more", readAt: ItemVersion(1))
        #expect(source.writes.last == .editBody(F.n1, "Mine more", base: ItemVersion(1), merge: .following))
        #expect(library.body(of: F.n1)?.text == "Theirs")
    }

    /// A search that fails is not shown as a search that found nothing.
    @Test func aSearchThatFailsIsNotNothingFound() async throws {
        let source = FailingSearchSource()
        let library = MarfaLibrary(source: source)
        source.inner.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        _ = library.items(matching: "body")
        #expect(await eventually { library.failure != nil }, "a search that threw is shown as no results, and nothing says so")
        #expect(library.items(matching: "body").isEmpty)
    }
}

@MainActor
private func observes(_ read: () -> Void) -> LiveMarfa.Flag {
    let flag = LiveMarfa.Flag()
    withObservationTracking(read) { flag.set() }
    return flag
}

nonisolated final class FailingSearchSource: ItemSource {
    let inner = FakeItemSource()
    var embeds: any EmbedResolver { inner.embeds }
    var connectionState: MarfaConnectionState { inner.connectionState }
    func connectionStates() -> AsyncStream<MarfaConnectionState> { inner.connectionStates() }
    var syncReport: SyncReport { inner.syncReport }
    func syncReports() -> AsyncStream<SyncReport> { inner.syncReports() }
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool { false }
    func changes() -> AsyncStream<SourceChange> { inner.changes() }
    func submit(_ write: ItemWrite, as id: WriteID) -> Bool { inner.submit(write, as: id) }
    func body(of item: ItemID) async throws -> ItemBody { try await inner.body(of: item) }
    func bodies(of items: Set<ItemID>) async throws -> [ItemBody] { try await inner.bodies(of: items) }
    func fileURL(of item: ItemID) async throws -> URL { try await inner.fileURL(of: item) }
    func search(_ text: String, in query: ItemQuery) async throws -> [ItemID] {
        throw SourceFailure(kind: .failed, message: "fts5: syntax error")
    }
    func queueSubmitted() async {}
    func close() async {}
    func refresh() {}
    func tryKey(_ key: String) async throws -> MarfaSync.KeyCheck { .accepted }
    func unsentWrites() async -> UnsentWrites? { nil }
    func close(agreeing agreed: UnsentWrites?) async -> CloseOutcome { .closed }
}

extension LiveMarfaTests {
    /// Against the test instance.
    @MainActor
    @Suite(.serialized)
    struct MarfaLibraryReviewLiveTests {
        private func withLibrary(_ body: @MainActor (MarfaLibrary, MarfaSource, LiveMarfa.Made) async throws -> Void) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaLibraryReview-\(UUID().uuidString)", directoryHint: .isDirectory)
            let made = LiveMarfa.Made()
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let source = try await MarfaSource.open(
                connection, keys: MemoryKeyStore([connection: try LiveMarfa.key()]),
                location: MarfaStoreLocation(root: root))
            let library = MarfaLibrary(source: source)
            func end() async {
                await source.flush()
                // Conflicted copies the tests caused, found by their tag and the token in their title.
                for item in library.items(in: .allNotes) + library.items(in: .recentlyDeleted)
                where item.tags.contains(MarfaProblems.conflictedCopyTag) && item.title.hasPrefix("MAPPTEST review") {
                    made.add(item.id)
                }
                await source.close()
                await LiveMarfa.purge(made.ids)
                try? FileManager.default.removeItem(at: root)
            }
            do {
                source.refresh()
                try #require(await eventually {
                    library.isLoaded && library.connection == .online && library.count(in: .allNotes) > 100
                })
                try await body(library, source, made)
            } catch {
                await end()
                throw error
            }
            await end()
        }

        private func make(_ library: MarfaLibrary, _ source: MarfaSource, _ made: LiveMarfa.Made, _ token: String) async throws -> ItemID {
            let id = try #require(library.createItem(
                typeID: "core.note", title: "MAPPTEST review \(token)", body: "start", parentID: nil, in: .allNotes,
                undoManager: nil))
            made.add(id)
            await source.flush()
            try #require(await eventually {
                guard let item = library.item(id), let body = library.body(of: id) else { return false }
                return item.sync == .settled && item.version.rawValue > 0 && body.version == item.version
            })
            return id
        }

        private func conflicts(_ library: MarfaLibrary, _ id: ItemID, _ token: String) -> [String] {
            var found: [String] = []
            if case .conflicted = library.item(id)?.sync { found.append("item sync is conflicted") }
            for item in library.items(in: .allNotes)
            where item.tags.contains(MarfaProblems.conflictedCopyTag) && item.title.contains(token) {
                found.append("conflicted copy \(item.id.rawValue)")
            }
            return found
        }

        /// Another device writes the body through its own copy.
        private func otherDevice(_ id: ItemID, sets text: String) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaLibraryReview-other-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let address = try #require(URL(string: try LiveMarfa.address()))
            let other = try await WorkingCopy.open(
                store: root.appending(path: "other.sqlite"), server: Server(url: address, key: try LiveMarfa.key()))
            _ = try await other.hydrate(types: ["core.*"], tier: .library)
            let row = try #require(try await other.items.get(id.rawValue))
            _ = try await other.items.update(id.rawValue, Edit(properties: ["body": .string(text)], baseVersion: row.version))
            let report = try await other.queue.drain()
            await other.close()
            try #require(report.verdicts.allSatisfy { $0.verdict == .accepted }, "the other device's write: \(report.verdicts)")
        }

        /// Sends what waits and waits for the server's conflicted copy of the item, holding `text`, to reach the library.
        private func conflictedCopy(
            _ library: MarfaLibrary, _ source: MarfaSource, _ token: String, holding text: String
        ) async throws -> [MAPP.Item] {
            await source.flush()
            _ = await eventually {
                library.items(in: .allNotes).contains {
                    $0.tags.contains(MarfaProblems.conflictedCopyTag) && $0.title.contains(token)
                        && library.body(of: $0.id)?.text == text
                }
            }
            return library.items(in: .allNotes).filter {
                $0.tags.contains(MarfaProblems.conflictedCopyTag) && $0.title.contains(token)
            }
        }

        /// Sends what waits and waits until the copy holds `text` with nothing left to send. A drain's answers are
        /// taken before a flush returns, so a conflict would show by then.
        private func sent(_ library: MarfaLibrary, _ source: MarfaSource, _ id: ItemID, holding text: String) async throws {
            await source.flush()
            let held = try await eventuallyAsking {
                guard library.syncReport.waiting == 0 else { return false }
                return try await source.body(of: id).text == text
            }
            #expect(held)
        }

        /// The finding reproduced: the page reports typing made on "start" after the copy took in another device's
        /// "theirs". The server keeps "theirs" on the item and the person's text on a conflicted copy beside it.
        @Test(.timeLimit(.minutes(3)))
        func aLateReportAfterAnotherDevicesTextKeepsBoth() async throws {
            try await withLibrary { library, source, made in
                let token = "zl" + UUID().uuidString.prefix(8).lowercased()
                let id = try await make(library, source, made, token)
                let read = try #require(library.body(of: id)?.version)
                try await otherDevice(id, sets: "theirs")
                try #require(await eventually { library.body(of: id)?.text == "theirs" })
                library.updateBody(of: id, to: "start, mine", readAt: read)
                let copies = try await conflictedCopy(library, source, token, holding: "start, mine")
                let held = try await source.body(of: id).text
                Attachment.record("held: \(held)\ncopies: \(copies.map { library.body(of: $0.id)?.text ?? "" })", named: "LateReport.txt")
                #expect(held == "theirs")
                #expect(copies.count == 1)
                #expect(copies.first.flatMap { library.body(of: $0.id)?.text } == "start, mine")
            }
        }

        /// The person's first save is answered, another device's text comes in, and only then is their next save,
        /// which follows the first, queued. It is sent as typed on the version the first was made on, so the server
        /// keeps the other device's text and puts the person's on a conflicted copy, rather than writing it over.
        @Test(.timeLimit(.minutes(3)))
        func aFollowingSaveQueuedAfterAnotherDevicesTextDoesNotOverwriteIt() async throws {
            try await withLibrary { library, source, made in
                let token = "zf" + UUID().uuidString.prefix(8).lowercased()
                let id = try await make(library, source, made, token)
                let read = try #require(library.body(of: id)?.version)
                source.submit(.editBody(id, "start, one", base: read, merge: .asRead), as: WriteID())
                await source.flush()
                try #require(await eventually { library.item(id)?.sync == .settled })
                try await otherDevice(id, sets: "theirs")
                let caughtUp = await LiveMarfa.until { (try? await source.body(of: id).text) == "theirs" }
                try #require(caughtUp)
                source.submit(.editBody(id, "start, one, two", base: read, merge: .following), as: WriteID())
                let copies = try await conflictedCopy(library, source, token, holding: "start, one, two")
                let held = try await source.body(of: id).text
                Attachment.record("held: \(held)\ncopies: \(copies.map { library.body(of: $0.id)?.text ?? "" })", named: "Following.txt")
                #expect(held == "theirs")
                #expect(copies.compactMap { library.body(of: $0.id)?.text } == ["start, one, two"])
            }
        }

        /// The main actor is busy while the first save drains, as it is while a large list redraws; the person's
        /// second save must not come back conflicted against their own first.
        @Test(.timeLimit(.minutes(2)))
        func twoSavesWhileTheMainActorIsBusyDoNotConflict() async throws {
            try await withLibrary { library, source, made in
                let token = "zr" + UUID().uuidString.prefix(8).lowercased()
                let id = try await make(library, source, made, token)
                library.updateBody(of: id, to: "first edit")
                busy(seconds: 3)
                library.updateBody(of: id, to: "first edit, second edit")
                try await sent(library, source, id, holding: "first edit, second edit")
                let held = try await source.body(of: id).text
                let problems = conflicts(library, id, token)
                Attachment.record("copy holds: \(held)\nproblems: \(problems)\nfailure: \(String(describing: library.failure))", named: "Busy.txt")
                #expect(problems.isEmpty, "\(problems)")
                #expect(held == "first edit, second edit")
            }
        }

        /// Typing with short pauses, as the page reports edits.
        @Test(.timeLimit(.minutes(3)))
        func typingWithShortPausesNeverConflicts() async throws {
            try await withLibrary { library, source, made in
                let token = "zs" + UUID().uuidString.prefix(8).lowercased()
                let id = try await make(library, source, made, token)
                var text = "start"
                for index in 0..<30 {
                    text += " w\(index)"
                    library.updateBody(of: id, to: text)
                    // The pauses between the page's reports, which let earlier saves drain while later ones are typed.
                    try await Task.sleep(for: .milliseconds([40, 90, 150, 220][index % 4]))
                }
                try await sent(library, source, id, holding: text)
                let held = try await source.body(of: id).text
                let problems = conflicts(library, id, token)
                Attachment.record("copy holds: \(held)\nproblems: \(problems)\nfailure: \(String(describing: library.failure))", named: "Typing.txt")
                #expect(problems.isEmpty, "\(problems)")
                #expect(held == text)
                #expect(library.body(of: id)?.text == text)
            }
        }

        /// An item made in the Inbox stays in the Inbox once the server has it and the copy catches up.
        @Test(.timeLimit(.minutes(2)))
        func anItemMadeInTheInboxStays() async throws {
            try await withLibrary { library, source, made in
                let token = "zt" + UUID().uuidString.prefix(8).lowercased()
                let id = try #require(library.createItem(
                    typeID: "core.note", title: "MAPPTEST review \(token)", body: "captured", parentID: nil, in: .inbox,
                    undoManager: nil))
                made.add(id)
                #expect(await eventually { library.items(in: .inbox).contains { $0.id == id } })
                await source.flush()
                try #require(await eventually { library.item(id)?.sync == .settled })
                try await source.engine.sync.refreshNow()
                // Gives the changes the catch-up brought time to reach the library before checking that the item
                // did not leave the Inbox.
                try await Task.sleep(for: .seconds(2))
                Attachment.record("held: \(library.item(id) != nil), tier: \(String(describing: library.item(id)?.tier)), inbox: \(library.items(in: .inbox).count), failure: \(String(describing: library.failure))", named: "Inbox.txt")
                #expect(library.items(in: .inbox).contains { $0.id == id })
            }
        }

        /// What a person might type into search.
        @Test(.timeLimit(.minutes(2)))
        func untidySearchTextIsSearchedNotRefused() async throws {
            try await withLibrary { library, source, _ in
                var thrown: [String] = []
                for query in ["\"", "foo\"", "(", "a)", "*", "-x", "a:b", "NOT", "AND", "^", "it's", "c++", "near/3", "{x}", "100%"] {
                    do { _ = try await source.search(query, in: MarfaLibrary.searchScope) } catch { thrown.append("\(query) -> \(error)") }
                }
                Attachment.record(thrown.joined(separator: "\n"), named: "Search.txt")
                #expect(thrown.isEmpty, "\(thrown)")
            }
        }
    }
}

/// Holds the calling thread, as a long redraw holds the main actor.
func busy(seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
}
