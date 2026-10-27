import AppKit
import WebKit

/// Handing over the page's last edit before a note, a window or the library goes.
extension EditorController {
    /// Hands over an edit the page has not yet reported, as when the window closes or another note is shown.
    /// The page answers in order, so this lands before anything asked of it later. The reply keeps this controller alive until it arrives.
    ///
    /// A page that cannot hand over its edit within `flushLimit` is given up on: the person is told, and the next
    /// flush goes ahead without it, so a stuck page never holds the window or the app for good. What the page
    /// last reported is already saved; only what it never reported is lost.
    ///
    /// Outside text reloading the note mid-flush leaves the note the one being flushed, so the flush goes ahead. A
    /// flush whose note was replaced on the page stops, and the person is told why.
    func flush(then done: @escaping (Bool) -> Void = { _ in }) {
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
            webView.evaluateJavaScript("window.editor.flush(\(generation))") { [self] result, error in
                // A reply that comes after the page was given up on still holds the person's latest text.
                if error == nil, let markdown = result as? String { report(markdown, of: generation) }
                guard !finished else { return }
                guard error == nil else {
                    Task { try? await Task.sleep(for: .milliseconds(50)); capture() }
                    return
                }
                guard self.noteID == noteID else { return replaced() }
                finish(true)
            }
        }
        func replaced() {
            tellNotSaved(noteID, reason: Self.replacedReason)
            finish(false)
        }
        // Held weakly, so a finished flush does not keep a closed editor among the open ones until the limit.
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.flushLimit)
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

    static let flushLimit = Duration.seconds(2)

    private static var replacedReason: String {
        String(localized: "Another note opened before MAPP finished saving this one, so your most recent typing might not be saved. Try again.")
    }

    /// Destructive transitions proceed only once every editor has handed over its current text and its window's
    /// titles. Where the window or the library goes, a title that still cannot be saved stops them as a failed
    /// capture does, since it would otherwise be lost; where they stay, as when a note is deleted, it waits.
    static func flushAll(leaving: Bool = true, then done: @escaping (Bool) -> Void) {
        let editors = open.allObjects
        let gate = Gate(waitingFor: editors.count, then: done)
        // One refusal is told, from the window that holds it, since that window comes forward and only one can.
        var told = false
        for editor in editors {
            guard editor.saveTitles(tellingRefusal: leaving && !told) || !leaving else {
                told = true
                gate.arrive(false)
                continue
            }
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
