import Foundation
import Marfa
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
                // One copy holds both tiers: the Inbox is the feed, and All Items has the feed's items among the rest.
                let inbox = library.items(in: .inbox)
                #expect(!inbox.isEmpty)
                #expect(Set(inbox.map(\.id)).isSubset(of: Set(library.items(in: .allNotes).map(\.id))))
                #expect(library.items(in: .allNotes).contains { $0.tier == .library })
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

                // A new parent replaces the one link a child holds, which waits for the package to have a call that
                // moves an edge.
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

                // The bin: a delete the server has taken leaves the copy, and the item is still in Recently Deleted,
                // from where undoing the delete restores it.
                step { library.delete([other], undoManager: undo) }
                #expect(await eventually(.seconds(20)) { library.item(other)?.state == .trashed })
                await source.flush()
                #expect(library.items(in: .recentlyDeleted).contains { $0.id == other })
                undo.undo()
                #expect(await eventually(.seconds(30)) { library.item(other)?.state == .active })
                #expect(!library.items(in: .recentlyDeleted).contains { $0.id == other })
                #expect(library.failure == nil, "\(String(describing: library.failure))")
            }
        }

        /// The bin is the server's, read online: an item deleted and sent is listed, including by a copy that never
        /// held it, is restored from there, and is destroyed for good by Delete Permanently.
        @Test(.timeLimit(.minutes(3)))
        func theBinListsRestoresAndPurgesItems() async throws {
            try await withLibrary { library, source, made in
                let token = "zq" + UUID().uuidString.prefix(8).lowercased()
                let kept = try #require(library.createItem(
                    typeID: "core.note", title: "MAPPTEST bin kept \(token)", body: "Kept.", parentID: nil, in: .allNotes,
                    undoManager: nil))
                let purged = try #require(library.createItem(
                    typeID: "core.note", title: "MAPPTEST bin purged \(token)", body: "Purged.", parentID: nil, in: .allNotes,
                    undoManager: nil))
                made.add(kept)
                made.add(purged)
                try #require(await eventually(.seconds(20)) { library.item(kept) != nil && library.item(purged) != nil })
                await source.flush()
                library.delete([kept, purged], undoManager: nil)
                await source.flush()
                try #require(await eventually(.seconds(30)) {
                    Set(library.items(in: .recentlyDeleted).map(\.id)).isSuperset(of: [kept, purged])
                })

                // Restoring after the delete was sent: the item comes back to its places.
                library.recover([kept], undoManager: nil)
                try #require(await eventually(.seconds(30)) { library.item(kept)?.state == .active })
                #expect(!library.items(in: .recentlyDeleted).contains { $0.id == kept })
                #expect(library.items(in: .allNotes).contains { $0.id == kept })

                // Delete Permanently needs the server and takes the item out of the bin and the copy.
                try #require(library.capabilities.contains(.purge))
                library.deletePermanentlyOnConfirm([purged])
                try #require(await eventually(.seconds(30)) { library.item(purged) == nil })
                #expect(library.failure == nil, "\(String(describing: library.failure))")
                let bin = try await source.copy.items.bin()
                #expect(!bin.items.contains { $0.id == purged.rawValue })
                #expect(!bin.items.contains { $0.id == kept.rawValue })
            }
        }

        /// A copy that never held the item reads it from the server's bin, with its text, and restores it from there.
        @Test(.timeLimit(.minutes(3)))
        func aFreshCopyListsTheServersBinAndRestoresFromIt() async throws {
            try await withLibrary { library, source, made in
                let note = try #require(library.createItem(
                    typeID: "core.note", title: "MAPPTEST fresh bin \(UUID().uuidString.prefix(8))", body: "In the bin.",
                    parentID: nil, in: .allNotes, undoManager: nil))
                made.add(note)
                try #require(await eventually(.seconds(20)) { library.item(note) != nil })
                await source.flush()
                library.delete([note], undoManager: nil)
                await source.flush()
                try #require(await eventually(.seconds(30)) { library.item(note)?.state == .trashed })

                let root = URL.temporaryDirectory.appending(path: "MarfaLibraryLiveTests-fresh-\(UUID().uuidString)", directoryHint: .isDirectory)
                defer { try? FileManager.default.removeItem(at: root) }
                let connection = try MarfaConnection(address: try #require(LiveMarfa.address))
                let second = try await MarfaSource.open(
                    connection, keys: MemoryKeyStore([connection: try #require(LiveMarfa.key)]),
                    location: try MarfaStoreLocation(root: root))
                let fresh = MarfaLibrary(source: second)
                second.refresh()
                try #require(await eventually(.seconds(60)) {
                    fresh.isLoaded && fresh.connection == .online && fresh.count(in: .allNotes) > 100
                })
                try #require(await eventually(.seconds(30)) { fresh.items(in: .recentlyDeleted).contains { $0.id == note } })
                #expect(await eventually(.seconds(20)) { fresh.body(of: note)?.text == "In the bin." })

                fresh.recover([note], undoManager: nil)
                #expect(!fresh.items(in: .recentlyDeleted).contains { $0.id == note })
                try #require(await eventually(.seconds(30)) { fresh.item(note)?.state == .active })
                #expect(fresh.failure == nil, "\(String(describing: fresh.failure))")
                await second.flush()
                await second.close()
            }
        }

        /// A link in the text is an edge the package writes as the text is saved, seen from both ends; an embedded
        /// file is attached by the package and shows its size once the server has stamped it.
        @Test(.timeLimit(.minutes(3)))
        func linksAndEmbedsInTheTextAreEdgesBothWays() async throws {
            try await withLibrary { library, source, made in
                let token = "zq" + UUID().uuidString.prefix(8).lowercased()
                let targetTitle = "MAPPTEST link target \(token)"
                let target = try #require(library.createItem(
                    typeID: "core.note", title: targetTitle, body: "Linked.", parentID: nil, in: .allNotes, undoManager: nil))
                let host = try #require(library.createItem(
                    typeID: "core.note", title: "MAPPTEST link host \(token)", body: "Nothing yet.", parentID: nil,
                    in: .allNotes, undoManager: nil))
                made.add(target)
                made.add(host)
                try #require(await eventually(.seconds(20)) { library.item(target) != nil && library.item(host) != nil })
                await source.flush()

                // A link to the target, and to a name nothing answers to.
                library.updateBody(of: host, to: "See [[\(targetTitle)]] and [[MAPPTEST nowhere \(token)]].")
                await source.flush()
                try #require(await eventually(.seconds(30)) {
                    library.relationships(for: target).first { $0.field == "inverse:references" }?.targets.map(\.itemID) == [host]
                })
                let mentions = library.bodyMentions(for: host)
                #expect(mentions.contains { $0.itemID == target && $0.resolution == .resolved(target) })
                #expect(mentions.contains { $0.title == "MAPPTEST nowhere \(token)" && $0.resolution == .missing })

                // Taking the link out of the text takes the edge out.
                library.updateBody(of: host, to: "Nothing again.")
                await source.flush()
                try #require(await eventually(.seconds(30)) {
                    library.relationships(for: target).first { $0.field == "inverse:references" }?.targets.isEmpty ?? true
                })
                #expect(library.bodyMentions(for: host).isEmpty)

                // A file attached through the package, and embedded where the page writes it.
                let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
                let embeds = try await library.attach([(name: "MAPPTEST attachment \(token).png", data: png)], to: host)
                let embed = try #require(embeds.first)
                #expect(embed.name == "MAPPTEST attachment \(token).png")
                library.updateBody(of: host, to: "A picture: ![\(embed.name)](\(embed.link))")
                await source.flush()
                try #require(await eventually(.seconds(30)) {
                    library.relationships(for: host).first { $0.field == "inverse:attached-to" }?.targets.count == 1
                })
                let file = try #require(library.relationships(for: host).first { $0.field == "inverse:attached-to" }?.targets.first?.itemID)
                made.add(file)
                // The path-style embed the page writes reads back as the file the package attached.
                let links = try await source.copy.items.links(in: host.rawValue)
                #expect(links.embeds.map(\.target) == [.item(id: file.rawValue)])
                try #require(await eventually(.seconds(30)) {
                    if case .file(_, let size)? = library.item(file)?.content { size == Int64(png.count) } else { false }
                })
                #expect(library.items(in: .files).contains { $0.id == file })
                #expect(library.failure == nil, "\(String(describing: library.failure))")
            }
        }
    }
}
