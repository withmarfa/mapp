import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MarfaMac

extension LiveMarfaTests {
    /// Against the test instance, in the Live test plan, each on a copy of its own that it removes.
    @MainActor @Suite(.serialized)
    struct MarfaHostLiveTests {
        private func host(_ bench: HostBench) -> MarfaHost {
            bench.host(opener: { try await MarfaSource.open($0, signIns: $1, location: $2) })
        }

        /// A copy that has heard of another device's purge refuses an edit to the item itself, before anything is queued,
        /// so no problem is listed. What the person typed is then in no queue, and it is given back with the reason.
        @Test(.timeLimit(.minutes(3)))
        func editsToAnItemTheCopyKnowsWasPurgedAreRefusedAtOnceAndTheTextIsGivenBack() async throws {
            try await withPurgedItem { connection, keys, location, id, version in
                let source = try await MarfaSource.open(connection, signIns: keys, location: location)
                try await closing(source) {
                    let notices = Notices()
                    let library = MarfaLibrary(source: source, notices: notices)
                    source.refresh()
                    try #require(await eventually { library.isLoaded && library.item(id) == nil }, "the copy never heard of the purge")
                    let typed = "MARFAMACTEST purged elsewhere, then everything typed after"
                    let log = ChangeLog(source)
                    // As a property editor still showing the item saves, by the library, which follows the answer.
                    library.submitPropertyEdit(
                        .editProperties(id, ["title": .string(typed)], base: version, undoing: nil), of: id,
                        failing: "Can’t Edit This Property")
                    let answered = try #require(await log.wait { state in
                        state.changes.contains { if case .answered(_, .refused) = $0 { true } else { false } }
                    })
                    guard let problem = answered.changes.lazy.compactMap({ change -> SyncProblem? in
                        if case .answered(_, .refused(let problem)) = change { problem } else { nil }
                    }).first else { return }
                    #expect(problem.notQueued, "the package refused it before queueing, so no queue holds the text")
                    #expect(await eventually { notices.waiting.contains { $0.isNotKept && $0.text?.contains(typed) == true } },
                        "what the person typed is given back")
                    #expect(source.syncReport.problems.allSatisfy { $0.itemID != id })
                    #expect(try await source.copy.queue.all().allSatisfy { $0.itemId != id.rawValue })
                }
            }
        }

        /// Writes made to an item another device purged while this copy had not heard of it are queued and refused by the
        /// server. Each refusal is a problem the person can see, copy what they typed from, and discard.
        @Test(.timeLimit(.minutes(3)))
        func editsToAnItemPurgedElsewhereAreAProblemThePersonCanCopyAndDiscard() async throws {
            try await withPurgedItem { connection, keys, location, id, version in
                // The copy is not told what the server does, so the item is still held when the edits are made, and
                // only the server's answer to each queued write says it is gone.
                let copy = try await WorkingCopy.open(store: location.store(for: connection), server: try #require(try keys.server(for: connection)))
                let source = MarfaSource(copy: copy, connection: connection)
                await source.engine.sync.hooks.ignoringCopy.set(true)
                let log = ChangeLog(source)
                source.events.yield(.paint)
                try await closing(source) {
                    let state = try #require(await log.wait { $0.painted != nil })
                    #expect(state.painted?.items.contains { $0.id == id } == true)
                    let typed = "MARFAMACTEST purged elsewhere, then everything typed after"
                    let edit = WriteID(), behind = WriteID()
                    source.submit(.editProperties(id, ["title": .string(typed)], base: version, undoing: nil), as: edit)
                    source.submit(.tag(id, ItemTag.favorite, on: true), as: behind)
                    // Each write names an item the server no longer holds, so each is refused on its own.
                    #expect(await eventually { source.syncReport.problems.count { $0.itemID == id } == 2 }, "\(source.syncReport.problems)")
                    let entries = source.syncReport.problems.filter { $0.itemID == id }
                    #expect(entries.allSatisfy { $0.kind == .refused && $0.reason?.code.isEmpty == false })
                    #expect(entries.allSatisfy { !$0.actions.contains(.tryAgain) && $0.actions.contains(.discard) })
                    let edited = try #require(entries.first { $0.change == .edit })
                    #expect(edited.copyText.contains(typed))
                    for entry in entries { #expect(try await source.resolve(entry.id, by: .discard)) }
                    #expect(await eventually { !source.syncReport.problems.contains { $0.itemID == id } })
                    #expect(try await source.copy.queue.all().allSatisfy { $0.itemId != id.rawValue })
                }
            }
        }

        /// Makes an item through a copy of its own, closes the copy, and has another device purge the item, then hands
        /// the closed copy's place to `body`. Whatever `body` does, the item and the copy's folder are removed.
        private func withPurgedItem(
            _ body: (MarfaConnection, ScriptedSignIns, MarfaStoreLocation, ItemID, ItemVersion) async throws -> Void
        ) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaHostTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let made = LiveMarfa.Made()
            do {
                let connection = try MarfaConnection(address: try LiveMarfa.address())
                let keys = ScriptedSignIns([connection.address: try LiveMarfa.key()])
                let location = MarfaStoreLocation(root: root)
                let id = made.mint()
                let first = try await MarfaSource.open(connection, signIns: keys, location: location)
                let version = try await closing(first) {
                    let log = ChangeLog(first)
                    first.refresh()
                    try #require(await eventually { LiveMarfa.isWhole(first.syncReport) && first.connectionState == .online })
                    let created = WriteID()
                    first.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MARFAMACTEST purged elsewhere", body: "One")), as: created)
                    await first.flush()
                    let settled = try #require(await log.wait { state in
                        state.answer(to: created) == .accepted && state.snapshot?.items.first { $0.id == id }?.sync == .settled
                    })
                    return try #require(settled.snapshot?.items.first { $0.id == id }?.version)
                }
                // Another device bins and purges the item while this copy is closed.
                await LiveMarfa.purge([id])
                try await body(connection, keys, location, id, version)
            } catch {
                await LiveMarfa.purge(made.ids)
                throw error
            }
            await LiveMarfa.purge(made.ids)
        }

        /// Closes `source` whatever `body` does, so a failed check never leaves the copy open while its folder is removed.
        private func closing<T>(_ source: MarfaSource, _ body: () async throws -> T) async throws -> T {
            do {
                let result = try await body()
                await source.close()
                return result
            } catch {
                await source.close()
                throw error
            }
        }

        /// A throwaway key on a throwaway copy, so the real key is never revoked.
        @Test(.timeLimit(.minutes(2)))
        func aWrongKeyIsRefusedUntilTheRightOneIsGiven() async throws {
            let bench = try HostBench()
            let host = host(bench)
            try await host.connect(address: try LiveMarfa.address(), key: "marfamactest-not-a-key-\(UUID().uuidString)")
            #expect(await eventually { host.state == .keyRefused }, "\(host.state)")
            try await host.signInAgain(via: host.scripted(try LiveMarfa.key()))
            #expect(await eventually { host.state == .online }, "\(host.state)")
            try await discardEverything(host)
        }
    }
}
