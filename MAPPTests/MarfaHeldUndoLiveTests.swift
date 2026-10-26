import Foundation
import Marfa
import Synchronization
import struct MarfaCore.Edit
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// An Undo pressed while a real copy is brought up to date, over the test instance. Moving a child to another
    /// parent moves the source of its edge, which the server answers by expiring the copy, so the copy hydrates again
    /// and its package refuses the edge write an Undo makes until it is whole. The hydration is held back until the
    /// test lets it go, so the Undo is always pressed inside that window and the refusal is always the package's.
    /// Every item it makes has a title starting `MAPPTEST ` and is purged when the test ends, passed or not.
    @MainActor
    @Suite(.serialized)
    struct MarfaHeldUndoLiveTests {
        /// The refresh of a real copy, whose next hydration waits until the test releases it. The copy is expired
        /// when the hydration is asked for, so it is the package that refuses a write meanwhile.
        private nonisolated final class GatedRefresh: MarfaRefreshing {
            private struct State {
                var armed = false
                var waiting = false
            }

            private let real: MarfaRefresh
            private let state = Mutex(State())
            private let held: AsyncStream<Void>
            private let letGo: AsyncStream<Void>.Continuation

            init(copy: WorkingCopy) {
                real = MarfaRefresh(copy: copy)
                (held, letGo) = AsyncStream<Void>.makeStream()
            }

            /// The next hydration waits, and only that one.
            func arm() { state.withLock { $0.armed = true } }
            var isWaiting: Bool { state.withLock { $0.waiting } }
            func release() { letGo.finish() }

            func readStatus() async throws -> Status { try await real.readStatus() }
            func catchUp() async throws { try await real.catchUp() }
            func fetchKept() async throws -> KeptFetch { try await real.fetchKept() }

            func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
                let gated = state.withLock { state in
                    defer { state.waiting = state.armed; state.armed = false }
                    return state.armed
                }
                if gated {
                    for await _ in held {}
                    state.withLock { $0.waiting = false }
                }
                return try await real.hydrate(types: types, tier: tier, edgeTypes: edgeTypes)
            }
        }

        /// A parent-of edge as the server holds it.
        private struct ServerEdge: Decodable {
            let id: String
            let sourceID: String
            let targetID: String
            let version: Int64

            private enum CodingKeys: String, CodingKey {
                case id, version
                case sourceID = "source_id", targetID = "target_id"
            }
        }

        /// The edge that holds `child` under a parent, read from the server itself and not from any copy, as the edges that point at it.
        private func serverParentEdge(of child: ItemID) async throws -> ServerEdge? {
            var components = URLComponents(url: try #require(URL(string: try LiveMarfa.address())), resolvingAgainstBaseURL: false)
            components?.path += "/items/\(child.rawValue)/backrefs"
            components?.queryItems = [URLQueryItem(name: "edge_type", value: MarfaMapping.parentEdge), URLQueryItem(name: "limit", value: "100")]
            var request = URLRequest(url: try #require(components?.url))
            request.setValue("Bearer \(try LiveMarfa.key())", forHTTPHeaderField: "Authorization")
            struct Page: Decodable { let data: [ServerEdge] }
            let (data, response) = try await URLSession.shared.data(for: request)
            try #require((response as? HTTPURLResponse)?.statusCode == 200)
            return try JSONDecoder().decode(Page.self, from: data).data.first { $0.targetID == child.rawValue }
        }

        /// What a held Undo needs: a child under `parent`, moved to `other` and sent, with the copy's hydration held
        /// back after the server expired it.
        private struct Scene {
            let library: MarfaLibrary
            let source: MarfaSource
            let gate: GatedRefresh
            let undo: UndoManager
            let parent: ItemID
            let other: ItemID
            let third: ItemID
            let child: ItemID
        }

        private func withScene(_ body: @MainActor (Scene) async throws -> Void) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaHeldUndoLiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let made = LiveMarfa.Made()
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let location = MarfaStoreLocation(root: root)
            try FileManager.default.createDirectory(at: location.directory(for: connection), withIntermediateDirectories: true)
            let copy = try await WorkingCopy.open(store: location.store(for: connection), server: connection.server(key: try LiveMarfa.key()))
            let gate = GatedRefresh(copy: copy)
            let source = MarfaSource(copy: copy, connection: connection, refreshing: gate)
            source.events.yield(.paint)
            let library = MarfaLibrary(source: source, notices: Notices())
            func end() async {
                // A hydration still held would keep the source from closing.
                gate.release()
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
                // Groups by event, since a step given back registers itself again outside any group the test opened.
                let undo = UndoManager()
                let token = "zu" + UUID().uuidString.prefix(8).lowercased()
                @MainActor func make(_ title: String, under parent: ItemID? = nil) throws -> ItemID {
                    let id = library.createItem(
                        typeID: "core.note", title: "MAPPTEST \(title) \(token)", body: "Made by the MAPP tests.",
                        parentID: parent, in: .allNotes, undoManager: nil)
                    if let id { made.add(id) }
                    return try #require(id)
                }
                let parent = try make("parent"), other = try make("other"), third = try make("third")
                try #require(await eventually { [parent, other, third].allSatisfy { library.item($0) != nil } })
                let child = try make("child", under: parent)
                try #require(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [parent]
                })
                await source.flush()
                try #require(await eventually { library.syncReport.waiting == 0 && LiveMarfa.isWhole(library.syncReport) })
                try #require(await serverParentEdge(of: child)?.sourceID == parent.rawValue)

                // The move of the edge's source: the server takes it and expires the copy, which hydrates again,
                // and that hydration waits for the test.
                gate.arm()
                undo.beginUndoGrouping()
                #expect(library.setItemRelationship(child, field: "child-of", targetIDs: [other], undoManager: undo))
                undo.endUndoGrouping()
                try #require(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [other]
                })
                // The engine drains the move itself, and only that drain's answer asks for the hydration. A flush would
                // wait for a drain behind the held hydration.
                try #require(await eventually { gate.isWaiting })
                #expect(source.syncReport.phase == .catchingUp)
                #expect(try await serverParentEdge(of: child)?.sourceID == other.rawValue)
                #expect(library.notices.waiting.isEmpty)

                try await body(Scene(library: library, source: source, gate: gate, undo: undo, parent: parent, other: other, third: third, child: child))
            } catch {
                await end()
                throw error
            }
            await end()
        }

        /// The Undo is held, not lost and not refused, while the copy is brought up to date, and is made once, from
        /// the server's point of view, when the copy is whole.
        @Test(.timeLimit(.minutes(3)))
        func anUndoPressedWhileTheCopyCatchesUpIsHeldAndThenMadeOnce() async throws {
            try await withScene { scene in
                let moved = try #require(await serverParentEdge(of: scene.child))
                scene.undo.undo()
                // The package refused the edge write, and the engine kept it.
                try #require(await eventuallyAsking { await scene.source.engine.held.count == 1 })
                #expect(scene.library.notices.waiting.isEmpty)
                #expect(try await serverParentEdge(of: scene.child)?.sourceID == scene.other.rawValue, "the Undo was made before the copy was whole")

                scene.gate.release()
                try #require(await eventuallyAsking { try await serverParentEdge(of: scene.child)?.sourceID == scene.parent.rawValue })
                try #require(await eventuallyAsking { await scene.source.engine.held.isEmpty && LiveMarfa.isWhole(scene.source.syncReport) })
                await scene.source.flush()
                // One move back: the same edge, one version later, and nothing else was written.
                let back = try #require(await serverParentEdge(of: scene.child))
                #expect(back.id == moved.id)
                #expect(back.version == moved.version + 1)
                #expect(await scene.source.engine.held.isEmpty)
                #expect(scene.library.notices.waiting.isEmpty, "\(String(describing: scene.library.notices.waiting.last))")
                #expect(await eventually {
                    scene.library.relationships(for: scene.child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [scene.parent]
                })
                // The step it undid is the one to redo.
                #expect(scene.undo.canRedo)
            }
        }

        /// A held Undo is not made over what another connection changed meanwhile: the person is told, the Undo is
        /// available again, and what the other connection wrote stays.
        @Test(.timeLimit(.minutes(3)))
        func anUndoHeldWhileAnotherConnectionChangesTheItemIsNotMade() async throws {
            try await withScene { scene in
                let moved = try #require(await serverParentEdge(of: scene.child))
                scene.undo.undo()
                try #require(await eventuallyAsking { await scene.source.engine.held.count == 1 })

                // A second copy of the library moves the same edge to a third parent and rewrites the child's text.
                let otherRoot = URL.temporaryDirectory.appending(path: "MarfaHeldUndoLiveTests-other-\(UUID().uuidString)", directoryHint: .isDirectory)
                defer { try? FileManager.default.removeItem(at: otherRoot) }
                try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
                let address = try #require(URL(string: try LiveMarfa.address()))
                let second = try await WorkingCopy.open(
                    store: otherRoot.appending(path: "other.sqlite"), server: Server(url: address, key: try LiveMarfa.key()))
                let newer = "Newer text from another device."
                do {
                    _ = try await second.hydrate(types: ["core.*"], tier: .library, edgeTypes: [MarfaMapping.parentEdge])
                    let row = try #require(try await second.items.get(scene.child.rawValue))
                    _ = try await second.items.update(scene.child.rawValue, Edit(properties: ["body": .string(newer)], baseVersion: row.version))
                    _ = try await second.edges.update(moved.id, EdgeEdit(baseVersion: moved.version, move: .source(scene.third.rawValue)))
                    do {
                        _ = try await second.queue.drain()
                    } catch MarfaError.copyExpired {
                        // The server takes a move of an edge's source and expires every copy, the one that sent it too.
                    }
                } catch {
                    await second.close()
                    throw error
                }
                await second.close()
                try #require(await serverParentEdge(of: scene.child)?.sourceID == scene.third.rawValue)

                scene.gate.release()
                // The copy reads what the other connection wrote, and the held Undo is given back.
                try #require(await eventually { !scene.library.notices.waiting.isEmpty })
                try #require(await eventuallyAsking { await scene.source.engine.held.isEmpty && LiveMarfa.isWhole(scene.source.syncReport) })
                await scene.source.flush()
                let notice = try #require(scene.library.notices.waiting.last)
                #expect(notice.message.contains(MarfaEngine.heldChanged), "\(notice.message)")
                #expect(scene.undo.canUndo, "the Undo was not put back")

                let kept = try #require(await serverParentEdge(of: scene.child))
                #expect(kept.sourceID == scene.third.rawValue)
                #expect(kept.version == moved.version + 1, "the Undo wrote to the edge")
                #expect(try await scene.source.body(of: scene.child).text == newer)
                #expect(await eventually {
                    scene.library.relationships(for: scene.child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [scene.third]
                        && scene.library.body(of: scene.child)?.text == newer
                })
            }
        }
    }
}
