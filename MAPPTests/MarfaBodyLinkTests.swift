import Foundation
import Marfa
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// What Marfa answers for the links in a note's text, against a server. Run only when `MARFA_TEST_URL` and
    /// `MARFA_TEST_MAPP_KEY` are in the environment (passed to xcodebuild as `TEST_RUNNER_MARFA_TEST_URL` and
    /// `TEST_RUNNER_MARFA_TEST_MAPP_KEY`); a throwaway server and key come from `core/scripts/server-up.sh` in the
    /// `marfa` repository. Every item has a title starting `MAPPTEST ` and is purged when the test ends.
    @Suite(.serialized, .enabled(if: LiveMarfa.isConfigured))
    struct MarfaBodyLinkLiveTests {
        private static let note = TypeID("core.note")

        /// Runs `body` with a fresh copy that has read the server, and purges every id it mints, however it ends.
        private func withSource(_ body: (MarfaSource, ChangeLog, LiveMarfa.Made) async throws -> Void) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaBodyLinks-\(UUID())", directoryHint: .isDirectory)
            let made = LiveMarfa.Made()
            let connection = try MarfaConnection(address: try #require(LiveMarfa.address))
            let source = try await MarfaSource.open(
                connection, keys: MemoryKeyStore([connection: try #require(LiveMarfa.key)]),
                location: try MarfaStoreLocation(root: root))
            let log = ChangeLog(source)
            do {
                source.refresh()
                #expect(await waitForConnection(source) { $0 == .online })
                _ = try #require(await log.wait { $0.snapshot != nil })
                try await body(source, log, made)
            } catch {
                await source.close()
                await LiveMarfa.purge(made.ids)
                try? FileManager.default.removeItem(at: root)
                throw error
            }
            await source.close()
            await LiveMarfa.purge(made.ids)
            try? FileManager.default.removeItem(at: root)
        }

        /// Each link in the text, as typed, with the note it names once the server has answered for all of them.
        private func targets(of reader: ItemID, in source: MarfaSource, count: Int) async throws -> [String: BodyTarget] {
            var found: [String: BodyTarget] = [:]
            _ = await LiveMarfa.until(.seconds(30)) {
                let links = (try? await source.copy.items.links(in: reader.rawValue))?.links ?? []
                found = Dictionary(links.map { ($0.text, $0.target) }, uniquingKeysWith: { first, _ in first })
                return links.count == count && !found.values.contains(.pending)
            }
            return found
        }

        /// A link whose edge stands keeps the note it named when that note is renamed and another note takes its
        /// title, and when a link to the other note is added to the same text, by its identity with the old title as
        /// the label (withmarfa/marfa#2045).
        @Test(.timeLimit(.minutes(2)))
        func anOldLinkKeepsItsTargetWhenALinkToANoteWithItsTitleIsAdded() async throws {
            try await withSource { source, log, made in
                let token = UUID().uuidString.prefix(8)
                let title = "MAPPTEST Plan \(token)"
                let (plan, reader, reused) = (made.mint(), made.mint(), made.mint())
                source.submit(.create(id: plan, ItemDraft(type: Self.note, title: title, body: "Plan")), as: WriteID())
                source.submit(.create(id: reader, ItemDraft(type: Self.note, title: "MAPPTEST Reader \(token)", body: "See [[\(title)]].")), as: WriteID())
                _ = try #require(await log.wait { $0.item(titled: title) != nil && $0.item(titled: "MAPPTEST Reader \(token)") != nil })
                await source.flush()
                let first = try await targets(of: reader, in: source, count: 1)
                #expect(first == ["[[\(title)]]": .item(id: plan.rawValue)])

                let version = try #require(log.current.snapshot?.items.first { $0.id == plan }?.version)
                source.submit(.editProperties(plan, ["title": .string("\(title) v2")], base: version, undoing: nil), as: WriteID())
                source.submit(.create(id: reused, ItemDraft(type: Self.note, title: title, body: "New")), as: WriteID())
                _ = try #require(await log.wait { state in
                    state.snapshot?.items.first { $0.id == plan }?.title == "\(title) v2" && state.snapshot?.items.contains { $0.id == reused } == true
                })
                await source.flush()
                let readerVersion = try #require(log.current.snapshot?.items.first { $0.id == reader }?.version)
                let added = "[[\(reused.rawValue)|\(title)]]"
                source.submit(.editBody(reader, "See [[\(title)]] and \(added).", base: readerVersion, merge: .asRead), as: WriteID())
                await source.flush()

                let after = try await targets(of: reader, in: source, count: 2)
                #expect(after["[[\(title)]]"] == .item(id: plan.rawValue), "the old link was moved to another note")
                #expect(after[added] == .item(id: reused.rawValue))
            }
        }

        /// A link by identity names the note with that identity, even when another note the text links to is titled
        /// with that identity (withmarfa/marfa#2046).
        @Test(.timeLimit(.minutes(2)))
        func aLinkByIdentityNamesThatNoteWhateverAnotherLinkedNoteIsTitled() async throws {
            try await withSource { source, log, made in
                let token = UUID().uuidString.prefix(8)
                let (target, decoy, reader) = (made.mint(), made.mint(), made.mint())
                source.submit(.create(id: target, ItemDraft(type: Self.note, title: "MAPPTEST Target \(token)", body: "Target")), as: WriteID())
                source.submit(.create(id: decoy, ItemDraft(type: Self.note, title: target.rawValue, body: "Decoy")), as: WriteID())
                source.submit(.create(id: reader, ItemDraft(type: Self.note, title: "MAPPTEST Reader \(token)", body: "See [[\(decoy.rawValue)]].")), as: WriteID())
                _ = try #require(await log.wait { $0.item(titled: "MAPPTEST Reader \(token)") != nil && $0.item(titled: target.rawValue) != nil })
                await source.flush()
                #expect(try await targets(of: reader, in: source, count: 1) == ["[[\(decoy.rawValue)]]": .item(id: decoy.rawValue)])

                let version = try #require(log.current.snapshot?.items.first { $0.id == reader }?.version)
                source.submit(.editBody(reader, "See [[\(decoy.rawValue)]] and [[\(target.rawValue)]].", base: version, merge: .asRead), as: WriteID())
                await source.flush()
                let after = try await targets(of: reader, in: source, count: 2)
                #expect(after["[[\(target.rawValue)]]"] == .item(id: target.rawValue), "the identity was read as the other note's title")
                #expect(after["[[\(decoy.rawValue)]]"] == .item(id: decoy.rawValue))
            }
        }
    }
}
