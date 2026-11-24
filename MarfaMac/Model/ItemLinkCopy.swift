import AppKit

/// The link Copy Link puts on the pasteboard for an item: the one text every Copy Link command copies.
nonisolated struct ItemLinkCopy: Equatable, Sendable {
    let url: URL

    var text: String { url.absoluteString }
}

extension ItemLibrary {
    /// Copy Link, as every place that offers it does it: the row menus, the item page's More menu, the menu bar and
    /// the palette. The text goes on the pasteboard as a string and as a URL. Where `itemLink` has none to give, the
    /// person is told and the pasteboard is left as it was.
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
