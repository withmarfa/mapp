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
    func finishLinkRequest(choosing id: ItemID) -> Bool {
        guard linking != nil, let source = linkRequest?.note, let link = library?.bodyLink(to: id, in: source) else { return false }
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

    /// Opens the note a link in `source` names, as the library reads that very link, and scrolls to the heading it asks
    /// for. A link that names no note, or more than one, or that the library has not been able to look up, opens
    /// nothing and beeps; no note is made for it. A click in a note the page has since left is ignored.
    func openNote(_ link: NoteLink, from source: ItemID) {
        guard !windowIsGone, source == noteID, let library else { return }
        guard case .resolved(let id) = library.resolveLink(link, in: source), library.item(id) != nil else {
            return onUnopenableLink()
        }
        pendingHeading = link.heading.map { (id, $0) }
        if id == noteID { revealPendingHeading(in: id) } else { onOpenNote(id) }
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
