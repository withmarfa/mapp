import Foundation
import Marfa
import Testing
@testable import MarfaMac

extension LiveMarfaTests {
    /// The counts a type's look shows, asked of a real server through the library's store. The instance must hold a
    /// type that declares a `messages` table (`core.conversation`) and a task type with a status.
    @MainActor
    @Suite(.serialized)
    struct MarfaCountsLiveTests {
        private func withLibrary(_ body: @MainActor (MarfaLibrary, MarfaSource, LiveMarfa.Made) async throws -> Void) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaCountsLiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let made = LiveMarfa.Made()
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let source = try await MarfaSource.open(
                connection, signIns: ScriptedSignIns([connection.address: try LiveMarfa.key()]),
                location: MarfaStoreLocation(root: root))
            let library = MarfaLibrary(source: source, notices: Notices())
            func end() async {
                await source.flush()
                await source.close()
                await LiveMarfa.purge(made.ids)
                try? FileManager.default.removeItem(at: root)
            }
            do {
                source.refresh()
                try #require(await eventually {
                    library.isLoaded && library.connection == .online && LiveMarfa.isWhole(library.syncReport)
                })
                try await body(library, source, made)
            } catch {
                await end()
                throw error
            }
            await end()
        }

        private func make(_ copy: WorkingCopy, _ made: LiveMarfa.Made, type: String, _ title: String, status: String? = nil) async throws
            -> ItemID
        {
            var properties: JSONObject = ["title": .string("MAPPTEST counts \(title)")]
            if let status { properties["status"] = .string(status) }
            let write = try await copy.items.create(Draft(type: type, properties: properties))
            let id = ItemID(try #require(write.itemId))
            made.add(id)
            return id
        }

        @Test(.timeLimit(.minutes(2)))
        func childrenProgressAndMembersAreCountedAndAChangeToAChildRefreshesThem() async throws {
            try await withLibrary { library, source, made in
                let copy = source.copy
                let parent = try await make(copy, made, type: "core.note", "parent")
                let done = try await make(copy, made, type: "core.task", "done child", status: "completed")
                let open = try await make(copy, made, type: "core.task", "open child", status: "not_started")
                let plain = try await make(copy, made, type: "core.note", "child without a status")
                for child in [done, open, plain] {
                    _ = try await copy.edges.create(from: parent.rawValue, to: child.rawValue, type: MarfaMapping.parentEdge)
                }
                let collection = try await make(copy, made, type: "core.collection", "collection")
                for member in [done, open] {
                    _ = try await copy.edges.create(from: member.rawValue, to: collection.rawValue, type: MarfaMapping.collectionEdge)
                }
                await source.flush()

                library.counts.want([parent], .children)
                library.counts.want([collection], .members)
                #expect(
                    await eventually {
                        library.counts.answer(of: parent, .children)?.total == 3
                            && library.counts.answer(of: collection, .members)?.total == 2
                    }, "children and members")
                let groups = try #require(library.counts.answer(of: parent, .children)?.groups)
                #expect(groups.finished == 1 && groups.withStatus == 2, "\(groups)")

                // A child finishes: the count the store holds is asked again with no one asking for it.
                let version = try #require(try await copy.items.get(open.rawValue)?.version)
                _ = try await copy.items.update(
                    open.rawValue, Edit(properties: ["status": .string("completed")], baseVersion: version))
                await source.flush()
                #expect(
                    await eventually { library.counts.answer(of: parent, .children)?.groups?.finished == 2 },
                    "\(String(describing: library.counts.answer(of: parent, .children)))")
                library.counts.release([parent], .children)
                library.counts.release([collection], .members)
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func aTablesRowsAreCountedAndAChangeToTheTableRefreshesThem() async throws {
            try await withLibrary { library, source, made in
                let copy = source.copy
                let conversation = try await make(copy, made, type: "core.conversation", "conversation")
                await source.flush()
                let message: (String) -> RowOperation = { .put(values: ["author": .string("a"), "text": .string($0), "sent_at": .string("2026-11-18T09:00:00Z")]) }
                _ = try await copy.tables.write([message("one"), message("two"), message("three")], to: "messages", of: conversation.rawValue)
                await source.flush()

                let query = CountQuery.rows(table: "messages")
                library.counts.want([conversation], query)
                #expect(
                    await eventually { library.counts.answer(of: conversation, query)?.total == 3 },
                    "\(String(describing: library.counts.answer(of: conversation, query)))")
                #expect(library.counts.answer(of: conversation, query)?.groups == nil)

                _ = try await copy.tables.write([message("four")], to: "messages", of: conversation.rawValue)
                await source.flush()
                #expect(
                    await eventually { library.counts.answer(of: conversation, query)?.total == 4 },
                    "\(String(describing: library.counts.answer(of: conversation, query)))")
                library.counts.release([conversation], query)
            }
        }
    }
}
