import AppKit

/// Edit > Find, through the system find bar above the page.
extension EditorController {
    /// Whether an item is on the page to find in.
    var hasItem: Bool { isPresented && isReady && pageItemID != nil }

    /// Does what an item of Edit > Find asks, through the system find bar above the page.
    func performFind(_ action: NSTextFinder.Action) {
        guard hasItem else { return }
        pageFinder.finder.performAction(action)
    }

    /// Opens the find bar on `text` and goes to its first match, once the page holds the item `id`: what Search
    /// Notes' Open at Match does. The words go to the system's find pasteboard, as typing them in any find bar does.
    func find(_ text: String, in id: ItemID) async {
        for _ in 0..<80 where !(hasItem && pageItemID == id) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard hasItem, pageItemID == id else { return }
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        performFind(.showFindInterface)
        try? await Task.sleep(for: .milliseconds(300))
        performFind(.nextMatch)
    }

    func findSelect(_ range: NSRange, state: FindState) {
        call("findSelect", String(range.location), String(NSMaxRange(range)), String(state.generation), json(state.snapshotID))
    }

    func findScroll(_ range: NSRange, state: FindState) {
        call("findScroll", String(range.location), String(state.generation), json(state.snapshotID))
    }

    func findReplace(_ range: NSRange, with text: String, state: FindState, batch: String) {
        call("findReplace", String(range.location), String(NSMaxRange(range)), json(text), String(state.generation), json(state.snapshotID), json(batch))
    }
}
