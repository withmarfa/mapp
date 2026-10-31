import Foundation

/// Writing Tools rewrites the page's text in place and can put the original back, so the text it shows part way
/// through is not yet the person's. Saving it would write a rewrite that is then undone, or lose the original.
extension EditorController {
    /// Keeps the page's edit instead of saving it while a Writing Tools session is open, and saves the latest one
    /// when the session ends. A flush saves it at once (`releaseHeldEdit`), so closing the window or quitting during a
    /// session keeps whatever the page shows.
    func holdEdit(_ markdown: String, of generation: Int) {
        heldEdit = (markdown, generation)
        guard heldEditWatch == nil else { return }
        // WebKit does not announce the end of a session to the app, so it is asked while an edit waits.
        heldEditWatch = Task { [weak self] in
            while let self, isWritingToolsActive() {
                try? await Task.sleep(for: .milliseconds(200))
                // A flush has saved the edit and ended this watch; a later edit has a watch of its own.
                if Task.isCancelled { return }
            }
            self?.releaseHeldEdit()
        }
    }

    /// Saves the held edit now, as when the session has ended or the page is being flushed.
    func releaseHeldEdit() {
        heldEditWatch?.cancel()
        heldEditWatch = nil
        guard let held = heldEdit else { return }
        report(held.markdown, of: held.generation)
    }
}
