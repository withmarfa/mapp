import CoreGraphics
import Foundation
import Testing
@testable import MAPP

@Suite(.hangLimit)
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
        let (library, _, newer, _) = BrowserTests().makeFakeLibrary()
        let saved = Browser()
        saved.viewMode = .gallery
        saved.selection = [newer.id]
        saved.openCollectionSelection()
        let data = try JSONEncoder().encode(saved.snapshot())
        let restored = Browser()
        restored.restore(from: data, in: library, order: NoteOrder())
        #expect(restored.showsCollection)
        #expect(restored.selection == [newer.id])
    }

    @Test func aNewItemOpensInThePageAndReturningToGalleryOrChangingPlaceReturnsToTheGrid() async {
        let (library, _, _, _) = BrowserTests().makeFakeLibrary()
        let browser = Browser()
        browser.viewMode = .gallery
        browser.show(.allNotes, in: library, order: NoteOrder())
        browser.openCollectionSelection()
        #expect(!browser.showsCollection)
        let id = await browser.quickAdded("New", in: library)
        #expect(!browser.showsCollection, "the new item opens in the page, not behind the grid")
        #expect(browser.selection == id.map { [$0] })
        browser.returnToCollection()
        #expect(browser.showsCollection)
        browser.openCollectionSelection()
        browser.show(.inbox, in: library, order: NoteOrder())
        #expect(browser.showsCollection)
        browser.show(.allNotes, in: library, order: NoteOrder())
        #expect(browser.showsCollection)
    }
}
