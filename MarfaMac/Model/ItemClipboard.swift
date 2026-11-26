import Foundation

extension Notices {
    /// Whether the clipboard holds the text of a change not kept that a window has shown and the person has not answered,
    /// which nothing else may write over (`show(in:copying:)`).
    var holdsTextOnClipboard: Bool {
        waiting.contains { $0.isNotKept && $0.text != nil && isShown($0.id) }
    }
}

extension ItemLibrary {
    /// Whether a command that copies to the clipboard may do so now. While the person's unanswered text is on it, none
    /// may, and they are told why.
    func mayWriteClipboard() -> Bool {
        guard notices.holdsTextOnClipboard else { return true }
        notices.tell(
            String(localized: "Clipboard Not Changed"),
            String(localized: "Your unsaved text is still on the clipboard, so nothing was copied over it. Paste it back or answer its alert, then try again."))
        return false
    }
}
