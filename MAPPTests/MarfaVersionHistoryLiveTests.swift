import Foundation
import Marfa
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// Version History over a real test instance: the snapshots `MarfaServerVersions` reads, and a restore written
    /// back through the library. Every item it makes has a title starting `MAPPTEST ` and is purged when the test
    /// ends, passed or not.
    @MainActor
    @Suite(.serialized)
    struct MarfaVersionHistoryLiveTests {
        private static let first = "First draft.", second = "Second draft.", third = "Third draft."

        private func withLibrary(_ body: @MainActor (MarfaLibrary, MarfaSource, LiveMarfa.Made) async throws -> Void) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaVersionHistoryLiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let made = LiveMarfa.Made()
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let keys = MemoryKeyStore([connection: try LiveMarfa.key()])
            let source = try await MarfaSource.open(connection, keys: keys, location: MarfaStoreLocation(root: root))
            let library = MarfaLibrary(
                source: source, notices: Notices(), history: MarfaServerVersions(connection: connection, keys: keys))
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

        /// A note written three times, so the server holds two earlier versions of it besides the current one.
        private func writtenNote(
            _ library: MarfaLibrary, _ source: MarfaSource, _ made: LiveMarfa.Made
        ) async throws -> ItemID {
            let title = "MAPPTEST history \(UUID().uuidString.prefix(8).lowercased())"
            let id = try #require(library.createItem(
                typeID: "core.note", title: title, body: Self.first, parentID: nil, in: .allNotes, undoManager: nil))
            made.add(id)
            for text in [Self.second, Self.third] {
                try #require(await eventually { library.body(of: id)?.text != nil && library.syncReport.waiting == 0 })
                let read = try #require(library.body(of: id))
                library.saveText(text, of: id, readAt: read.version, failing: title)
                await source.flush()
                try #require(await eventually { library.body(of: id)?.text == text && library.syncReport.waiting == 0 })
            }
            #expect(try await source.body(of: id).text == Self.third)
            return id
        }

        private func loadedHistory(of id: ItemID, in library: MarfaLibrary) async throws -> ItemHistoryModel {
            let model = ItemHistoryModel(id: id, source: library.history)
            model.load()
            try #require(await eventually { model.phase != .loading })
            #expect(model.phase == .loaded, "\(model.phase)")
            return model
        }

        @Test(.timeLimit(.minutes(3)))
        func theServersVersionsAreListedAndAnOldOneIsRestoredAndUndone() async throws {
            try await withLibrary { library, source, made in
                let id = try await writtenNote(library, source, made)
                let history = try await loadedHistory(of: id, in: library)
                // A snapshot is the item before the write that replaced it, so the current text has none.
                let texts = history.snapshots.map { $0.text(in: library.catalogue) }
                #expect(texts == [Self.first, Self.second], "\(texts)")
                #expect(history.snapshots.map(\.version) == history.snapshots.map(\.version).sorted())
                let oldest = try #require(history.snapshots.first)
                #expect(oldest.type == TypeID("core.note"))

                let undo = UndoManager()
                #expect(library.restoreCheck(of: oldest, for: id) == .ready(RestorePlan(text: Self.first)))
                #expect(library.restoreVersion(oldest, of: id, undoManager: undo))
                await source.flush()
                try #require(await eventually { library.body(of: id)?.text == Self.first && library.syncReport.waiting == 0 })
                #expect(library.notices.waiting.isEmpty, "\(library.notices.waiting)")
                #expect(try await source.body(of: id).text == Self.first)
                #expect(library.restoreCheck(of: oldest, for: id) == .unchanged)

                // The restore is a new write: what it replaced is now a version of its own.
                let after = try await loadedHistory(of: id, in: library)
                #expect(after.snapshots.count == history.snapshots.count + 1, "\(after.snapshots.map(\.version))")
                #expect(after.snapshots.last?.text(in: library.catalogue) == Self.third)

                undo.undo()
                await source.flush()
                try #require(await eventually { library.body(of: id)?.text == Self.third && library.syncReport.waiting == 0 })
                #expect(library.notices.waiting.isEmpty, "\(library.notices.waiting)")
                #expect(try await source.body(of: id).text == Self.third)
            }
        }

        @Test(.timeLimit(.minutes(3)))
        func aNoteInTheBinCannotBeRestoredAndKeepsItsText() async throws {
            try await withLibrary { library, source, made in
                let id = try await writtenNote(library, source, made)
                let oldest = try #require(try await loadedHistory(of: id, in: library).snapshots.first)

                library.delete([id], undoManager: nil)
                await source.flush()
                try #require(await eventually { library.item(id)?.state == .trashed && library.syncReport.waiting == 0 })

                guard case .unavailable(let reason) = library.restoreCheck(of: oldest, for: id) else {
                    Issue.record("restorable in the bin")
                    return
                }
                #expect(!reason.isEmpty)
                #expect(!library.restoreVersion(oldest, of: id, undoManager: nil))
                #expect(library.notices.waiting.last?.title == String(localized: "Can’t Restore Version"))
                await source.flush()
                #expect(try await source.body(of: id).text == Self.third)
            }
        }
    }
}
