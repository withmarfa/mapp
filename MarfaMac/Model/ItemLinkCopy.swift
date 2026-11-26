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

nonisolated enum ItemLinkLimit {
    /// The most items Share and Copy Links take at once: each link is a read from the server.
    static let items = 100
    /// How many of those reads are in flight at a time.
    static let inFlight = 20
}

extension ItemLibrary {
    /// Keep the current pasteboard contents if the link can't be built, or if they changed while it was read.
    func copyLink(of id: ItemID, to pasteboard: NSPasteboard = .general) async {
        let before = pasteboard.changeCount
        guard let link = await itemLink(id) else {
            notices.tell(
                String(localized: "Can’t Copy Link"),
                String(localized: "This item doesn’t have a link yet. Try again once Marfa has finished syncing."))
            return
        }
        guard pasteboard.changeCount == before else { return tellPasteboardChanged() }
        pasteboard.clearContents()
        pasteboard.setString(link.text, forType: .URL)
        pasteboard.setString(link.text, forType: .string)
    }

    /// The links of these items, in the order given. An item the copy no longer holds, as one another Mac deleted, and one
    /// that has no link yet are counted in `missing`. More than `ItemLinkLimit.items` ask the server for nothing: the
    /// person is told and the answer is nil.
    func links(of ids: [ItemID]) async -> (links: [ItemLinkCopy], missing: Int)? {
        guard ids.count <= ItemLinkLimit.items else {
            notices.tell(
                String(localized: "Too Many Items for Links"),
                String(localized: "Share and Copy Links take up to \(ItemLinkLimit.items) items at once, because each link comes from the server. Choose fewer items."))
            return nil
        }
        let held = ids.filter { item($0) != nil }
        var links: [ItemLinkCopy] = []
        for start in stride(from: 0, to: held.count, by: ItemLinkLimit.inFlight) {
            // A batch is asked at once, since a link comes from the server, and its answers keep the order given.
            let asking = held[start..<min(start + ItemLinkLimit.inFlight, held.count)].map { id in Task { await self.itemLink(id) } }
            for task in asking { if let link = await task.value { links.append(link) } }
        }
        return (links, ids.count - links.count)
    }

    /// Copies the links of several items, one to a line in the order given. The links there are copied and the person is
    /// told how many items had none; with none to copy, or if the pasteboard changed while they were read, it is left as
    /// it was.
    func copyLinks(of ids: [ItemID], to pasteboard: NSPasteboard = .general) async {
        let before = pasteboard.changeCount
        guard let found = await links(of: ids) else { return }
        guard !found.links.isEmpty else {
            notices.tell(
                String(localized: "Can’t Copy Links"),
                String(localized: "These items don’t have links yet. Try again once Marfa has finished syncing."))
            return
        }
        guard pasteboard.changeCount == before else { return tellPasteboardChanged() }
        pasteboard.clearContents()
        pasteboard.setString(found.links.map(\.text).joined(separator: "\n"), forType: .string)
        if found.missing > 0 {
            notices.tell(
                String(localized: "Some Links Not Copied"),
                String(localized: "\(found.missing) of the items don’t have a link yet, so only the others were copied."))
        }
    }

    /// Something else wrote to the pasteboard while a link was read, which may be text kept for the person (`Notices.notKept`).
    private func tellPasteboardChanged() {
        notices.tell(
            String(localized: "Links Not Copied"),
            String(localized: "The clipboard changed while the links were being found, so it was left as it is. Try again."))
    }
}
