import Foundation
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// The library over a real copy of the test instance, run only when `MARFA_TEST_URL` and `MARFA_TEST_MAPP_KEY`
    /// are in the environment. Every item it makes has a title starting `MAPPTEST ` and is purged when the test
    /// ends, passed or not.
    @MainActor
    @Suite(.serialized, .enabled(if: LiveMarfa.isConfigured))
    struct MarfaLibraryLiveTests {
        private func withLibrary(_ body: @MainActor (MarfaLibrary, MarfaSource, LiveMarfa.Made) async throws -> Void) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaLibraryLiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let made = LiveMarfa.Made()
            let connection = try MarfaConnection(address: try #require(LiveMarfa.address))
            let source = try await MarfaSource.open(
                connection, keys: MemoryKeyStore([connection: try #require(LiveMarfa.key)]),
                location: try MarfaStoreLocation(root: root))
            let library = MarfaLibrary(source: source)
            func end() async {
                await source.flush()
                await source.close()
                await LiveMarfa.purge(made.ids)
                try? FileManager.default.removeItem(at: root)
            }
            do {
                source.refresh()
                try #require(await eventually(.seconds(60)) {
                    library.isLoaded && library.connection == .online && library.count(in: .allNotes) > 100
                })
                try await body(library, source, made)
            } catch {
                await end()
                throw error
            }
            await end()
        }

        @Test(.timeLimit(.minutes(2)))
        func browsesEveryPlaceAndFollowsEdgesBothWays() async throws {
            try await withLibrary { library, _, _ in
                let types = Set(library.items(in: .allNotes).map(\.type)).map { SidebarItem.itemType($0.rawValue) }
                for place in [SidebarItem.inbox, .allNotes, .favorites, .files, .recentlyDeleted] + types {
                    let items = library.items(in: place)
                    #expect(library.count(in: place) == items.count, "\(place)")
                    #expect(!library.name(of: place).isEmpty, "\(place)")
                    switch place {
                    case .recentlyDeleted: #expect(items.allSatisfy { $0.state == .trashed })
                    case .favorites: #expect(items.allSatisfy { $0.isFavorite && $0.state == .active })
                    case .inbox: #expect(items.allSatisfy { $0.tier == .feed })
                    default: #expect(items.allSatisfy { $0.state == .active }, "\(place)")
                    }
                }
                #expect(library.items(in: .allNotes).allSatisfy { !$0.title.isEmpty })
                // A type's place holds its subtypes.
                let tickets = library.items(in: .itemType("aic.ticket"))
                #expect(tickets.contains { $0.type != TypeID("aic.ticket") })

                // A project lists itself and everything below it; each child holds it as `child-of`.
                let projects = library.items(in: .itemType(MarfaMapping.projectType.rawValue))
                let project = try #require(projects.first { project in
                    library.relationships(for: project.id).contains { $0.field == "inverse:parent-of" && !$0.targets.isEmpty }
                })
                let children = try #require(library.relationships(for: project.id).first { $0.field == "inverse:parent-of" })
                #expect(children.label == "Children")
                let beneath = Set(library.items(in: .project(project.id)).map(\.id))
                #expect(beneath.contains(project.id))
                for child in children.targets {
                    let id = try #require(child.itemID)
                    let parent = library.relationships(for: id).first { $0.field == "child-of" }
                    #expect(parent?.targets.map(\.itemID) == [project.id])
                    #expect(parent?.label == "Parent")
                    if library.item(id)?.state == .active { #expect(beneath.contains(id)) }
                }
                #expect(library.body(of: project.id) != nil)
                #expect(!library.relationshipCandidates(for: project.id, field: "about").isEmpty)

                let word = try #require(project.title.split(separator: " ").first { $0.count > 3 }.map(String.init))
                #expect(await eventually { library.items(matching: word).contains { $0.id == project.id } })
            }
        }

        @Test(.timeLimit(.minutes(3)))
        func makesEditsLinksAndUndoesItsOwnItems() async throws {
            try await withLibrary { library, source, made in
                let undo = UndoManager()
                undo.groupsByEvent = false
                @MainActor func step(_ work: () -> Void) {
                    undo.beginUndoGrouping()
                    work()
                    undo.endUndoGrouping()
                }
                let token = "zq" + UUID().uuidString.prefix(8).lowercased()
                @MainActor func make(_ title: String, under parent: ItemID? = nil) throws -> ItemID {
                    let id = library.createItem(
                        typeID: "core.note", title: "MAPPTEST \(title) \(token)", body: "Made by the MAPP tests.",
                        parentID: parent, in: .allNotes, undoManager: nil)
                    if let id { made.add(id) }
                    return try #require(id)
                }
                let parent = try make("parent")
                let other = try make("other")
                // A parent is chosen from what the library holds, which a new item joins once the copy has it.
                try #require(await eventually(.seconds(20)) { library.item(parent) != nil && library.item(other) != nil })
                let child = try make("child", under: parent)
                try #require(await eventually(.seconds(20)) {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [parent]
                })
                #expect(library.relationships(for: parent).first { $0.field == "inverse:parent-of" }?.targets.map(\.itemID) == [child])
                #expect(library.body(of: child)?.text == "Made by the MAPP tests.")
                #expect(Set(library.items(in: .project(parent)).map(\.id)) == [parent, child])

                // Text: held at once, and the copy's own once the server has answered.
                library.updateBody(of: child, to: "Edited \(token) text.")
                #expect(library.body(of: child)?.text == "Edited \(token) text.")
                await source.flush()
                #expect(try await source.body(of: child).text == "Edited \(token) text.")
                #expect(await eventually(.seconds(20)) { library.body(of: child)?.text == "Edited \(token) text." })
                #expect(await eventually(.seconds(20)) { library.items(matching: token).contains { $0.id == child } })

                // A title, and its undo.
                let title = try #require(library.item(child)?.title)
                step { #expect(library.setItemProperty(child, key: "title", value: .string("MAPPTEST renamed \(token)"), undoManager: undo)) }
                #expect(await eventually(.seconds(20)) { library.item(child)?.title == "MAPPTEST renamed \(token)" })
                undo.undo()
                #expect(await eventually(.seconds(20)) { library.item(child)?.title == title })

                // A new parent replaces the one link a child holds, which waits for the package to move an edge.
                #expect(!library.setItemRelationship(child, field: "child-of", targetIDs: [other], undoManager: undo))
                #expect(library.failure?.message == String(localized: "Changing this link isn’t available yet in a Marfa library."))
                library.failure = nil
                // Without a parent, then under another, each seen from both ends, and undone.
                step { #expect(library.setItemRelationship(child, field: "child-of", targetIDs: [], undoManager: undo)) }
                #expect(await eventually(.seconds(20)) {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.isEmpty == true
                })
                step { #expect(library.setItemRelationship(child, field: "child-of", targetIDs: [other], undoManager: undo)) }
                #expect(await eventually(.seconds(20)) {
                    library.relationships(for: other).first { $0.field == "inverse:parent-of" }?.targets.map(\.itemID) == [child]
                })
                #expect(library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [other])
                undo.undo()
                #expect(await eventually(.seconds(20)) {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.isEmpty == true
                })
                undo.undo()
                #expect(await eventually(.seconds(20)) {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [parent]
                })
                #expect(library.relationships(for: other).first { $0.field == "inverse:parent-of" } == nil)

                // A favorite, and its undo.
                step { library.setFavorite([child], true, undoManager: undo) }
                #expect(await eventually(.seconds(20)) { library.items(in: .favorites).contains { $0.id == child } })
                undo.undo()
                #expect(await eventually(.seconds(20)) { library.item(child)?.isFavorite == false })

                await source.flush()
                #expect(library.failure == nil, "\(String(describing: library.failure))")

                // The bin: a delete the server has taken leaves the copy, so undoing it is either a restore, while the
                // copy still holds the item, or the person is told plainly that it could not be made.
                step { library.delete([other], undoManager: undo) }
                #expect(await eventually(.seconds(20)) { library.item(other).map { $0.state == .trashed } ?? true })
                await source.flush()
                undo.undo()
                #expect(await eventually(.seconds(20)) { library.item(other)?.state == .active || library.failure != nil })
                if let failure = library.failure {
                    #expect(failure.title == String(localized: "Can’t Recover"))
                    Attachment.record("Undoing a delete told the person: \(failure.title): \(failure.message)", named: "Bin.txt")
                    library.failure = nil
                } else {
                    Attachment.record("Undoing a delete restored the item.", named: "Bin.txt")
                }
            }
        }
    }
}
