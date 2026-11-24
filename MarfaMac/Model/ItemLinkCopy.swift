import AppKit

nonisolated struct ItemLinkCopy: Equatable, Sendable {
    let url: URL

    var text: String { url.absoluteString }
}

extension ItemLibrary {
    /// Keep the current pasteboard contents if the link can't be built.
    func copyLink(of id: ItemID, to pasteboard: NSPasteboard = .general) async {
        guard let link = await itemLink(id) else {
            notices.tell(
                String(localized: "Can’t Copy Link"),
                String(localized: "This item doesn’t have a link yet. Try again once Marfa has finished syncing."))
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(link.text, forType: .URL)
        pasteboard.setString(link.text, forType: .string)
    }
}
