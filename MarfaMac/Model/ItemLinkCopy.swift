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

    /// The links of these items, in the order given. An item the copy no longer holds, as one another Mac deleted, and one
    /// that has no link yet are counted in `missing`.
    func links(of ids: [ItemID]) async -> (links: [ItemLinkCopy], missing: Int) {
        let held = ids.filter { item($0) != nil }
        // Each is asked at once, since a link comes from the server, and the answers keep the order given.
        let asking = held.map { id in Task { await self.itemLink(id) } }
        var found: [ItemLinkCopy?] = []
        for task in asking { found.append(await task.value) }
        let links = found.compactMap { $0 }
        return (links, ids.count - links.count)
    }

    /// Copies the links of several items, one to a line in the order given. The links there are copied and the person is
    /// told how many items had none; with none to copy, the pasteboard is left as it was.
    func copyLinks(of ids: [ItemID], to pasteboard: NSPasteboard = .general) async {
        let found = await links(of: ids)
        guard !found.links.isEmpty else {
            notices.tell(
                String(localized: "Can’t Copy Links"),
                String(localized: "These items don’t have links yet. Try again once Marfa has finished syncing."))
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(found.links.map(\.text).joined(separator: "\n"), forType: .string)
        if found.missing > 0 {
            notices.tell(
                String(localized: "Some Links Not Copied"),
                String(localized: "\(found.missing) of the items don’t have a link yet, so only the others were copied."))
        }
    }
}
