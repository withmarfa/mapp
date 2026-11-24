import Foundation

/// The person's text as the library holds it: typed text held at once and sent after a pause or a hand-over
/// (`TextPause`), saved against the version it was typed on, and kept while the source has not answered.
extension MarfaLibrary {
    /// Text read while the person's own text is still on its way, or waits to be sent, is older than what the library
    /// holds. Text taken in is a new read: the page follows `body(of:)` and shows it, so the next save starts from it,
    /// and where the server kept its own text over the person's, the page shows the server's.
    func hold(_ bodies: [ItemBody]) {
        for body in bodies {
            guard unsettledText[body.id] == nil, waitingText[body.id] == nil else {
                sourceText[body.id] = body
                continue
            }
            guard let record = records[body.id], record.body != body else { continue }
            record.body = body
        }
    }

    /// Text the page typed on the text the library gave at `readAt`. Text typed on the text the library holds is held
    /// at once and waits to be sent (`TextPause`), the latest report replacing the one before; text that comes back to
    /// what the copy holds while nothing is on its way needs no write. Text typed on older text goes at once
    /// (`saveText`), after any that waits.
    func takeTyped(_ text: String, of id: ItemID, readAt typedOn: ItemVersion, failing title: String) {
        let held = heldVersion(of: id)
        let readAt = ItemVersion(MarfaEngine.version(read: typedOn.rawValue, holding: held.rawValue))
        guard readAt == held, !sourceEnded else { return saveText(text, of: id, readAt: typedOn, failing: title) }
        if let waiting = waitingText[id], waiting.readAt != readAt { sendWaitingText(of: id) }
        if unsettledText[id] == nil, sourceText[id] == nil { sourceText[id] = records[id]?.body }
        if unsettledText[id] == nil, let copy = sourceText[id], copy.text == text {
            waitingText.removeValue(forKey: id)?.timer?.cancel()
            sourceText[id] = nil
            records[id]?.body = copy
            return
        }
        let now = ContinuousClock.now
        let isNew = waitingText[id] == nil
        var waiting = waitingText[id] ?? WaitingText(text: text, readAt: readAt, title: title, reports: 0, since: now, last: now)
        waiting.text = text
        waiting.title = title
        waiting.reports += 1
        waiting.last = now
        waitingText[id] = waiting
        records[id]?.body = ItemBody(id: id, text: text, version: readAt)
        if isNew { schedule(id, at: min(now + textPause.quiet, now + textPause.cap)) }
    }

    /// Whether any typed text waits to be sent.
    var hasWaitingText: Bool { !waitingText.isEmpty }

    /// Sends every text that waits, as every hand-over ends with, so nothing typed before it still waits after it.
    func sendWaitingText() {
        for id in Array(waitingText.keys) { sendWaitingText(of: id) }
    }

    /// Sends the text waiting for the item now. It is no step of an undo or redo running, whichever write sends it. An
    /// item gone, or no longer writable, since the text was typed gives the person the text back.
    private func sendWaitingText(of id: ItemID) {
        guard let waiting = waitingText.removeValue(forKey: id) else { return }
        waiting.timer?.cancel()
        guard let item = item(id), item.isWritable else {
            if unsettledText[id] == nil, let copy = sourceText.removeValue(forKey: id) { records[id]?.body = copy }
            return notices.notKept(waiting.title, text: waiting.text, reason: Self.cantChange)
        }
        within(nil) { saveText(waiting.text, of: id, readAt: waiting.readAt, failing: waiting.title, reports: waiting.reports) }
    }

    /// Any other write naming an item goes after the text typed on it, so the queue keeps the order the person made
    /// them in. A link write names its items by edge, so every text that waits goes first.
    func sendWaitingText(before write: ItemWrite) {
        guard !waitingText.isEmpty else { return }
        switch write {
        case .create, .editBody:
            break
        case .editProperties(let id, _, _), .retype(let id, _, _, _), .retier(let id, _, _), .transition(let id, _),
            .purge(let id, _), .tag(let id, _, _):
            sendWaitingText(of: id)
        case .link, .unlink, .moveEdge:
            sendWaitingText()
        }
    }

    /// One wake per waiting text: typing again only moves `last`, which this reads when it wakes. The wake keeps the
    /// library until the text is sent, so a library let go without `finish` still sends it; a closing source sends
    /// every text that waits, which cancels the wakes.
    private func schedule(_ id: ItemID, at due: ContinuousClock.Instant) {
        waitingText[id]?.timer?.cancel()
        waitingText[id]?.timer = Task {
            try? await Task.sleep(until: due)
            guard !Task.isCancelled else { return }
            waitEnded(id)
        }
    }

    /// Sends the waiting text once the cap has passed, or once the person has paused with no earlier text write of the
    /// item unanswered; otherwise wakes again when the pause or the cap is due. The answer to the earlier write
    /// comes here too (`answered`).
    func waitEnded(_ id: ItemID) {
        guard let waiting = waitingText[id] else { return }
        let now = ContinuousClock.now
        let cap = waiting.since + textPause.cap
        let paused = waiting.last + textPause.quiet
        if now >= cap || (now >= paused && unsettledText[id] == nil) { return sendWaitingText(of: id) }
        schedule(id, at: now >= paused ? cap : min(paused, cap))
    }

    private func heldVersion(of id: ItemID) -> ItemVersion {
        records[id]?.body?.version ?? records[id]?.item.version ?? ItemVersion(0)
    }

    /// The person's text, typed on the text the library gave at `readAt`, sent now. The first save sent on a version is
    /// merged against it where the copy has moved on; every later one follows the person's own, so their saves never
    /// come back conflicted against each other. Which it is is decided here, when the write is sent, so text that
    /// waited never follows a save that was not sent. Text typed on the text the library holds is held at once until
    /// the source answers. Text typed on older text, reported after the page took in newer text, is sent as made on
    /// what it was typed on (`queue-and-verdicts/as-read-sent-on-read`), so the server keeps both rather than this
    /// text replacing what the person never saw, and the library goes on holding the newer text. `reports` counts the
    /// page's reports the write carries.
    func saveText(_ text: String, of id: ItemID, readAt: ItemVersion, failing title: String, reports: Int = 1) {
        sendWaitingText(of: id)
        let held = heldVersion(of: id)
        let readAt = ItemVersion(MarfaEngine.version(read: readAt.rawValue, holding: held.rawValue))
        // A save held on a local create's version 0 is on version 1 once the answer lands, as `readAt` now is.
        let saved = savedOn[id].map { ItemVersion(MarfaEngine.version(read: $0.rawValue, holding: held.rawValue)) }
        let merge: BodyMerge = saved == readAt ? .following : .asRead
        let saving = Telemetry.begin(.library, "text.save", ("reports", reports))
        let write = submit(.editBody(id, text, base: readAt, merge: merge), failing: title)
        let shown = readAt == held ? ItemBody(id: id, text: text, version: readAt) : nil
        // Every write the engine takes ends in `.taken` or `.answered`; only one the source refuses to take, as it
        // has closed, gets neither, so nothing waits on it.
        if refusals[write] != nil {
            // Until a write is taken, the copy holds the text it held before, which a save refused before queueing
            // leaves on the page. Text that waited set it aside when it was typed.
            if unsettledText[id] == nil, sourceText[id] == nil { sourceText[id] = records[id]?.body }
            for earlier in unsettledText[id] ?? [] { textWrites[earlier]?.typed = nil }
            unsettledText[id, default: []].insert(write)
            unreadText[id, default: []].insert(write)
            textWrites[write] = TextWrite(item: id, shown: shown, typed: text)
            textSaves[write] = saving
        } else {
            saving.end()
            if unsettledText[id] == nil { sourceText[id] = nil }
        }
        guard let shown else { return }
        savedOn[id] = readAt
        records[id]?.body = shown
    }

    /// The copy holds the text the person typed once it takes their write, so text told before is older: the page
    /// keeps the typed text at the answer unless a read after the write tells the copy's.
    func took(_ write: WriteID) {
        guard let shown = textWrites[write]?.shown else { return }
        textWrites[write]?.shown = nil
        sourceText[shown.id] = shown
    }

    func hasUnreadSave(_ id: ItemID) -> Bool {
        unreadText[id] != nil || waitingText[id] != nil
    }

    /// A write answered before the copy took it, as one refused, is read too: nothing more will come of it.
    func read(_ write: WriteID) {
        guard let item = textWrites[write]?.item, unreadText[item]?.remove(write) != nil, unreadText[item]?.isEmpty == true
        else { return }
        unreadText[item] = nil
    }
}
