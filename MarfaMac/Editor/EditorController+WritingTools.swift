import Foundation

/// Writing Tools rewrites the page's text in place and can put the original back, so the text it shows part way
/// through is not yet the person's. Saving it would write a rewrite that is then undone, or lose the original.
extension EditorController {
    /// Keeps the page's edit instead of saving it while a Writing Tools session is open, and saves the latest one
    /// when the session ends (`writingToolsActivityChanged`). A flush saves it at once (`releaseHeldEdit`), and so
    /// does anything that replaces the page's text, so the edit is saved against the version it was made on.
    func holdEdit(_ markdown: String, of generation: Int) {
        // Never replace an edit held for another generation: it is the only copy of that text.
        if let held = heldEdit, held.generation != generation { releaseHeldEdit() }
        heldEdit = (markdown, generation)
    }

    /// Called when `WKWebView.isWritingToolsActive` changes (it is key-value observing compliant). Saves the held
    /// edit once the session has ended.
    func writingToolsActivityChanged() {
        if !isWritingToolsActive() { releaseHeldEdit() }
    }

    /// Saves the held edit now, as when the session has ended, the page is being flushed or its text is about to be
    /// replaced.
    func releaseHeldEdit() {
        guard let held = heldEdit else { return }
        heldEdit = nil
        report(held.markdown, of: held.generation)
    }
}
