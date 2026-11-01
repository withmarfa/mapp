import Foundation
import WebKit

/// Format > Link: a web, mail or phone address set on the selection, or taken off the link the caret is in.
extension EditorController {
    struct WebLinkRequest: Identifiable {
        let id = UUID()
        let note: ItemID
        /// The load of the note the sheet was opened on; a reload gives the page another, and the selection the sheet
        /// is for is gone with it.
        let generation: Int
        /// The caret is in a link, which the sheet can then also change or remove.
        let removable: Bool
        /// The address of the link the caret is in, for the sheet to start from.
        var address = ""
    }

    func askForWebLink() {
        guard hasNote, isEditable, isReady, let noteID else { return }
        guard caret.marks.contains(.link) else {
            webLinkRequest = WebLinkRequest(note: noteID, generation: generation, removable: false)
            return
        }
        webLinkRequest = WebLinkRequest(note: noteID, generation: generation, removable: true, address: caret.href ?? "")
    }

    /// Sets the link on the selection. Whether the address was acceptable, as the page's `normalizeLinkAddress`
    /// reads it; the request stays open for the person to correct it otherwise. A request the page has moved on from
    /// is closed and nothing is written.
    func setWebLink(_ address: String) async -> Bool {
        guard let request = webLinkRequest else { return false }
        guard isCurrent(request) else { return true }
        let normalized: Any?
        do {
            normalized = try await webView.callAsyncJavaScript(
                "return window.editor.normalizeLinkAddress(typed)", arguments: ["typed": address], in: nil, contentWorld: .page)
        } catch {
            // A fault in the page says nothing about the address, so the sheet closes instead of blaming it.
            guard webLinkRequest?.id == request.id else { return true }
            webLinkRequest = nil
            library?.notices.tell(String(localized: "Editor Couldn’t Complete the Action"), error.localizedDescription)
            return true
        }
        // The page was replaced, or the request closed, while the page was asked.
        guard webLinkRequest?.id == request.id, isCurrent(request) else { return true }
        guard let normalized = normalized as? String else { return false }
        webLinkRequest = nil
        call("format", json("link"), json(normalized), String(request.generation))
        return true
    }

    /// Takes the link off the one the caret is in.
    func removeWebLink() {
        guard let request = webLinkRequest else { return }
        let current = isCurrent(request)
        webLinkRequest = nil
        if current { call("format", json("link"), "null", String(request.generation)) }
    }

    func cancelWebLink() { webLinkRequest = nil }

    /// Ends both requests the page can be waiting on or the sheets can show, for a page that is about to show another
    /// note or text, or that is going away.
    func cancelRequests() {
        cancelLinkRequest()
        cancelWebLink()
    }

    /// Whether the request is still for the text on the page. One that is not is closed, since the selection it was
    /// opened for is gone and the link would land wherever the reloaded page's selection is.
    private func isCurrent(_ request: WebLinkRequest) -> Bool {
        guard request.note == noteID, request.generation == generation else {
            if webLinkRequest?.id == request.id { webLinkRequest = nil }
            return false
        }
        return true
    }
}
