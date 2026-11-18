import AppKit

/// Link to Item, and following a link to the item it names.
extension EditorController {
    // MARK: Linking to an item

    /// Asks the person which item to link to, and gives the page the link to write, or nil if they decline or the
    /// page has moved on from the item the command was typed in. A new request cancels the earlier one. A request
    /// made after the window went is answered with nothing.
    func chooseItemToLink(from itemID: ItemID) async -> String? {
        cancelLinkRequest()
        guard !windowIsGone, itemID == pageItemID, isEditable, isReady else { return nil }
        return await withCheckedContinuation { continuation in
            linking = continuation
            linkRequest = LinkRequest(itemID: itemID)
        }
    }

    /// Answers the page with the link to the item chosen, read from the library as the item is now, not as the
    /// picker listed it, and by identity, so an item renamed meanwhile is linked by its new name and one that shares
    /// its name is not mistaken for it. Whether it was answered: an item no link can name alone leaves the request
    /// open for the person to choose another.
    @discardableResult
    func finishLinkRequest(choosing id: ItemID) async -> Bool {
        guard linking != nil, let request = linkRequest, let link = await library?.bodyLink(to: id, in: request.itemID) else {
            return false
        }
        // The person may have gone on while the core was asked; the request is answered only if it is still theirs.
        guard linking != nil, linkRequest?.id == request.id else { return false }
        answerLinkRequest(link)
        return true
    }

    /// Any other end of the request answers the page with nothing, so it is never left waiting.
    func cancelLinkRequest() { answerLinkRequest(nil) }

    private func answerLinkRequest(_ link: String?) {
        let continuation = linking
        linking = nil
        linkRequest = nil
        continuation?.resume(returning: link)
    }

    // MARK: Following a link

    /// Opens the item a link in `source` names, as the core reads that very link from that item
    /// (`Items.linkCandidates`), and scrolls to the heading it asks for. A link the copy has not bound, which one
    /// item or more answer to, offers them in a menu. A link that names no item, or that the core cannot be asked
    /// about, opens nothing and beeps; no item is made for it. A click in an item the page has since left is ignored.
    func openItemLink(_ link: ItemLink, from source: ItemID) async {
        guard !windowIsGone, source == pageItemID, let library else { return }
        let answer = await library.linkAnswers(of: [link.raw], in: source)?.first
        guard !windowIsGone, source == pageItemID else { return }
        switch answer?.state {
        case .bound:
            guard let id = answer?.item, library.item(id) != nil else { return onUnopenableLink() }
            show(id, heading: link.heading)
        case .ambiguous, .unresolved:
            // A name the copy has not bound is the person's to confirm, since the server may hold another item by it.
            let held = (answer?.candidates ?? []).filter { library.item($0) != nil }
            guard !held.isEmpty else { return onUnopenableLink() }
            let choose = onChooseAmbiguousLink ?? { [weak self] ids, pick in self?.popUpCandidates(ids, pick: pick) }
            choose(held) { [weak self] id in self?.show(id, heading: link.heading) }
        case nil:
            onUnopenableLink()
        }
    }

    private func show(_ id: ItemID, heading: String?) {
        pendingHeading = heading.map { (id, $0) }
        if id == pageItemID { revealPendingHeading(in: id) } else { onOpenItem(id) }
    }

    /// A menu at the pointer naming each item a link could mean, by title.
    private func popUpCandidates(_ ids: [ItemID], pick: @escaping (ItemID) -> Void) {
        let menu = NSMenu()
        let chosen = CandidateChoice(pick: pick)
        for id in ids {
            let entry = NSMenuItem(title: library?.item(id)?.displayTitle ?? id.rawValue, action: #selector(CandidateChoice.choose(_:)), keyEquivalent: "")
            entry.target = chosen
            entry.representedObject = id.rawValue
            menu.addItem(entry)
        }
        // A menu item holds its target weakly, and `popUp` returns once the choice is made, so keep the target alive to then.
        withExtendedLifetime(chosen) { _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    }

    /// Scrolls the page to the heading of the item on it that has this text, as a link to the item's own heading does.
    func revealHeading(_ text: String) {
        guard isReady else { return }
        call("revealHeading", json(text), String(generation))
    }

    /// The headings the Outline lists for `id`: those the page reported for the item now on it, and none while the page
    /// holds another item or has not loaded this one.
    func headings(of id: ItemID) -> [OutlineHeading] {
        guard isShowing(id) else { return [] }
        return outline?.headings(for: id) ?? []
    }

    /// Scrolls the page to the n-th heading (from 0) of its own list, under the load that list was reported for, so a
    /// row made from an earlier load reveals nothing: the page refuses a generation that is not on it.
    func revealHeading(at ordinal: Int) {
        guard isReady, let outline else { return }
        call("revealHeadingAt", String(ordinal), String(outline.generation))
    }

    func revealPendingHeading(in itemID: ItemID) {
        guard let pending = pendingHeading, pending.itemID == itemID, isReady else { return }
        pendingHeading = nil
        call("revealHeading", json(pending.text), String(generation))
    }

    /// Tells the page when the library's items change, since a link there may then name an item or none. Changes
    /// come in bursts, as typing is saved, so the page hears once they pause. Followed here, as the header is, so
    /// the page keeps up whether or not a view is updated.
    func watchLinks() {
        guard !isWatchingLinks, let library else { return }
        isWatchingLinks = true
        withObservationTracking {
            _ = library.items(in: .allItems)
            // A type given another icon or tone changes the mark of every link to its items.
            _ = library.membershipRevision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !windowIsGone else { return }
                isWatchingLinks = false
                if pageItemID != nil, isReady { call("linksChanged") }
                watchLinks()
            }
        }
    }
}

/// Carries a menu choice back to the link that offered it.
private final class CandidateChoice: NSObject {
    let pick: (ItemID) -> Void
    init(pick: @escaping (ItemID) -> Void) { self.pick = pick }
    @objc func choose(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        pick(ItemID(raw))
    }
}
