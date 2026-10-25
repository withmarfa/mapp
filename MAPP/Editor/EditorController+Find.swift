import AppKit

/// Edit > Find, through the system find bar above the page.
extension EditorController {
    /// Whether a note is on the page to find in.
    var hasNote: Bool { isPresented && isReady && noteID != nil }

    /// Does what an item of Edit > Find asks, through the system find bar above the page.
    func performFind(_ action: NSTextFinder.Action) {
        guard hasNote else { return }
        pageFinder.finder.performAction(action)
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
