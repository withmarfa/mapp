import Foundation
import WebKit

/// Format > Link: a web, mail or phone address set on the selection, or taken off the link the caret is in.
extension EditorController {
    struct WebLinkRequest: Identifiable {
        let id = UUID()
        let note: ItemID
        /// The caret is in a link, which the sheet can then also change or remove.
        let removable: Bool
        /// The address of the link the caret is in, for the sheet to start from.
        var address = ""
    }

    func askForWebLink() {
        guard hasNote, isEditable, isReady, let noteID else { return }
        guard caret.marks.contains(.link) else {
            webLinkRequest = WebLinkRequest(note: noteID, removable: false)
            return
        }
        webLinkRequest = WebLinkRequest(note: noteID, removable: true, address: caret.href ?? "")
    }

    /// Sets the link on the selection. Whether the address was acceptable, as the page's `normalizeLinkAddress`
    /// reads it; the request stays open for the person to correct it otherwise.
    func setWebLink(_ address: String) async -> Bool {
        guard let request = webLinkRequest else { return false }
        guard request.note == noteID else {
            webLinkRequest = nil
            return true
        }
        let generation = generation
        let normalized = try? await webView.callAsyncJavaScript(
            "return window.editor.normalizeLinkAddress(typed)", arguments: ["typed": address], in: nil, contentWorld: .page)
        // The page was replaced, or the request closed, while the page was asked.
        guard webLinkRequest?.id == request.id, self.generation == generation else { return true }
        guard let normalized = normalized as? String else { return false }
        webLinkRequest = nil
        call("format", json("link"), json(normalized), String(generation))
        return true
    }

    /// Takes the link off the one the caret is in.
    func removeWebLink() {
        guard let request = webLinkRequest else { return }
        webLinkRequest = nil
        if request.note == noteID { call("format", json("link"), "null", String(generation)) }
    }

    func cancelWebLink() { webLinkRequest = nil }
}
