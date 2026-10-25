import Foundation
import Marfa
import struct MarfaCore.BinPage
import struct MarfaCore.Item
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// The library over a real copy of the test instance, in the Live test plan. Every item it makes has a title
    /// starting `MAPPTEST ` and is purged when the test ends, passed or not.
    @MainActor
    @Suite(.serialized)
    struct MarfaLibraryLiveTests {
        private func withLibrary(_ body: @MainActor (MarfaLibrary, MarfaSource, LiveMarfa.Made) async throws -> Void) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaLibraryLiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let made = LiveMarfa.Made()
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let source = try await MarfaSource.open(
                connection, keys: MemoryKeyStore([connection: try LiveMarfa.key()]),
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

        @Test(.timeLimit(.minutes(2)))
        func browsesEveryPlaceAndFollowsEdgesBothWays() async throws {
            try await withLibrary { library, source, made in
                let token = "zb" + UUID().uuidString.prefix(8).lowercased()
                @MainActor func make(_ title: String, under parent: ItemID? = nil, in place: SidebarItem = .allNotes) throws -> ItemID {
                    let id = library.createItem(
                        typeID: "core.note", title: "MAPPTEST \(title) \(token)", body: "Made by the MAPP tests.",
                        parentID: parent, in: place, undoManager: nil)
                    if let id { made.add(id) }
                    return try #require(id)
                }
                let project = try make("project")
                let captured = try make("captured", in: .inbox)
                try #require(await eventually { library.item(project) != nil })
                let children = [try make("first child", under: project), try make("second child", under: project)]
                await source.flush()
                try #require(await eventually {
                    Set(library.relationships(for: project).first { $0.field == "inverse:parent-of" }?.targets.compactMap(\.itemID) ?? [])
                        == Set(children) && library.item(captured) != nil
                })

                let types = Set(library.items(in: .allNotes).map(\.type))
                for place in [SidebarItem.inbox, .allNotes, .favorites, .files, .recentlyDeleted] + types.map({ SidebarItem.itemType($0.rawValue) }) {
                    let items = library.items(in: place)
                    #expect(library.count(in: place) == items.count, "\(place)")
                    #expect(!library.name(of: place).isEmpty, "\(place)")
                    switch place {
                    case .recentlyDeleted: #expect(items.allSatisfy { $0.state == .trashed })
                    case .favorites: #expect(items.allSatisfy { $0.isFavorite && $0.state == .active })
                    case .inbox: #expect(items.allSatisfy { $0.tier == .feed })
                    // A type's place holds only its own items, never its subtypes'.
                    case .itemType(let type): #expect(items.allSatisfy { $0.type == TypeID(type) && $0.state == .active }, "\(place)")
                    default: #expect(items.allSatisfy { $0.state == .active }, "\(place)")
                    }
                }
                #expect(library.items(in: .allNotes).allSatisfy { !$0.title.isEmpty })
                // One copy holds both tiers: the Inbox is the feed, and All Items has the feed's items among the rest.
                let inbox = library.items(in: .inbox)
                #expect(inbox.contains { $0.id == captured })
                #expect(!inbox.contains { $0.id == project })
                #expect(Set(inbox.map(\.id)).isSubset(of: Set(library.items(in: .allNotes).map(\.id))))

                // A collection lists everything below it, not itself; each child holds it as `child-of`.
                let below = try #require(library.relationships(for: project).first { $0.field == "inverse:parent-of" })
                #expect(below.label == "Children")
                let beneath = Set(library.items(in: .collection(project)).map(\.id))
                #expect(beneath == Set(children))
                for child in children {
                    let parent = library.relationships(for: child).first { $0.field == "child-of" }
                    #expect(parent?.targets.map(\.itemID) == [project])
                    #expect(parent?.label == "Parent")
                }
                #expect(library.body(of: project)?.text == "Made by the MAPP tests.")
                #expect(!library.relationshipCandidates(for: project, field: "about").isEmpty)
                #expect(await eventually { library.items(matching: token).contains { $0.id == project } })
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
                try #require(await eventually { library.item(parent) != nil && library.item(other) != nil })
                let child = try make("child", under: parent)
                try #require(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [parent]
                })
                #expect(library.relationships(for: parent).first { $0.field == "inverse:parent-of" }?.targets.map(\.itemID) == [child])
                #expect(library.body(of: child)?.text == "Made by the MAPP tests.")
                #expect(Set(library.items(in: .collection(parent)).map(\.id)) == [child])

                // Text: held at once, and the copy's own once the server has answered.
                library.updateBody(of: child, to: "Edited \(token) text.")
                #expect(library.body(of: child)?.text == "Edited \(token) text.")
                await source.flush()
                #expect(try await source.body(of: child).text == "Edited \(token) text.")
                #expect(await eventually { library.body(of: child)?.text == "Edited \(token) text." })
                #expect(await eventually { library.items(matching: token).contains { $0.id == child } })

                // A title, and its undo.
                let title = try #require(library.item(child)?.title)
                step { #expect(library.setItemProperty(child, key: "title", value: .string("MAPPTEST renamed \(token)"), undoManager: undo)) }
                #expect(await eventually { library.item(child)?.title == "MAPPTEST renamed \(token)" })
                undo.undo()
                #expect(await eventually { library.item(child)?.title == title })

                @MainActor func rehydrated(after before: Int) async throws -> Bool {
                    try await eventuallyAsking {
                        guard LiveMarfa.isWhole(library.syncReport) else { return false }
                        return await source.engine.sync.hydrations > before
                    }
                }
                // A new parent replaces the one link a child holds, as one move of the edge's source: the child never
                // holds none, and a refusal would leave it where it was.
                let moving = await source.engine.sync.hydrations
                step { #expect(library.setItemRelationship(child, field: "child-of", targetIDs: [other], undoManager: undo)) }
                #expect(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [other]
                })
                #expect(library.notices.waiting.last == nil)
                #expect(await eventually {
                    library.relationships(for: other).first { $0.field == "inverse:parent-of" }?.targets.map(\.itemID) == [child]
                })
                // The server took the move of a source, which expires the copy and hydrates it again; nothing queued
                // is lost, and the child is still under its new parent.
                await source.flush()
                #expect(await eventually {
                    library.relationships(for: parent).first { $0.field == "inverse:parent-of" } == nil
                        && library.relationships(for: other).first { $0.field == "inverse:parent-of" }?.targets.map(\.itemID) == [child]
                })
                #expect(await eventually { library.syncReport.waiting == 0 })
                // A relationship written while the copy hydrates again is refused until it is whole.
                try #require(try await rehydrated(after: moving))
                let undoing = await source.engine.sync.hydrations
                undo.undo()
                #expect(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [parent]
                }, "\(String(describing: library.notices.waiting.last))")
                await source.flush()
                try #require(try await rehydrated(after: undoing))
                // Without a parent, then under another, each seen from both ends, and undone.
                step { #expect(library.setItemRelationship(child, field: "child-of", targetIDs: [], undoManager: undo)) }
                #expect(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.isEmpty == true
                })
                step { #expect(library.setItemRelationship(child, field: "child-of", targetIDs: [other], undoManager: undo)) }
                #expect(await eventually {
                    library.relationships(for: other).first { $0.field == "inverse:parent-of" }?.targets.map(\.itemID) == [child]
                })
                #expect(library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [other])
                undo.undo()
                #expect(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.isEmpty == true
                })
                undo.undo()
                #expect(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [parent]
                })
                #expect(library.relationships(for: other).first { $0.field == "inverse:parent-of" } == nil)

                // A favorite, and its undo.
                step { library.setFavorite([child], true, undoManager: undo) }
                #expect(await eventually { library.items(in: .favorites).contains { $0.id == child } })
                undo.undo()
                #expect(await eventually { library.item(child)?.isFavorite == false })

                await source.flush()
                #expect(library.notices.waiting.last == nil, "\(String(describing: library.notices.waiting.last))")

                // The bin: a delete the server has taken leaves the copy, and the item is still in Recently Deleted,
                // from where undoing the delete restores it.
                step { library.delete([other], undoManager: undo) }
                #expect(await eventually { library.item(other)?.state == .trashed })
                await source.flush()
                #expect(library.items(in: .recentlyDeleted).contains { $0.id == other })
                undo.undo()
                #expect(await eventually { library.item(other)?.state == .active })
                #expect(!library.items(in: .recentlyDeleted).contains { $0.id == other })
                #expect(library.notices.waiting.last == nil, "\(String(describing: library.notices.waiting.last))")
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
                try #require(await eventually { library.item(kept) != nil && library.item(purged) != nil })
                await source.flush()
                library.delete([kept, purged], undoManager: nil)
                await source.flush()
                try #require(await eventually {
                    Set(library.items(in: .recentlyDeleted).map(\.id)).isSuperset(of: [kept, purged])
                })

                // Restoring after the delete was sent: the item comes back to its places.
                library.recover([kept], undoManager: nil)
                try #require(await eventually { library.item(kept)?.state == .active })
                #expect(!library.items(in: .recentlyDeleted).contains { $0.id == kept })
                #expect(library.items(in: .allNotes).contains { $0.id == kept })

                // Delete Permanently needs the server and takes the item out of the bin and the copy.
                try #require(library.canPurge)
                library.deletePermanentlyOnConfirm([purged])
                try #require(await eventually { library.item(purged) == nil })
                #expect(library.notices.waiting.last == nil, "\(String(describing: library.notices.waiting.last))")
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
                try #require(await eventually { library.item(note) != nil })
                await source.flush()
                library.delete([note], undoManager: nil)
                await source.flush()
                try #require(await eventually { library.item(note)?.state == .trashed })

                let root = URL.temporaryDirectory.appending(path: "MarfaLibraryLiveTests-fresh-\(UUID().uuidString)", directoryHint: .isDirectory)
                defer { try? FileManager.default.removeItem(at: root) }
                let connection = try MarfaConnection(address: try LiveMarfa.address())
                let second = try await MarfaSource.open(
                    connection, keys: MemoryKeyStore([connection: try LiveMarfa.key()]),
                    location: MarfaStoreLocation(root: root))
                let fresh = MarfaLibrary(source: second, notices: Notices())
                second.refresh()
                try #require(await eventually {
                    fresh.isLoaded && fresh.connection == .online && LiveMarfa.isWhole(fresh.syncReport)
                })
                try #require(await eventually { fresh.items(in: .recentlyDeleted).contains { $0.id == note } })
                #expect(await eventually { fresh.body(of: note)?.text == "In the bin." })

                // The copy never held the item, so it is restored once the server has taken it.
                fresh.recover([note], undoManager: nil)
                try #require(await eventually { fresh.item(note)?.state == .active })
                #expect(!fresh.items(in: .recentlyDeleted).contains { $0.id == note })
                #expect(fresh.notices.waiting.last == nil, "\(String(describing: fresh.notices.waiting.last))")
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
                try #require(await eventually { library.item(target) != nil && library.item(host) != nil })
                await source.flush()

                // A link to the target, and to a name nothing answers to.
                library.updateBody(of: host, to: "See [[\(targetTitle)]] and [[MAPPTEST nowhere \(token)]].")
                await source.flush()
                try #require(await eventually {
                    library.relationships(for: target).first { $0.field == "inverse:references" }?.targets.map(\.itemID) == [host]
                })
                let mentions = library.bodyMentions(for: host)
                #expect(mentions.contains { $0.itemID == target && $0.resolution == .resolved(target) })
                #expect(mentions.contains { $0.title == "MAPPTEST nowhere \(token)" && $0.resolution == .missing })

                // Taking the link out of the text takes the edge out.
                library.updateBody(of: host, to: "Nothing again.")
                await source.flush()
                try #require(await eventually {
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
                try #require(await eventually {
                    library.relationships(for: host).first { $0.field == "inverse:attached-to" }?.targets.count == 1
                })
                let file = try #require(library.relationships(for: host).first { $0.field == "inverse:attached-to" }?.targets.first?.itemID)
                made.add(file)
                // The path-style embed the page writes reads back as the file the package attached.
                let links = try await source.copy.items.links(in: host.rawValue)
                #expect(links.embeds.map(\.target) == [.item(id: file.rawValue)])
                try #require(await eventually {
                    if case .file(_, let size)? = library.item(file)?.content { size == Int64(png.count) } else { false }
                })
                #expect(library.items(in: .files).contains { $0.id == file })
                #expect(library.notices.waiting.last == nil, "\(String(describing: library.notices.waiting.last))")
            }
        }
    }
}
