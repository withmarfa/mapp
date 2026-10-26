import Foundation
import Marfa
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// Against the test instance, in the Live test plan, each on a copy of its own that it removes.
    @MainActor @Suite(.serialized)
    struct MarfaHostLiveTests {
        private func host(_ bench: HostBench) -> MarfaHost {
            bench.host(opener: { try await MarfaSource.open($0, keys: $1, location: $2) })
        }

        /// A mistyped key never replaces the key that works.
        @Test(.timeLimit(.minutes(2)))
        func aWrongKeyGivenForAWorkingCopyKeepsTheOldKey() async throws {
            let bench = try HostBench()
            let host = host(bench)
            let address = try LiveMarfa.address()
            let key = try LiveMarfa.key()
            try await host.connect(address: address, key: key)
            #expect(await eventually { host.state == .online })
            do {
                try await host.replaceKey("mapptest-not-a-key-\(UUID().uuidString)")
                Issue.record("took a key the server refuses")
            } catch {}
            #expect(bench.keys.key(for: try MarfaConnection(address: address)) == key)
            #expect(await eventually { host.state == .online }, "\(host.state)")
            try await discardEverything(host)
        }

        /// Writes made to an item another device purged meanwhile are refused by the server. Each refusal is a
        /// problem the person can see, copy what they typed from, and discard.
        @Test(.timeLimit(.minutes(3)))
        func editsToAnItemPurgedElsewhereAreAProblemThePersonCanCopyAndDiscard() async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaHostTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let made = LiveMarfa.Made()
            do {
                try await refuseEditsToAPurgedItem(root, made)
            } catch {
                await LiveMarfa.purge(made.ids)
                throw error
            }
            await LiveMarfa.purge(made.ids)
        }

        private func refuseEditsToAPurgedItem(_ root: URL, _ made: LiveMarfa.Made) async throws {
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let keys = MemoryKeyStore([connection: try LiveMarfa.key()])
            let location = MarfaStoreLocation(root: root)
            let id = made.mint()
            let first = try await MarfaSource.open(connection, keys: keys, location: location)
            let version = try await closing(first) {
                let log = ChangeLog(first)
                first.refresh()
                try #require(await eventually { LiveMarfa.isWhole(first.syncReport) && first.connectionState == .online })
                let created = WriteID()
                first.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MAPPTEST purged elsewhere", body: "One")), as: created)
                await first.flush()
                let settled = try #require(await log.wait { state in
                    state.answer(to: created) == .accepted && state.snapshot?.items.first { $0.id == id }?.sync == .settled
                })
                return try #require(settled.snapshot?.items.first { $0.id == id }?.version)
            }

            // Another device bins and purges the item while this copy is closed.
            await LiveMarfa.purge([id])

            let source = try await MarfaSource.open(connection, keys: keys, location: location)
            try await closing(source) {
                let log = ChangeLog(source)
                _ = try #require(await log.wait { $0.snapshot?.items.contains { $0.id == id } == true })
                let typed = "MAPPTEST purged elsewhere, then everything typed after"
                let edit = WriteID(), behind = WriteID()
                source.submit(.editProperties(id, ["title": .string(typed)], base: version, undoing: nil), as: edit)
                source.submit(.tag(id, ItemTag.favorite, on: true), as: behind)
                #expect(await eventually { source.syncReport.waiting == 2 }, "\(source.syncReport.waiting) waiting, \(source.connectionState), \(source.syncReport.problems)")
                source.refresh()
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
            try await host.connect(address: try LiveMarfa.address(), key: "mapptest-not-a-key-\(UUID().uuidString)")
            #expect(await eventually { host.state == .keyRefused }, "\(host.state)")
            try await host.replaceKey(try LiveMarfa.key())
            #expect(await eventually { host.state == .online }, "\(host.state)")
            try await discardEverything(host)
        }
    }
}
