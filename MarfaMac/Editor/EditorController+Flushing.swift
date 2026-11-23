import AppKit
import WebKit
import os

/// Handing over the page's last edit before an item, a window or the library goes.
extension EditorController {
    /// Hands over an edit the page has not yet reported, as when the window closes or another item is shown.
    /// The page answers in order, so this lands before anything asked of it later. The reply keeps this controller alive until it arrives.
    ///
    /// A page that cannot hand over its edit within `flushLimit` is given up on: the person is told, and the next
    /// flush goes ahead without it, so a stuck page never holds the window or the app for good. What the page
    /// last reported is already saved; only what it never reported is lost. Until then it is asked again only while
    /// it is composing or importing a picture. Any other failure in the page, an exception or another refusal, is
    /// logged with the page's own words and told at once as a problem with the editor, with the step to take, and the
    /// page is given up on the same way.
    ///
    /// A page that went down after it had been ready (`pageWentDown`) may have lost what the person typed last, so a
    /// flush fails while it is down, and one under way when it went down fails too.
    ///
    /// Outside text reloading the item mid-flush leaves the item the one being flushed, so the flush goes ahead. A
    /// flush whose item was replaced on the page stops, and the person is told why.
    ///
    /// Flushes take turns, and what one does once its edit is in is part of its turn: a selection's hand-over puts
    /// the next item on the page, and leaving the item empties it. So a flush asked for meanwhile, as when the window
    /// closes or the app quits just after a selection, waits and then hands over whatever is on the page, instead of
    /// finding its item replaced. Those waiting behind a flush that fails fail with it, without asking the page: they
    /// were waiting on the edit it could not keep, and the person has been told once.
    func flush(then done: @escaping (Bool) -> Void = { _ in }) {
        releaseHeldEdit()
        guard !isFlushing else { return waitingFlushes.append(done) }
        isFlushing = true
        handOver { [self] kept in
            // An edit the page reported before the hand-over but that arrived during it was held, and the page's
            // answer leaves it out, since the page counts it as reported.
            releaseHeldEdit()
            // What the page handed over goes to the library's queue now, not after the pause typing waits for.
            library?.sendWaitingText()
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
        guard let pageItemID else { return done(true) }
        let generation = generation
        let losses = pageLosses
        if !isReady, pageLoss != nil { return done(!lossHoldsFlush()) }
        // A page still loading for the first time has nothing unreported: it reports every change as it is made.
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
            guard self.pageItemID == pageItemID else { return replaced() }
            // The page went down while this flush waited for it, taking what it held back.
            guard losses == pageLosses else {
                tellPageLoss()
                return finish(false)
            }
            guard isReady else { return finish(true) }
            // Asked for the generation the flush began on even after outside text reloaded the item: the page puts
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
                if let error { return failed(detail: error.localizedDescription) }
                if let code { return failed(detail: refusal?["message"] as? String ?? code) }
                guard self.pageItemID == pageItemID else { return replaced() }
                finish(true)
            }
        }
        func replaced() {
            tellNotSaved(pageItemID, reason: Self.replacedReason)
            finish(false)
        }
        // The page answered, so it is not stuck, but asking again would only fail again. It is given up on as a page
        // that stopped answering is, so trying again goes ahead without it.
        // `detail` is JavaScript's or WebKit's own text, for the log alone.
        func failed(detail: String) {
            abandonedGeneration = self.generation
            Telemetry.logger(.editor).error("flush failed: \(detail)")
            tellNotSaved(pageItemID, reason: String(localized: "The editor ran into a problem, so the app couldn’t save your most recent typing. Everything before it is saved. To go ahead without it, try again."))
            finish(false)
        }
        // Held weakly, so a finished flush does not keep a closed editor among the open ones until the limit.
        watchdog = Task { [weak self, flushLimit] in
            try? await Task.sleep(for: flushLimit)
            guard !finished else { return }
            guard let self else {
                preconditionFailure("An unfinished flush's pending reply or retry holds its editor.")
            }
            guard self.pageItemID == pageItemID else {
                tellNotSaved(pageItemID, reason: Self.replacedReason)
                return finish(false)
            }
            // The page answers in order, so one that has not answered this flush holds every later load too.
            abandonedGeneration = self.generation
            tellNotSaved(pageItemID, reason: String(localized: "The editor stopped responding, so the app couldn’t save your most recent typing. Everything before it is saved. To go ahead without it, try again."))
            finish(false)
        }
        capture()
    }

    /// Records that the page went down after it had been ready, as when its process ended or loading it again failed,
    /// and tells the person. Where it held no item they could edit, nothing typed can be missing.
    func pageWentDown(comingBack: Bool) {
        guard let item = pageLoss?.item ?? (isEditable ? pageItemID : nil) else { return }
        pageLoss = PageLoss(item: item, comingBack: comingBack)
        pageLosses += 1
        tellPageLoss()
    }

    /// Whether a flush fails because the page is down after a loss: while it is coming back, so the person can check
    /// the item before they go, and, where it cannot come back, until they have answered being told. A flush it holds
    /// tells them again where they have answered already, so a refused close or quit always says why.
    func lossHoldsFlush() -> Bool {
        guard let pageLoss else { return false }
        let waiting = isLossNoticeWaiting(pageLoss)
        guard pageLoss.comingBack else { return waiting }
        if !waiting { tellPageLoss() }
        return true
    }

    /// Tells the person the page went down, unless that notice still waits for their answer.
    func tellPageLoss() {
        guard let pageLoss, let notices = library?.notices, !isLossNoticeWaiting(pageLoss) else { return }
        let notice = lossNotice(pageLoss)
        notices.notKept(notice.title, text: nil, reason: notice.message, standsAlone: true)
    }

    private func isLossNoticeWaiting(_ loss: PageLoss) -> Bool {
        let notice = lossNotice(loss)
        return library?.notices.waiting.contains { $0.title == notice.title && $0.message == notice.message } == true
    }

    private func lossNotice(_ loss: PageLoss) -> (title: String, message: String) {
        let title = library?.item(loss.item).map { String(localized: "Typing in “\($0.displayTitle)” Might Be Missing") }
            ?? String(localized: "Some Typing Might Be Missing")
        let message = loss.comingBack
            ? String(localized: "The editor stopped unexpectedly, so the last thing you typed in this item might not be saved. When the item shows again, check it and add anything that’s missing.")
            : String(localized: "The editor stopped unexpectedly and couldn’t start again, so the last thing you typed in this item might not be saved. Close this window, then open the item again to check it.")
        return (title, message)
    }

    /// The page reports each change as it is made, so what it never reported is not on the page to give back.
    private func tellNotSaved(_ pageItemID: ItemID, reason: String) {
        let title = library?.item(pageItemID).map { String(localized: "Couldn’t Save “\($0.displayTitle)”") }
        library?.notices.notKept(title ?? String(localized: "Couldn’t Save Item"), text: nil, reason: reason)
    }

    /// The page's refusals to hand over its edit that pass: a composition, a picture still being imported, and a load or
    /// reload the page puts off until either ends (`stale-document`, as the flush asks for the generation last sent).
    private static let passingFlushRefusals: Set<String> = ["composition", "operation-pending", "stale-document", "hidden-text"]

    /// Whether the script ran in the page and failed there, rather than never reaching it.
    private static func ranInPage(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == WKError.errorDomain
            && [WKError.javaScriptExceptionOccurred.rawValue, WKError.javaScriptResultTypeIsUnsupported.rawValue].contains(error.code)
    }

    private static var replacedReason: String {
        String(localized: "Another item opened before the app finished saving this one, so your most recent typing might not be saved. Try again.")
    }

    /// The page went down after it had been ready, holding an item the person could edit, so what they typed last may
    /// not have reached the app.
    struct PageLoss {
        let item: ItemID
        /// Whether the page is loading again. One that ended again before it was ready, or failed to load, is not.
        let comingBack: Bool
    }

    /// Destructive transitions proceed only once every editor has handed over its current text and its window's
    /// titles. Where the window or the library goes, a title that still cannot be saved stops them as a failed
    /// capture does, since it would otherwise be lost; where they stay, as when an item is deleted, it waits.
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
        quickLook = nil
        requestedItemID = nil
        cancelRequests()
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
