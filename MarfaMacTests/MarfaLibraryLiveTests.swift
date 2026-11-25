import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MarfaMac

extension LiveMarfaTests {
    /// The library over a real copy of the test instance, in the Live test plan. Every item it makes has a title
    /// starting `MARFAMACTEST ` and is purged when the test ends, passed or not.
    @MainActor
    @Suite(.serialized)
    struct MarfaLibraryLiveTests {
        private func withLibrary(_ body: @MainActor (MarfaLibrary, MarfaSource, LiveMarfa.Made) async throws -> Void) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaLibraryLiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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

        @Test(.timeLimit(.minutes(2)))
        func browsesEveryPlaceAndFollowsEdgesBothWays() async throws {
            try await withLibrary { library, source, made in
                let token = "zb" + UUID().uuidString.prefix(8).lowercased()
                @MainActor func make(_ title: String, under parent: ItemID? = nil, in place: MarfaMac.Tier = .library) throws -> ItemID {
                    let id = library.createItem(
                        typeID: "core.note", title: "MARFAMACTEST \(title) \(token)", body: "Made by the app tests.",
                        parentID: parent, tier: place, undoManager: nil)
                    if let id { made.add(id) }
                    return try #require(id)
                }
                let project = try make("project")
                let captured = try make("captured", in: .feed)
                try #require(await eventually { library.item(project) != nil })
                let children = [try make("first child", under: project), try make("second child", under: project)]
                await source.flush()
                try #require(await eventually {
                    Set(library.relationships(for: project).first { $0.field == "inverse:parent-of" }?.targets.compactMap(\.itemID) ?? [])
                        == Set(children) && library.item(captured) != nil
                })

                let types = Set(library.items(in: .library).map(\.type))
                for place in [Place.feed, .library] + types.map({ Place.type($0) }) {
                    let items = library.items(in: place)
                    #expect(library.count(in: place) == items.count, "\(place)")
                    #expect(!library.name(of: place).isEmpty, "\(place)")
                    switch place {
                    case .feed: #expect(items.allSatisfy { $0.tier == .feed })
                    case .type(let type):
                        let own = library.items(in: place, scope: .all, archived: .hidden, includingKinds: false)
                        #expect(own.allSatisfy { $0.type == type && $0.state == .active }, "\(place)")
                        #expect(Set(own.map(\.id)).isSubset(of: Set(items.map(\.id))), "\(place)")
                    default: #expect(items.allSatisfy { $0.state == .active }, "\(place)")
                    }
                }
                #expect(library.favoriteItems(in: .library, archived: .hidden).allSatisfy { $0.isFavorite && $0.state == .active })
                // A library may hold untitled notes, so what is read back is the titles of the notes made here.
                #expect(library.item(project)?.title == "MARFAMACTEST project \(token)")
                #expect(children.map { library.item($0)?.title } == ["MARFAMACTEST first child \(token)", "MARFAMACTEST second child \(token)"])
                // One copy holds both tiers: the Feed lists the feed tier, and the Library does not.
                let feed = library.items(in: .feed)
                #expect(feed.contains { $0.id == captured })
                #expect(!feed.contains { $0.id == project })
                #expect(Set(feed.map(\.id)).isDisjoint(with: Set(library.items(in: .library).map(\.id))))

                // Each child holds its parent as `child-of`, which makes the parent no collection.
                let below = try #require(library.relationships(for: project).first { $0.field == "inverse:parent-of" })
                #expect(below.label == "Children")
                #expect(library.items(in: .collection(project)).isEmpty)
                for child in children {
                    let parent = library.relationships(for: child).first { $0.field == "child-of" }
                    #expect(parent?.targets.map(\.itemID) == [project])
                    #expect(parent?.label == "Parent")
                }
                #expect(library.body(of: project)?.text == "Made by the app tests.")
                #expect(!library.relationshipCandidates(for: project, field: "about").isEmpty)
                #expect(await eventually { library.search(token, in: .everywhere).items.contains { $0.id == project } })
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func filesItemsInACollectionAndTakesThemOut() async throws {
            try await withLibrary { library, source, made in
                let token = "zc" + UUID().uuidString.prefix(8).lowercased()
                // Whatever type the instance gives the `container` role, as the app never names one.
                let type = try #require(library.catalogue.collectionTypes.map(\.rawValue).sorted().first)
                @MainActor func make(_ title: String, type: String) throws -> ItemID {
                    let id = library.createItem(
                        typeID: type, title: "MARFAMACTEST \(title) \(token)", body: "", properties: [:], parentID: nil,
                        tier: .library, undoManager: nil)
                    if let id { made.add(id) }
                    return try #require(id)
                }
                let collection = try make("collection", type: type)
                let other = try make("other collection", type: type)
                let first = try make("first member", type: "core.note")
                let second = try make("second member", type: "core.note")
                await source.flush()
                try #require(await eventually {
                    library.collections.contains { $0.id == collection } && library.item(first) != nil && library.item(second) != nil
                })

                #expect(library.addToCollection([first, second], collection, undoManager: nil))
                await source.flush()
                #expect(await eventually { Set(library.items(in: .collection(collection)).map(\.id)) == [first, second] })
                let membership = library.relationships(for: first).first { $0.field == "in-collection" }
                #expect(membership?.targets.map(\.itemID) == [collection])
                let contents = library.relationships(for: collection).first { $0.field == "inverse:in-collection" }
                #expect(Set(contents?.targets.map(\.itemID) ?? []) == [first, second])

                // The server refuses nesting, and the app never sends it.
                #expect(!library.addToCollection([other], collection, undoManager: nil))

                #expect(library.removeFromCollection([first], collection, undoManager: nil))
                await source.flush()
                #expect(await eventually { library.items(in: .collection(collection)).map(\.id) == [second] })
                #expect(library.item(first)?.collectionIDs.isEmpty == true)
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
                @MainActor func stepAsync(_ work: () async -> Void) async {
                    undo.beginUndoGrouping()
                    await work()
                    undo.endUndoGrouping()
                }
                let token = "zq" + UUID().uuidString.prefix(8).lowercased()
                @MainActor func make(_ title: String, under parent: ItemID? = nil) throws -> ItemID {
                    let id = library.createItem(
                        typeID: "core.note", title: "MARFAMACTEST \(title) \(token)", body: "Made by the app tests.",
                        parentID: parent, tier: .library, undoManager: nil)
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
                #expect(library.body(of: child)?.text == "Made by the app tests.")

                // Text: held at once, and the copy's own once the server has answered.
                library.updateBody(of: child, to: "Edited \(token) text.")
                library.sendWaitingText()
                #expect(library.body(of: child)?.text == "Edited \(token) text.")
                await source.flush()
                #expect(try await source.body(of: child).text == "Edited \(token) text.")
                #expect(await eventually { library.body(of: child)?.text == "Edited \(token) text." })
                #expect(await eventually { library.search(token, in: .everywhere).items.contains { $0.id == child } })

                // A title, and its undo.
                let title = try #require(library.item(child)?.title)
                step { #expect(library.setItemProperty(child, key: "title", value: .string("MARFAMACTEST renamed \(token)"), undoManager: undo)) }
                #expect(await eventually { library.item(child)?.title == "MARFAMACTEST renamed \(token)" })
                undo.undo()
                #expect(await eventually { library.item(child)?.title == title })

                // The count comes first because the report is read after it: the copy marks itself as catching up
                // before it counts a hydration, so a report read before the count can still be the old, whole one
                // while the hydration has begun. The source's own report is read, since the library's follows it
                // a moment later.
                @MainActor func rehydrated(after before: Int) async throws -> Bool {
                    try await eventuallyAsking {
                        guard await source.engine.sync.hooks.hydrations > before else { return false }
                        return LiveMarfa.isWhole(source.syncReport)
                    }
                }
                // A new parent replaces the one link a child holds, as one move of the edge's source: the child never
                // holds none, and a refusal would leave it where it was.
                let moving = await source.engine.sync.hooks.hydrations
                await stepAsync { #expect(await library.changeLinks(child, field: "child-of", adding: [other], removing: [parent], undoManager: undo) == .taken) }
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
                // The copy refuses a relationship written while it hydrates again, so the engine holds the Undo and makes
                // it once, when the copy is whole.
                try #require(try await rehydrated(after: moving))
                let undoing = await source.engine.sync.hooks.hydrations
                undo.undo()
                #expect(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [parent]
                }, "\(String(describing: library.notices.waiting.last))")
                await source.flush()
                try #require(try await rehydrated(after: undoing))
                // Without a parent, then under another, each seen from both ends, and undone.
                await stepAsync { #expect(await library.changeLinks(child, field: "child-of", adding: [], removing: [parent], undoManager: undo) == .taken) }
                #expect(await eventually {
                    library.relationships(for: child).first { $0.field == "child-of" }?.targets.isEmpty == true
                })
                await stepAsync { #expect(await library.changeLinks(child, field: "child-of", adding: [other], removing: [], undoManager: undo) == .taken) }
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

                // A second parent beside the one it has is refused by the core's check, which the copy makes; nothing is
                // written and the child stays where it is.
                #expect(await eventually { library.syncReport.waiting == 0 })
                let waiting = library.syncReport.waiting
                library.notices.answerAll()
                #expect(await library.changeLinks(child, field: "child-of", adding: [other], removing: [], undoManager: undo) != .taken)
                #expect(library.notices.waiting.last?.message
                    == String(localized: "“\(title)” can hold only one link of this kind, and already holds it."), "\(String(describing: library.notices.waiting.last))")
                #expect(library.syncReport.waiting == waiting)
                #expect(library.relationships(for: child).first { $0.field == "child-of" }?.targets.map(\.itemID) == [parent])
                library.notices.answerAll()

                // A favorite, and its undo.
                step { library.setFavorite([child], true, undoManager: undo) }
                #expect(await eventually { library.favoriteItems(in: .all, archived: .hidden).contains { $0.id == child } })
                undo.undo()
                #expect(await eventually { library.item(child)?.isFavorite == false })

                await source.flush()
                #expect(library.notices.waiting.last == nil, "\(String(describing: library.notices.waiting.last))")

                // The bin: a delete the server has taken leaves the copy, and the item is still in Recently Deleted,
                // from where undoing the delete restores it.
                step { library.delete([other], undoManager: undo) }
                #expect(await eventually { library.item(other)?.state == .trashed })
                await source.flush()
                #expect(library.deletedItems.contains { $0.id == other })
                undo.undo()
                #expect(await eventually { library.item(other)?.state == .active })
                #expect(!library.deletedItems.contains { $0.id == other })
                #expect(library.notices.waiting.last == nil, "\(String(describing: library.notices.waiting.last))")
            }
        }

        /// The bin is the server's, read online: an item deleted and sent is listed, including by a copy that never
        /// held it, is restored from there, and is destroyed for good by Permanently Delete.
        @Test(.timeLimit(.minutes(3)))
        func theBinListsRestoresAndPurgesItems() async throws {
            try await withLibrary { library, source, made in
                let token = "zq" + UUID().uuidString.prefix(8).lowercased()
                let kept = try #require(library.createItem(
                    typeID: "core.note", title: "MARFAMACTEST bin kept \(token)", body: "Kept.", parentID: nil, tier: .library,
                    undoManager: nil))
                let purged = try #require(library.createItem(
                    typeID: "core.note", title: "MARFAMACTEST bin purged \(token)", body: "Purged.", parentID: nil, tier: .library,
                    undoManager: nil))
                made.add(kept)
                made.add(purged)
                try #require(await eventually { library.item(kept) != nil && library.item(purged) != nil })
                await source.flush()
                library.delete([kept, purged], undoManager: nil)
                await source.flush()
                try #require(await eventually {
                    Set(library.deletedItems.map(\.id)).isSuperset(of: [kept, purged])
                })

                // Restoring after the delete was sent: the item comes back to its places.
                library.recover([kept], undoManager: nil)
                try #require(await eventually { library.item(kept)?.state == .active })
                #expect(!library.deletedItems.contains { $0.id == kept })
                #expect(library.items(in: .library).contains { $0.id == kept })

                // Permanently Delete needs the server and takes the item out of the bin and the copy.
                try #require(library.reachesServer)
                library.deletePermanentlyOnConfirm([purged])
                try #require(await eventually { library.item(purged) == nil })
                #expect(library.notices.waiting.last == nil, "\(String(describing: library.notices.waiting.last))")
                let bin = try await source.copy.items.bin()
                #expect(!bin.items.contains { $0.id == purged.rawValue })
                #expect(!bin.items.contains { $0.id == kept.rawValue })
            }
        }

        /// A link in the text is an edge the package writes as the text is saved, seen from both ends; an embedded
        /// file is attached by the package and shows its size once the server has stamped it.
        @Test(.timeLimit(.minutes(3)))
        func linksAndEmbedsInTheTextAreEdgesBothWays() async throws {
            try await withLibrary { library, source, made in
                let token = "zq" + UUID().uuidString.prefix(8).lowercased()
                let targetTitle = "MARFAMACTEST link target \(token)"
                let target = try #require(library.createItem(
                    typeID: "core.note", title: targetTitle, body: "Linked.", parentID: nil, tier: .library, undoManager: nil))
                let host = try #require(library.createItem(
                    typeID: "core.note", title: "MARFAMACTEST link host \(token)", body: "Nothing yet.", parentID: nil,
                    tier: .library, undoManager: nil))
                made.add(target)
                made.add(host)
                try #require(await eventually { library.item(target) != nil && library.item(host) != nil })
                await source.flush()

                // A link to the target, and to a name nothing answers to.
                library.updateBody(of: host, to: "See [[\(targetTitle)]] and [[MARFAMACTEST nowhere \(token)]].")
                library.sendWaitingText()
                await source.flush()
                try #require(await eventually {
                    library.relationships(for: target).first { $0.field == "inverse:references" }?.targets.map(\.itemID) == [host]
                })
                let mentions = library.bodyMentions(for: host)
                #expect(mentions.contains { $0.itemID == target && $0.resolution == .resolved(target) })
                #expect(mentions.contains { $0.title == "MARFAMACTEST nowhere \(token)" && $0.resolution == .missing })

                // Taking the link out of the text takes the edge out.
                library.updateBody(of: host, to: "Nothing again.")
                library.sendWaitingText()
                await source.flush()
                try #require(await eventually {
                    library.relationships(for: target).first { $0.field == "inverse:references" }?.targets.isEmpty ?? true
                })
                #expect(library.bodyMentions(for: host).isEmpty)

                // A file attached through the package, and embedded where the page writes it.
                let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
                let report = await library.attach([(name: "MARFAMACTEST attachment \(token).png", data: png)], to: host)
                let embed = try #require(report.embeds.first, "\(report.failed)")
                #expect(embed.name == "MARFAMACTEST attachment \(token).png")
                library.updateBody(of: host, to: "A picture: ![\(embed.name)](\(embed.link))")
                library.sendWaitingText()
                await source.flush()
                try #require(await eventually {
                    library.relationships(for: host).first { $0.field == "inverse:attached-to" }?.targets.count == 1
                })
                let file = try #require(library.relationships(for: host).first { $0.field == "inverse:attached-to" }?.targets.first?.itemID)
                made.add(file)
                // The path-style embed the page writes reads back as the file the package attached.
                let links = try await source.copy.items.links(in: host.rawValue)
                #expect(links.embeds.map(\.target) == [.item(id: file.rawValue)])
                // The page is served the file through the copy's binding, fetched and kept under its title.
                let shown = await library.openEmbeddedFile(EmbedReference(text: "![\(embed.name)](\(embed.link))"), in: host, waiting: .seconds(30)).file
                #expect(shown?.length == UInt64(png.count))
                #expect(shown?.url.lastPathComponent == embed.name)
                try #require(await eventually {
                    if case .file(_, let size)? = library.item(file)?.content { size == Int64(png.count) } else { false }
                })
                #expect(library.activeItems.contains { $0.id == file })
                #expect(library.notices.waiting.last == nil, "\(String(describing: library.notices.waiting.last))")
            }
        }

        /// A view saved on the server reaches the sidebar through the copy's slice, lists the items the copy holds
        /// of it, and never shows as an item, in a count or in search.
        @Test(.timeLimit(.minutes(2)))
        func savedViewsListTheirItemsAndStayOutOfTheItems() async throws {
            try await withLibrary { library, source, made in
                let status = try await source.copy.status()
                #expect(Set(status.sliceTypes) == Set(MarfaSync.slice))
                #expect(Set(status.sliceEdgeTypes) == Set(MarfaSync.sliceEdgeTypes))

                let token = "zv" + UUID().uuidString.prefix(8).lowercased()
                let title = "MARFAMACTEST view note \(token)"
                let id = try #require(library.createItem(
                    typeID: "core.note", title: title, body: "Made by the app tests.", parentID: nil, tier: .library,
                    undoManager: nil))
                made.add(id)
                await source.flush()
                let query = ViewQuery(types: ["core.note"], filter: "properties.title eq \"\(title)\"")
                let view = try await source.copy.createView(ViewSettings(title: "MARFAMACTEST view \(token)", query: query))
                func deleteView() async { try? await source.copy.deleteView(view.id) }
                do {
                    let place = PlaceView.saved(ItemID(view.id))
                    try #require(await eventually { library.views.contains { $0.id.rawValue == view.id } })
                    #expect(SidebarPlan(library, layout: SidebarLayout()).section(.pinned)?.shown.contains(.view(ItemID(view.id))) == true)
                    #expect(library.name(of: place) == "MARFAMACTEST view \(token)")
                    #expect(await eventually { library.items(inView: ItemID(view.id)).map(\.id) == [id] })

                    #expect(library.item(ItemID(view.id)) == nil)
                    #expect(!library.items(in: .library).contains { $0.id.rawValue == view.id })
                    #expect(!library.itemTypeCounts.contains { $0.id.rawValue.hasPrefix("system.") })
                    // The view's title holds the token too, so only an item reaches the results.
                    #expect(await eventually { library.search(token, in: .everywhere).items.map(\.id) == [id] })

                    let browser = Browser()
                    browser.show(place, in: library, order: ItemOrder())
                    await deleteView()
                    try #require(await eventually { !library.views.contains { $0.id.rawValue == view.id } })
                    browser.placeRemoved(in: library, order: ItemOrder())
                    #expect(browser.showing == .library)
                } catch {
                    await deleteView()
                    throw error
                }
            }
        }

        /// Text typed into an item the page opened before its create was answered, saved once before the answer and then
        /// after each answer as the page saves while the person types, is kept without a conflicted copy, as
        /// `SampleLibraryTests` and `MarfaLibraryReviewFakeTests` check without a server.
        @Test(.timeLimit(.minutes(2)))
        func textTypedOnAnItemJustMadeIsKeptSaveAfterSave() async throws {
            try await withLibrary { library, source, made in
                let title = "MARFAMACTEST typed after a new item " + UUID().uuidString.prefix(8).lowercased()
                let id = try #require(library.createItem(
                    typeID: "core.note", title: title, body: "Ask about the leak under the sink.", parentID: nil,
                    tier: .library, undoManager: nil))
                made.add(id)
                // The page opens the item as soon as it is made, so it reads the text of the create before the server
                // answers it, at version 0.
                let read = ItemBody(id: id, text: "Ask about the leak under the sink.", version: ItemVersion(0))
                // The first save comes before the create is answered; the next follow it once both answers land.
                var text = read.text + " T"
                library.saveText(text, of: id, readAt: read.version, failing: title)
                await source.flush()
                try #require(await eventually {
                    library.body(of: id)?.version == ItemVersion(2) && library.syncReport.waiting == 0
                })
                for typed in ["omorrow", "."] {
                    text += typed
                    library.saveText(text, of: id, readAt: read.version, failing: title)
                    await source.flush()
                    try #require(await eventually { library.syncReport.waiting == 0 })
                }
                #expect(library.notices.waiting.isEmpty, "\(library.notices.waiting)")
                // Other runs can leave copies of their own items on the instance, so only this item's count.
                let copies = library.syncReport.problems.filter { $0.content.title == title }
                #expect(copies.isEmpty, "\(copies)")
                let typed = "Ask about the leak under the sink. Tomorrow."
                #expect(try await source.body(of: id).text == typed)
                // The library reads the text again after the last answer, on its own stream, which can come after the
                // report.
                #expect(await eventually { library.body(of: id)?.text == typed }, "\(String(describing: library.body(of: id)))")
                #expect(try await source.copy.items.get(id.rawValue)?.version == 4)
            }
        }
    }
}
