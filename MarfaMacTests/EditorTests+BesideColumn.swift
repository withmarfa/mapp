import Foundation
import Testing
@testable import MarfaMac

/// The column beside a layout follows a selection that moves quickly without losing what was typed on the item it
/// leaves, and shows the item the editor holds (`EditorController.heldItemID`), as `BesideColumn` does.
extension EditorTests {
    private static func choose(_ id: ItemID?, in settler: BesideSettler, page: Page) {
        settler.choose(id, held: page.editor.heldItemID, handOver: { page.editor.flush(then: $0) }) { id in
            if let item = page.library.item(id) { page.editor.open(item) { _ in } }
        }
    }

    @Test @MainActor func selectingQuicklyDownAListNeverLosesTextTypedOnTheItemLeft() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let third = library.add("Third\n")
        let page = try await Page(library: library)
        page.editor.onChange = { [library] id, text, read in library.updateBody(of: id, to: text, readAt: read) }
        try await page.show(first.id)
        // The page holds an edit it has not reported, which only a flush brings in.
        let leaving = page.editor.generation
        try await page.run("""
            const flush = window.editor.flush.bind(window.editor)
            window.editor.flush = generation => generation === \(leaving) ? 'First, typed\\n' : flush(generation)
            """)

        let settler = BesideSettler(rest: .seconds(2))
        Self.choose(first.id, in: settler, page: page)
        Self.choose(second.id, in: settler, page: page)
        Self.choose(third.id, in: settler, page: page)
        // The text is handed over as the selection leaves the item, long before the column follows it.
        try await page.wait { library.body(of: first.id)?.text == "First, typed\n" }
        #expect(page.editor.heldItemID == first.id, "the column waits for the selection to rest")
        try await page.wait { page.editor.heldItemID == third.id }
        #expect(page.editor.pageItemID == third.id, "the column shows the item the page holds")
        #expect(library.notices.waiting.isEmpty, "nothing was left unsaved, so nothing is told")
        #expect(library.body(of: second.id)?.text == "Second\n")
    }

    @Test @MainActor func aHandOverThatFailsKeepsTheColumnOnItsItem() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let page = try await Page(library: library)
        try await page.show(first.id)
        try await page.run("window.editor.flush = () => { throw new Error('broken') }")

        let settler = BesideSettler(rest: .milliseconds(50))
        Self.choose(first.id, in: settler, page: page)
        Self.choose(second.id, in: settler, page: page)
        try await page.wait { library.notices.told == 1 }
        // Well past the rest, when a column that did not stop would have followed.
        try await Task.sleep(for: .milliseconds(300))
        #expect(page.editor.heldItemID == first.id && page.editor.pageItemID == first.id, "the column and its page stay on the item")

        // Choosing again goes ahead without the typing given up on, as the person was told.
        Self.choose(first.id, in: settler, page: page)
        Self.choose(second.id, in: settler, page: page)
        try await page.wait { page.editor.heldItemID == second.id }
        #expect(page.editor.pageItemID == second.id)
    }

    /// The page takes an item whose open began while the selection moved on before its hand-over was in: the column
    /// shows that item, the one typing reaches, until the selection's own item is on the page.
    @Test @MainActor func anOpenThatLandsAfterTheSelectionMovedOnShowsItsItemInTheColumn() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let third = library.add("Third\n")
        let page = try await Page(library: library)
        page.editor.onChange = { [library] id, text, read in library.updateBody(of: id, to: text, readAt: read) }
        try await page.show(first.id)
        // The page composes, refusing to hand over, until `window.held` is false.
        let leaving = page.editor.generation
        try await page.run("""
            window.held = true
            const flush = window.editor.flush.bind(window.editor)
            window.editor.flush = generation => {
                if (window.held) return { commandError: 'composition', message: 'Text composition is in progress' }
                return generation === \(leaving) ? 'First, typed\\n' : flush(generation)
            }
            """)

        let settler = BesideSettler(rest: .milliseconds(800))
        Self.choose(first.id, in: settler, page: page)
        Self.choose(second.id, in: settler, page: page)
        // The selection rests on the second item, whose open then waits on the composing page.
        try await Task.sleep(for: .milliseconds(1000))
        #expect(page.editor.heldItemID == first.id && page.editor.pageItemID == first.id)
        Self.choose(third.id, in: settler, page: page)
        try await page.run("window.held = false")

        // The second item's open lands well before the third's rest ends.
        try await page.wait { page.editor.pageItemID == second.id }
        #expect(page.editor.heldItemID == second.id, "the column shows the item on the page, not the one it left")
        try await page.wait { page.editor.heldItemID == third.id }
        #expect(page.editor.pageItemID == third.id)
        #expect(library.body(of: first.id)?.text == "First, typed\n", "the typing went to the item it was typed in")
        #expect(library.body(of: second.id)?.text == "Second\n")
        #expect(library.notices.waiting.isEmpty)
    }
}
