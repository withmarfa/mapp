import AppKit

/// Link to Note, and following a link to the note it names.
extension EditorController {
    // MARK: Linking to a note

    /// Asks the person which note to link to, and gives the page the link to write, or nil if they decline or the
    /// page has moved on from the note the command was typed in. A new request cancels the earlier one. A request
    /// made after the window went is answered with nothing.
    func chooseNoteToLink(from note: ItemID) async -> String? {
        cancelLinkRequest()
        guard !windowIsGone, note == noteID, isEditable, isReady else { return nil }
        return await withCheckedContinuation { continuation in
            linking = continuation
            linkRequest = LinkRequest(note: note)
        }
    }

    /// Answers the page with the link to the note chosen, read from the library as the note is now, not as the
    /// picker listed it, and by identity, so a note renamed meanwhile is linked by its new name and one that shares
    /// its name is not mistaken for it. Whether it was answered: a note no link can name alone leaves the request
    /// open for the person to choose another.
    @discardableResult
    func finishLinkRequest(choosing id: ItemID) async -> Bool {
        guard linking != nil, let request = linkRequest, let link = await library?.bodyLink(to: id, in: request.note) else {
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

    /// Opens the note a link in `source` names, as the core reads that very link from that note
    /// (`Items.linkCandidates`), and scrolls to the heading it asks for. A link the copy has not bound, which one
    /// note or more answer to, offers them in a menu. A link that names no note, or that the core cannot be asked
    /// about, opens nothing and beeps; no note is made for it. A click in a note the page has since left is ignored.
    func openNote(_ link: NoteLink, from source: ItemID) async {
        guard !windowIsGone, source == noteID, let library else { return }
        let answer = await library.linkAnswers(of: [link.raw], in: source)?.first
        guard !windowIsGone, source == noteID else { return }
        switch answer?.state {
        case .bound:
            guard let id = answer?.item, library.item(id) != nil else { return onUnopenableLink() }
            show(id, heading: link.heading)
        case .ambiguous, .unresolved:
            // A name the copy has not bound is the person's to confirm, since the server may hold another note by it.
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
        if id == noteID { revealPendingHeading(in: id) } else { onOpenNote(id) }
    }

    /// A menu at the pointer naming each note a link could mean, by title.
    private func popUpCandidates(_ ids: [ItemID], pick: @escaping (ItemID) -> Void) {
        let menu = NSMenu()
        let chosen = CandidateChoice(pick: pick)
        for id in ids {
            let entry = NSMenuItem(title: library?.item(id)?.displayTitle ?? id.rawValue, action: #selector(CandidateChoice.choose(_:)), keyEquivalent: "")
            entry.target = chosen
            entry.representedObject = id.rawValue
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func revealPendingHeading(in note: ItemID) {
        guard let pending = pendingHeading, pending.note == note, isReady else { return }
        pendingHeading = nil
        call("revealHeading", json(pending.text), String(generation))
    }

    /// Tells the page when the library's notes change, since a link there may then name a note or none. Changes
    /// come in bursts, as typing is saved, so the page hears once they pause. Followed here, as the header is, so
    /// the page keeps up whether or not a view is updated.
    func watchLinks() {
        guard !isWatchingLinks, let library else { return }
        isWatchingLinks = true
        withObservationTracking {
            _ = library.items(in: .allNotes)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !windowIsGone else { return }
                isWatchingLinks = false
                if noteID != nil, isReady { call("linksChanged") }
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
