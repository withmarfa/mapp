import AppKit

nonisolated struct ItemLinkCopy: Equatable, Sendable {
    let url: URL

    var text: String { url.absoluteString }
}

/// Where the server's own link to an item is read: its `https` link, the address of the item's page, which only the
/// server can give, since it follows the instance's sign-in address.
nonisolated protocol ItemLinkSource: Sendable {
    /// The `https` link the server gives for the item, whichever place it is in. It throws when the server can't be
    /// reached or answers an error (an item it doesn't hold yet included). It only reads.
    func webLink(of id: ItemID) async throws -> URL
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
