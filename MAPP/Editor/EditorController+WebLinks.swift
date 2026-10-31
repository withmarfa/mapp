import Foundation

/// Format > Link: a web, mail or phone address set on the selection, or taken off the link the caret is in.
extension EditorController {
    struct WebLinkRequest: Identifiable {
        let id = UUID()
        let note: ItemID
        /// The caret is in a link, which the sheet can then also remove.
        let removable: Bool
    }

    func askForWebLink() {
        guard hasNote, isEditable, isReady, let noteID else { return }
        webLinkRequest = WebLinkRequest(note: noteID, removable: caret.marks.contains(.link))
    }

    /// Sets the link on the selection, or takes it off with nil. Whether the address was acceptable; the request
    /// stays open for the person to correct it otherwise.
    @discardableResult
    func finishWebLink(_ address: String?) -> Bool {
        guard let request = webLinkRequest else { return false }
        guard request.note == noteID else {
            webLinkRequest = nil
            return true
        }
        let destination: String
        if let address {
            guard let normalized = WebLinkAddress.normalized(address) else { return false }
            destination = json(normalized)
        } else {
            destination = "null"
        }
        webLinkRequest = nil
        call("format", json("link"), destination, String(generation))
        return true
    }

    func cancelWebLink() { webLinkRequest = nil }
}

/// What the Link command accepts: the schemes Inkkit's links may use by default.
nonisolated enum WebLinkAddress {
    /// The address as it will be written, with `https://` or `mailto:` added where the person left the scheme off,
    /// or nil when it is not a web, mail or phone address.
    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let hasScheme = trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
        let candidate: String
        if hasScheme {
            candidate = trimmed
        } else if trimmed.contains("@"), !trimmed.contains("/") {
            candidate = "mailto:" + trimmed
        } else {
            candidate = "https://" + trimmed
        }
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https": return url.host()?.isEmpty == false ? candidate : nil
        case "mailto", "tel": return candidate.count > scheme.count + 1 ? candidate : nil
        default: return nil
        }
    }
}
