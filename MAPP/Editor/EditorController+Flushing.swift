import AppKit
import WebKit
import os

/// Handing over the page's last edit before a note, a window or the library goes.
extension EditorController {
    /// Hands over an edit the page has not yet reported, as when the window closes or another note is shown.
    /// The page answers in order, so this lands before anything asked of it later. The reply keeps this controller alive until it arrives.
    ///
    /// A page that cannot hand over its edit within `flushLimit` is given up on: the person is told, and the next
    /// flush goes ahead without it, so a stuck page never holds the window or the app for good. What the page
    /// last reported is already saved; only what it never reported is lost. Until then it is asked again only while
    /// it is composing or importing a picture. Any other failure in the page, an exception or another refusal, is
    /// logged and told at once with its own message, and the page is given up on the same way.
    ///
    /// Outside text reloading the note mid-flush leaves the note the one being flushed, so the flush goes ahead. A
    /// flush whose note was replaced on the page stops, and the person is told why.
    ///
    /// Flushes take turns, and what one does once its edit is in is part of its turn: a selection's hand-over puts
    /// the next note on the page, and leaving the note empties it. So a flush asked for meanwhile, as when the window
    /// closes or the app quits just after a selection, waits and then hands over whatever is on the page, instead of
    /// finding its note replaced. Those waiting behind a flush that fails fail with it, without asking the page: they
    /// were waiting on the edit it could not keep, and the person has been told once.
    func flush(then done: @escaping (Bool) -> Void = { _ in }) {
        releaseHeldEdit()
        guard !isFlushing else { return waitingFlushes.append(done) }
        isFlushing = true
        handOver { [self] kept in
            isFlushing = false
            let waiting = waitingFlushes
            waitingFlushes = []
            done(kept)
            guard kept else { return waiting.forEach { $0(false) } }
            // `done` may have started a flush of its own, which keeps its turn.
            waitingFlushes = waiting + waitingFlushes
            if !isFlushing, !waitingFlushes.isEmpty { flush(then: waitingFlushes.removeFirst()) }
        }
    }

    /// One turn of `flush`: asks the page for its last edit and answers once.
    private func handOver(then done: @escaping (Bool) -> Void) {
        guard let noteID else { return done(true) }
        let generation = generation
        // A page that is not ready has nothing unreported: it reports every change as it is made, and one whose
        // process ended comes back with the text it last reported.
        guard isReady, generation != abandonedGeneration else { return done(true) }
        var finished = false
        var watchdog: Task<Void, Never>?
        func finish(_ kept: Bool) {
            guard !finished else { return }
            finished = true
            watchdog?.cancel()
            done(kept)
        }
        func capture() {
            guard !finished else { return }
            guard self.noteID == noteID else { return replaced() }
            guard isReady else { return finish(true) }
            // Asked for the generation the flush began on even after outside text reloaded the note: the page puts
            // a reload off while the person composes, so it can still hold text of that generation. A page that
            // has moved past it reported that text as it moved, and answers nil.
            // An exception is caught here and answered as a refusal, since the page's error listener hears one thrown
            // into a script the app runs only as "Script error.", and would tell the person that.
            let script = """
                (() => {
                  try { return window.editor.flush(\(generation)) }
                  catch (error) { return { commandError: 'exception', message: String(error) } }
                })()
                """
            webView.evaluateJavaScript(script) { [self] result, error in
                // A reply that comes after the page was given up on still holds the person's latest text.
                if error == nil, let markdown = result as? String { report(markdown, of: generation) }
                guard !finished else { return }
                let refusal = result as? [String: Any]
                let code = refusal?["commandError"] as? String
                // A page composing or importing a picture, or holding back a reload until then, hands its edit over
                // once it is done. A call that did not
                // run in the page, as when its process ended, is asked again too, and then finds the page not ready.
                if code.map(Self.passingFlushRefusals.contains) == true || error.map(Self.ranInPage) == false {
                    Task { try? await Task.sleep(for: .milliseconds(50)); capture() }
                    return
                }
                if let error { return failed(error.localizedDescription) }
                if let code { return failed(refusal?["message"] as? String ?? code) }
                guard self.noteID == noteID else { return replaced() }
                finish(true)
            }
        }
        func replaced() {
            tellNotSaved(noteID, reason: Self.replacedReason)
            finish(false)
        }
        // The page answered, so it is not stuck, but asking again would only fail again. It is given up on as a page
        // that stopped answering is, so trying again goes ahead without it.
        func failed(_ message: String) {
            abandonedGeneration = self.generation
            Telemetry.logger(.editor).error("flush failed: \(message)")
            tellNotSaved(noteID, reason: String(localized: "The editor ran into a problem (“\(message)”), so MAPP couldn’t save your most recent typing. Everything before it is saved. To go ahead without it, try again."))
            finish(false)
        }
        // Held weakly, so a finished flush does not keep a closed editor among the open ones until the limit.
        watchdog = Task { [weak self, flushLimit] in
            try? await Task.sleep(for: flushLimit)
            guard !finished else { return }
            guard let self else {
                preconditionFailure("An unfinished flush's pending reply or retry holds its editor.")
            }
            guard self.noteID == noteID else {
                tellNotSaved(noteID, reason: Self.replacedReason)
                return finish(false)
            }
            // The page answers in order, so one that has not answered this flush holds every later load too.
            abandonedGeneration = self.generation
            tellNotSaved(noteID, reason: String(localized: "The editor stopped responding, so MAPP couldn’t save your most recent typing. Everything before it is saved. To go ahead without it, try again."))
            finish(false)
        }
        capture()
    }

    /// The page reports each change as it is made, so what it never reported is not on the page to give back.
    private func tellNotSaved(_ noteID: ItemID, reason: String) {
        let title = library?.item(noteID).map { String(localized: "Couldn’t Save “\($0.title)”") }
        library?.notices.notKept(title ?? String(localized: "Couldn’t Save Note"), text: nil, reason: reason)
    }

    /// The page's refusals to hand over its edit that pass: a composition, a picture still being imported, and a load or
    /// reload the page puts off until either ends (`stale-document`, as the flush asks for the generation last sent).
    private static let passingFlushRefusals: Set<String> = ["composition", "operation-pending", "stale-document"]

    /// Whether the script ran in the page and failed there, rather than never reaching it.
    private static func ranInPage(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == WKError.errorDomain
            && [WKError.javaScriptExceptionOccurred.rawValue, WKError.javaScriptResultTypeIsUnsupported.rawValue].contains(error.code)
    }

    private static var replacedReason: String {
        String(localized: "Another note opened before MAPP finished saving this one, so your most recent typing might not be saved. Try again.")
    }

    /// Destructive transitions proceed only once every editor has handed over its current text and its window's
    /// titles. Where the window or the library goes, a title that still cannot be saved stops them as a failed
    /// capture does, since it would otherwise be lost; where they stay, as when a note is deleted, it waits.
    static func flushAll(leaving: Bool = true, trace: QuitTrace? = nil, then done: @escaping (Bool) -> Void) {
        let editors = open.allObjects
        let gate = Gate(waitingFor: editors.count, then: done)
        // One refusal is told, from the window that holds it, since that window comes forward and only one can.
        var told = false
        for editor in editors {
            trace?.begin(.titles)
            let titlesSaved = editor.saveTitles(tellingRefusal: leaving && !told)
            trace?.end(.titles)
            guard titlesSaved || !leaving else {
                told = true
                gate.arrive(false)
                continue
            }
            if editor.isFlushing { trace?.editorWaitsItsTurn() }
            editor.flush(then: gate.arrive)
        }
    }

    private final class Gate {
        private var remaining: Int
        private var succeeded = true
        private var action: ((Bool) -> Void)?
        init(waitingFor count: Int, then action: @escaping (Bool) -> Void) {
            remaining = count
            self.action = action
            if count == 0 { open(true) }
        }
        func arrive(_ success: Bool) {
            succeeded = succeeded && success
            remaining -= 1
            if remaining <= 0 { open(succeeded) }
        }
        func open(_ success: Bool) {
            action?(success)
            action = nil
        }
    }

    /// The window is gone and its text already flushed, so its drafts and page take no part in later flushes, even
    /// while SwiftUI still holds the editor for a moment.
    func windowWent() {
        windowIsGone = true
        requestedNoteID = nil
        cancelLinkRequest()
        titleDrafts = nil
        for (id, embeds) in pendingEmbeds { notInText(embeds, of: id) }
        pendingEmbeds = [:]
        pictureSettingWatch?.cancel()
        Self.open.remove(self)
    }

    /// Tries every title the window holds unsaved, since a name taken before may be free now, leaving out items that
    /// are gone or whose title cannot be set. Whether all are saved; if not, and asked to, says which is not.
    func saveTitles(tellingRefusal: Bool) -> Bool {
        guard let drafts = titleDrafts, let library else { return true }
        var refused: (id: ItemID, draft: String, item: String)?
        for id in drafts.unsavedTitles {
            guard let item = library.item(id), library.canSetTitle(of: item) else { continue }
            if !drafts.saveTitle(of: id, in: library, undoManager: webView.window?.undoManager), refused == nil {
                refused = (id, drafts.draft(for: id, key: "title").text, item.title)
            }
        }
        guard let refused else { return true }
        if tellingRefusal {
            let message = refused.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "The title for “\(refused.item)” is empty. Open the item to enter a title or discard your changes.")
                : String(localized: "The title “\(refused.draft)” for “\(refused.item)” couldn’t be saved. Open the item to change the title or discard your changes.")
            library.notices.tell(String(localized: "Couldn’t Save Title"), message)
            // The draft is shown only in its own window, so that window comes forward with the item.
            webView.window?.makeKeyAndOrderFront(nil)
            onShowRefusedTitle(refused.id)
        }
        return false
    }
}
