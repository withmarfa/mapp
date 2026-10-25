import Foundation
import Observation

/// What MAPP has to tell the person: something a library could not do, a change it could not keep, or a server
/// that would read the key unencrypted. The one way any of them reaches the person: each waits here, in the order
/// it was told, until one window shows it and the person answers. The host makes one and gives it to every library
/// it opens, so a notice from a library the windows have since left is still told.
@Observable @MainActor final class Notices {
    nonisolated struct Notice: Identifiable, Hashable, Sendable {
        /// Kept as more changes not kept gather into the notice, so the person's answer always finds it.
        let id: UUID
        var title: String
        var message: String
        /// What the person typed that nothing keeps, which goes to the clipboard as they are told.
        var text: String?
        /// Whether this tells of changes not kept, which gather into one notice until it is shown.
        var isNotKept = false
    }

    /// Oldest first. The first is the one shown.
    private(set) var waiting: [Notice] = []

    /// How many times anything was told, counting a notice that was already waiting or gathered into another, so a
    /// caller can see whether a step it took told the person.
    private(set) var told = 0

    /// The window showing the first notice, until the person answers it or the window closes.
    private(set) var shownIn: UUID?

    /// The notices any window has shown, whose text has gone to the clipboard. Nothing more gathers into them, since
    /// the person may have read them, and their text is never written again, since the person may have copied
    /// something since.
    private var shown: Set<Notice.ID> = []

    /// Tells the person something that was not done. A notice already waiting with the same words is not told twice.
    func tell(_ title: String, _ message: String) {
        told += 1
        guard !waiting.contains(where: { !$0.isNotKept && $0.title == title && $0.message == message }) else { return }
        waiting.append(Notice(id: UUID(), title: title, message: message))
    }

    /// Tells the person that a change was not kept, with `reason` where it was not that the library closed, and
    /// gives back `text`, the only copy of what they typed. Changes not kept before their notice is shown gather into
    /// it, so each text reaches the clipboard with the others; one not kept after that waits behind it in a notice of
    /// its own, so the text already on the clipboard stays there until the person answers.
    func notKept(_ title: String, text: String?, reason: String? = nil) {
        told += 1
        let text = text?.isEmpty == false ? text : nil
        guard let index = waiting.firstIndex(where: { $0.isNotKept && !shown.contains($0.id) }) else {
            waiting.append(Notice(id: UUID(), title: title, message: Self.notKeptMessage(reason: reason, text: text), text: text, isNotKept: true))
            return
        }
        let earlier = waiting[index]
        let texts = [earlier.text, text].compactMap { $0 }
        let gathered = texts.isEmpty ? nil : texts.joined(separator: "\n\n")
        let message = Self.notKeptMessage(reason: reason, text: gathered)
        waiting[index] = Notice(
            id: earlier.id,
            title: String(localized: "Some Changes Weren’t Saved"),
            message: earlier.message == message ? message : Self.someNotKeptMessage(text: gathered),
            text: gathered, isNotKept: true)
    }

    /// The notice for `window` to show: the first waiting, unless another window shows it. The first time any
    /// window shows a notice, its text goes to the clipboard through `copy`.
    func show(in window: UUID, copying copy: (String) -> Void) -> Notice? {
        guard let notice = waiting.first, shownIn == nil || shownIn == window else { return nil }
        shownIn = window
        if shown.insert(notice.id).inserted, let text = notice.text { copy(text) }
        return notice
    }

    /// The window closed, or stopped showing its notice without an answer, so another window can show it.
    func released(by window: UUID) {
        if shownIn == window { shownIn = nil }
    }

    /// The person answered the notice.
    func answered(_ id: Notice.ID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index)
        shown.remove(id)
        if index == 0 { shownIn = nil }
    }

    /// Whether a change not kept waits that no window has shown, so the person has not been told and its text is
    /// not on the clipboard.
    var holdsQuit: Bool {
        waiting.contains { $0.isNotKept && !shown.contains($0.id) }
    }

    /// Before the app quits, tells the person, through `present`, each notice in order up to the last change not
    /// kept that no window has shown, and answers it once `present` returns; whether the app can quit. While a
    /// window shows a notice the rest wait behind it, so the quit waits for the person to answer there.
    func tellBeforeQuitting(copying copy: (String) -> Void, present: (Notice) -> Void) -> Bool {
        guard holdsQuit else { return true }
        guard shownIn == nil else { return false }
        let quitting = UUID()
        while holdsQuit, let notice = show(in: quitting, copying: copy) {
            present(notice)
            answered(notice.id)
        }
        return !holdsQuit
    }

    /// The reason the change was not kept and where the person's text is.
    private static func notKeptMessage(reason: String?, text: String?) -> String {
        if let reason {
            return text == nil ? reason : String(localized: "\(reason) Your text is on the clipboard, so you can paste it back.")
        }
        return text == nil
            ? String(localized: "MAPP closed the library before it could keep your change. Make the change again.")
            : String(localized: "MAPP closed the library before it could keep what you typed. Your text is on the clipboard, so you can paste it back.")
    }

    /// Changes not kept for different reasons share the plainest account of them.
    private static func someNotKeptMessage(text: String?) -> String {
        text == nil
            ? String(localized: "MAPP couldn’t keep some of your changes. Make them again.")
            : String(localized: "MAPP couldn’t keep some of what you typed. Your text is on the clipboard, so you can paste it back.")
    }
}
