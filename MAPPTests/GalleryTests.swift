import CoreGraphics
import Foundation
import Testing
@testable import MAPP

struct GalleryTests {
    let a = ItemID.mint(), b = ItemID.mint(), c = ItemID.mint(), d = ItemID.mint()

    @Test func clickingAndModifierSelectionUseVisibleOrder() {
        let ids = [a, b, c, d]
        #expect(GallerySelection.selecting(c, among: ids, current: [a], anchor: a, extending: false, toggling: false) == [c])
        #expect(GallerySelection.selecting(c, among: ids, current: [a], anchor: a, extending: false, toggling: true) == [a, c])
        #expect(GallerySelection.selecting(a, among: ids, current: [a, c], anchor: a, extending: false, toggling: true) == [c])
        #expect(GallerySelection.selecting(d, among: ids, current: [b], anchor: b, extending: true, toggling: false) == [b, c, d])
        #expect(GallerySelection.selecting(a, among: ids, current: [c], anchor: c, extending: true, toggling: false) == [a, b, c])
        #expect(GallerySelection.selecting(d, among: ids, current: [], anchor: .mint(), extending: true, toggling: false) == [d])
    }

    @Test func keyboardNavigationStopsAtTheCollectionEdges() {
        #expect(GallerySelection.moving(from: b, among: [a, b, c, d], by: 2) == d)
        #expect(GallerySelection.moving(from: d, among: [a, b, c, d], by: 2) == d)
        #expect(GallerySelection.moving(from: a, among: [a, b], by: -1) == a)
        #expect(GallerySelection.moving(from: .mint(), among: [a, b], by: 1) == a)
        #expect(GallerySelection.moving(from: a, among: [], by: 1) == nil)
        #expect(GallerySelection.movingVertically(from: a, sections: [[a, b], [c, d]], columns: 3, down: true) == c)
        #expect(GallerySelection.movingVertically(from: d, sections: [[a, b], [c, d]], columns: 3, down: false) == b)
        #expect(GallerySelection.movingVertically(from: b, sections: [[a, b], [c]], columns: 3, down: true) == c)
        #expect(GallerySelection.movingVertically(from: a, sections: [], columns: 0, down: true) == nil)
    }

    @Test func galleryRestoresAsACollectionAndKeepsItsSelection() throws {
        let (library, _, newer, _) = BrowserTests().makeLibrary()
        let saved = Browser()
        saved.viewMode = .gallery
        saved.selection = [newer.id]
        saved.openGallerySelection()
        let data = try JSONEncoder().encode(saved.snapshot())
        let restored = Browser()
        restored.restore(from: data, in: library, order: NoteOrder())
        #expect(restored.showsGallery)
        #expect(restored.selection == [newer.id])
    }

    @Test func returningToGalleryRetainsTheDraftAndChangingPlaceReturnsToTheGrid() {
        let (library, _, _, _) = BrowserTests().makeLibrary()
        let browser = Browser()
        browser.viewMode = .gallery
        browser.show(.allNotes, in: library, order: NoteOrder())
        browser.openGallerySelection()
        #expect(!browser.showsGallery)
        browser.startItemDraft()
        browser.itemDraft?.body = "Keep this text"
        browser.returnToGallery()
        #expect(browser.showsGallery)
        #expect(browser.itemDraft?.body == "Keep this text")
        browser.openGallerySelection()
        browser.show(.inbox, in: library, order: NoteOrder())
        #expect(browser.showsGallery)
        browser.show(.marfaTypes, in: library, order: NoteOrder())
        #expect(!browser.usesGallery)
        browser.show(.allNotes, in: library, order: NoteOrder())
        #expect(browser.showsGallery)
    }

    @Test func imageCandidatesIgnoreCodeAndRemoteAddresses() {
        let markdown = """
        # Note
        `![inline](inline.png)`
        ```markdown
        ![fenced](fenced.png)
        ```
            ![indented](indented.png)
        ![remote](https://example.test/private.png)
        ![photo](<Photos/a b.png>)
        ![[Other.png|400]]
        ![nested](Photos/a(b).png "Caption")
        \\![escaped](escaped.png)
        """
        #expect(GalleryImageReferences.inBody(markdown) == [.path("Photos/a b.png"), .name("Other.png"), .path("Photos/a(b).png")])
    }

    @Test func aMissingOrDamagedImageUsesTheNextReadableImage() async throws {
        let folder = try EmbeddedFilesTests.Folder()
        try folder.write(Data("not an image".utf8), to: "Projects/Bad.png")
        try folder.write(EmbedFixtures.png(width: 1600, height: 1200), to: "Projects/Good.png")
        let body = "![Missing](Missing.png) ![Bad](Bad.png) ![Good](Good.png)"
        let item = try #require(folder.library.item(folder.note.id))
        let image = try #require(await GalleryPreview.image(for: item, body: body, in: folder.library))
        #expect(image.width <= 800 && image.height <= 800)
    }

    @Test func imagesOutsideTheNotesFolderAreNotRead() async throws {
        let folder = try EmbeddedFilesTests.Folder()
        let outside = folder.root.url.deletingLastPathComponent().appending(path: "outside-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outside) }
        try EmbedFixtures.png().write(to: outside)
        try FileManager.default.createSymbolicLink(at: folder.root.url.appending(path: "Projects/Link.png"), withDestinationURL: outside)
        let item = try #require(folder.library.item(folder.note.id))
        #expect(await GalleryPreview.image(for: item, body: "![](../../\(outside.lastPathComponent)) ![](Link.png)", in: folder.library) == nil)
    }
}
