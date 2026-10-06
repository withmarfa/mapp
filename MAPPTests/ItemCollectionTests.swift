import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// Notes and files read as one collection of items, as the views see them.
struct ItemCollectionTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let work = StoredFolder(id: .mint(), name: "Work")

    /// A library read from a store holding the notes and files given, as the app reads a folder.
    func load(notes: [StoredNote] = [], trash: [TrashedNote] = [], files: [StoredFile] = []) async -> NoteLibrary {
        let store = RecordingStore()
        store.stored = StoredLibrary(folders: [work], notes: notes, trash: trash, files: files)
        let library = NoteLibrary(loadingFrom: store, defaults: nil, now: { start + 60 })
        await library.load()
        return library
    }

    func note(_ path: String, _ text: String, modified: TimeInterval = 0) -> StoredNote {
        StoredNote(id: .mint(), path: path, text: text, created: start, modified: start + modified)
    }

    func file(_ path: String, bytes: Int64 = 2_048, modified: TimeInterval = 0) -> StoredFile {
        StoredFile(id: .mint(), path: path, created: start, modified: start + modified, byteCount: bytes)
    }

    // MARK: Mapping a note

    @Test func aNoteTakesItsDeclaredTypeOrIsANote() async throws {
        let typed = note("Work/Task.md", "---\ntype: aic.ticket.task\ntitle: Task\n---\nBody\n")
        let plain = note("Plain.md", "Plain\n\nText\n")
        let library = await load(notes: [typed, plain])
        #expect(library.item(typed.id)?.type == TypeID("aic.ticket.task"))
        #expect(library.item(plain.id)?.type == TypeID("core.note"))
        #expect(library.item(plain.id)?.content == .markdown)
    }

    @Test func aTitlePropertyIsTheTitleRuleOtherwiseTheFirstLineIs() async throws {
        let titled = note("Work/Some file.md", "---\ntitle: Given title\n---\nFirst line\n")
        let plain = note("First line.md", "First line\n\nMore\n")
        let library = await load(notes: [titled, plain])
        let item = try #require(library.item(titled.id))
        #expect(item.title == "Given title")
        #expect(item.titleRule == .property("title"))
        let other = try #require(library.item(plain.id))
        #expect(other.title == "First line")
        #expect(other.titleRule == .firstLine)
        #expect(other.preview == "More")
    }

    @Test func propertiesFollowTheTypesFieldsThenTheRestByKey() async throws {
        let task = note("Work/Task.md", """
            ---
            zeta: last
            type: aic.ticket.task
            priority: high
            alpha: first
            status: pending
            tags: [favorite]
            title: Task
            ---
            Body

            """)
        let library = await load(notes: [task])
        let item = try #require(library.item(task.id))
        #expect(item.properties.map(\.key) == ["status", "priority", "alpha", "title", "zeta"])
        #expect(item.value(of: "status") == .string("pending"))
        #expect(item.value(of: "type") == nil, "the type is the item's own")
        #expect(item.value(of: "tags") == nil, "the tags are the item's own")
    }

    @Test func aDeletedNoteIsTrashedAndKeepsWhereItWas() async throws {
        let live = note("Work/Live.md", "Live\n")
        let gone = note("Work/Gone.md", "Gone\n")
        let library = await load(notes: [live], trash: [TrashedNote(id: UUID(), note: gone, trashed: start + 30)])
        let item = try #require(library.item(live.id))
        #expect(item.state == .active)
        #expect(item.trashed == nil)
        #expect(item.container == ContainerID(work.id))
        let trashed = try #require(library.item(gone.id))
        #expect(trashed.state == .trashed)
        #expect(trashed.trashed == start + 30)
        #expect(trashed.container == ContainerID(work.id))
        #expect(!trashed.isEditable && !trashed.isWritable)
        #expect(library.items(in: .recentlyDeleted).map(\.id) == [gone.id])
    }

    @Test func theFavoriteTagMakesAFavorite() async throws {
        let favorite = note("Favorite.md", "---\ntags: [work, favorite]\n---\nFavorite\n")
        let other = note("Other.md", "---\ntags: work\n---\nOther\n")
        let library = await load(notes: [favorite, other])
        #expect(library.item(favorite.id)?.tags == ["work", "favorite"])
        #expect(library.item(favorite.id)?.isFavorite == true)
        #expect(library.item(other.id)?.isFavorite == false)
        #expect(library.items(in: .favorites).map(\.id) == [favorite.id])
    }

    @Test func frontMatterThatDoesNotParseLeavesTheTextWritableButNothingElse() async throws {
        let broken = note("Broken.md", "---\ntitle: [unclosed\n---\nBody\n")
        let library = await load(notes: [broken])
        let item = try #require(library.item(broken.id))
        #expect(item.problem != nil)
        #expect(!item.isEditable)
        #expect(item.isWritable)
        #expect(item.properties.isEmpty)
        #expect(!library.setItemProperty(broken.id, key: "status", value: .string("pending")))
    }

    @Test func referencesAreTheItemsEdgesAsItWritesThem() async throws {
        let parent = note("Projects/Area.md", "---\ntype: aic.project\ntitle: Area\n---\nArea\n")
        let child = note("Work/Task.md", """
            ---
            type: aic.ticket.task
            title: Task
            child-of: "[[Area]]"
            ---
            See [[Nowhere]] and [[Area]].

            """)
        let library = await load(notes: [parent, child])
        let edges = try #require(library.item(child.id)).edgesOut
        #expect(edges.count == 3)
        let parentEdge = try #require(edges.first { $0.origin == .property("child-of") })
        #expect(parentEdge.type == "child-of")
        #expect(parentEdge.target == .item(parent.id))
        #expect(edges.filter { $0.origin == .body }.map(\.target) == [
            .unresolved(spelling: "Nowhere", ambiguous: false), .item(parent.id)
        ])
        #expect(edges.allSatisfy { $0.source == child.id })
        #expect(library.item(parent.id)?.edgesOut.isEmpty == true)
    }

    // MARK: Mapping a file

    @Test func aFileIsAnItemWhoseContentIsItsKindAndSize() async throws {
        let image = file("Work/Photo.png", bytes: 4_096)
        let pdf = file("Brief.pdf")
        let other = file("Notes.txt")
        let library = await load(files: [image, pdf, other])
        let item = try #require(library.item(image.id))
        #expect(item.type == WorkbenchSchema.imageType)
        #expect(item.title == "Photo.png")
        #expect(item.content == .file(.png, byteCount: 4_096))
        #expect(item.container == ContainerID(work.id))
        #expect(item.isFile && !item.isEditable && !item.isWritable)
        #expect(library.item(pdf.id)?.type == WorkbenchSchema.pdfType)
        #expect(library.item(other.id)?.type == WorkbenchSchema.fileType)
        #expect(library.body(of: image.id) == nil)
        #expect(library.catalogue.isSubtype(WorkbenchSchema.imageType, ofAnyOf: [WorkbenchSchema.fileType]))
    }

    // MARK: One collection

    @Test func notesAndFilesAreListedAndSortedTogether() async throws {
        let apple = note("Apple.md", "Apple\n", modified: 30)
        let cherry = note("Work/Cherry.md", "Cherry\n", modified: 10)
        let banana = file("Banana.png", modified: 20)
        let date = file("Work/Date.pdf", modified: 40)
        let library = await load(notes: [apple, cherry], files: [banana, date])
        let browser = Browser()
        browser.show(.allNotes, in: library, order: NoteOrder(sort: .title))
        let byTitle = browser.sections(in: library, order: NoteOrder(sort: .title), now: start)
        #expect(byTitle.flatMap(\.items).map(\.title) == ["Apple", "Banana.png", "Cherry", "Date.pdf"])
        let byDate = browser.sections(in: library, order: NoteOrder(sort: .dateEdited), now: start)
        #expect(byDate.flatMap(\.items).map(\.id) == [date.id, apple.id, banana.id, cherry.id])
        #expect(browser.selection == [apple.id])
        #expect(library.items(in: .inbox).map(\.id) == [apple.id, banana.id])
        #expect(library.items(in: .folder(work.id)).map(\.id) == [cherry.id, date.id])
        #expect(library.items(in: .files).map(\.id) == [banana.id, date.id])
    }

    @Test func searchFindsNotesByTextAndFilesByName() async throws {
        let recipe = note("Recipe.md", "Recipe\n\nA proper ragù\n")
        let photo = file("Ragu photo.jpg")
        let library = await load(notes: [recipe], files: [photo])
        #expect(Set(library.items(matching: "RAGU").map(\.id)) == [recipe.id, photo.id])
        #expect(library.items(matching: "proper").map(\.id) == [recipe.id])
    }

    @Test func everyPlaceCountsWhatItLists() async throws {
        let library = await load(
            notes: [
                note("Inbox.md", "---\ntags: [favorite]\n---\nInbox\n"),
                note("Work/Task.md", "---\ntype: aic.ticket.task\ntitle: Task\n---\nTask\n"),
                note("Projects/Area.md", "---\ntype: aic.project\ntitle: Area\n---\nArea\n")
            ],
            trash: [TrashedNote(id: UUID(), note: note("Work/Old.md", "Old\n"), trashed: start)],
            files: [file("Photo.png"), file("Work/Brief.pdf")])
        let project = try #require(library.items(in: .itemType("aic.project")).first)
        let places: [SidebarItem] = [
            .inbox, .allNotes, .favorites, .files, .recentlyDeleted, .marfaTypes, .folder(work.id),
            .project(project.id), .favoriteItem(project.id)
        ] + WorkbenchSchema.types.map { .itemType($0.id) } + [.itemType("core.image")]
        for place in places {
            #expect(library.count(in: place) == library.items(in: place).count, "\(place)")
        }
        #expect(library.count(in: .allNotes) == 5)
        #expect(library.count(in: .files) == 2)
    }

    // MARK: Keeping items

    @Test func anItemIsKeptUntilItsNoteChangesAndItsVersionMovesOnWithIt() async throws {
        let one = note("One.md", "One\n\nText\n")
        let two = note("Two.md", "Two\n\nText\n")
        let library = await load(notes: [one, two])
        let before = try #require(library.item(one.id))
        let other = try #require(library.item(two.id))
        #expect(library.item(one.id) == before)
        #expect(library.body(of: one.id) == ItemBody(id: one.id, text: "One\n\nText\n", version: before.version))
        library.updateBody(of: one.id, to: "One\n\nMore text\n")
        let after = try #require(library.item(one.id))
        #expect(after.version > before.version)
        #expect(after.preview == "More text")
        #expect(library.body(of: one.id)?.version == after.version)
        #expect(library.item(two.id)?.version == other.version, "an item whose note did not change keeps its version")
    }

    @Test func typingOutsideAReferenceKeepsTheConnectionsAndChangingOneRemakesThem() async throws {
        let target = note("Target.md", "Target\n")
        let other = note("Other.md", "Other\n")
        let source = note("Source.md", "Source\n\nSee [[Target]].\n\nNotes\n")
        let library = await load(notes: [target, other, source])
        #expect(library.item(source.id)?.edgesOut.map(\.target) == [.item(target.id)])
        let generation = try #require(library.connections?.generation)
        library.updateBody(of: source.id, to: "Source\n\nSee [[Target]].\n\nNotes, and more notes\n")
        #expect(library.item(source.id)?.edgesOut.map(\.target) == [.item(target.id)])
        #expect(library.connections?.generation == generation)
        library.updateBody(of: source.id, to: "Source\n\nSee [[Other]].\n\nNotes, and more notes\n")
        #expect(library.item(source.id)?.edgesOut.map(\.target) == [.item(other.id)])
        #expect(library.connections?.generation == generation + 1)
    }

    @Test func retitlingANoteResolvesReferencesToItAgain() async throws {
        let target = note("Draft.md", "Draft\n")
        let source = note("Source.md", "Source\n\nSee [[Final]].\n")
        let library = await load(notes: [target, source])
        #expect(library.item(source.id)?.edgesOut.map(\.target) == [.unresolved(spelling: "Final", ambiguous: false)])
        library.updateBody(of: target.id, to: "Final\n")
        #expect(library.item(source.id)?.edgesOut.map(\.target) == [.item(target.id)])
    }

    @Test func referenceLinesAreTheLinesThatCouldHoldAReference() {
        #expect(NoteConnectionIndex.referenceLines(in: "One\nTwo [[A]]\r\n[[B\nno [ [ here\n[[") == ["Two [[A]]", "[[B", "[["])
        #expect(NoteConnectionIndex.referenceLines(in: "").isEmpty)
    }
}
