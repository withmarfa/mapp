import Foundation
import Observation

/// What MAPP has to tell the person: something a library could not do, a change it could not keep, or a server
/// that would read the key unencrypted. The one way any of them reaches the person: each waits here, in the order
/// it was told, until the window in front shows it and the person answers. The host makes one and gives it to every
/// library it opens, so a notice from a library the windows have since left is still told.
@Observable @MainActor final class Notices {
    nonisolated struct Notice: Hashable, Sendable {
        var title: String
        var message: String
        /// What the person typed that nothing keeps, which goes to the clipboard as they are told.
        var text: String?
        /// Whether this tells of changes not kept, which gather into one notice until the person answers.
        var isNotKept = false
    }

    /// Oldest first. The first is the one shown.
    private(set) var waiting: [Notice] = []

    /// The notice told last, for a test to read.
    var newest: Notice? { waiting.last }

    /// Tells the person something that was not done. A notice already waiting with the same words is not told twice.
    func tell(_ title: String, _ message: String) {
        let notice = Notice(title: title, message: message)
        guard !waiting.contains(notice) else { return }
        waiting.append(notice)
    }

    /// Tells the person that a change was not kept, with `reason` where it was not that the library closed, and
    /// gives back `text`, the only copy of what they typed. Changes not kept before the person answers gather into
    /// one notice, so each text stays on the clipboard with the others.
    func notKept(_ title: String, text: String?, reason: String? = nil) {
        let text = text?.isEmpty == false ? text : nil
        guard let index = waiting.firstIndex(where: \.isNotKept) else {
            waiting.append(Notice(title: title, message: Self.notKeptMessage(reason: reason, text: text), text: text, isNotKept: true))
            return
        }
        let earlier = waiting[index]
        let texts = [earlier.text, text].compactMap { $0 }
        let gathered = texts.isEmpty ? nil : texts.joined(separator: "\n\n")
        let message = Self.notKeptMessage(reason: reason, text: gathered)
        waiting[index] = Notice(
            title: String(localized: "Some Changes Weren’t Saved"),
            message: earlier.message == message ? message : Self.someNotKeptMessage(text: gathered),
            text: gathered, isNotKept: true)
    }

    /// The person answered the notice shown.
    func answered(_ notice: Notice) {
        guard let index = waiting.firstIndex(of: notice) else { return }
        waiting.remove(at: index)
    }

    func removeAll() {
        waiting = []
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
