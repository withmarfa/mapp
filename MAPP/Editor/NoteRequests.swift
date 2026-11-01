import Foundation
import WebKit

/// What the page asks of the app's notes through the `notes` message handler, which answers each request.
nonisolated enum NoteRequest: Equatable, Sendable {
    /// Titles that answer what was typed after `[[`.
    case suggest(String, in: ItemID?)
    /// The Link to Note command, from the note it was typed in.
    case pick(ItemID)
    /// Which of a note's links name no note. A link the core does not read as the one link the page posted is nil, and
    /// keeps its place so the answer lines up with the page's links.
    case resolve([NoteLink?], in: ItemID)

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "suggest":
            guard let query = dict["query"] as? String else { return nil }
            self = .suggest(query, in: (dict["item"] as? String).flatMap { $0.isEmpty ? nil : ItemID($0) })
        case "pick":
            guard let item = dict["item"] as? String, !item.isEmpty else { return nil }
            self = .pick(ItemID(item))
        case "resolve":
            guard let item = dict["item"] as? String, !item.isEmpty, let links = dict["links"] as? [[String: Any]] else { return nil }
            self = .resolve(links.map(NoteLink.init(page:)), in: ItemID(item))
        default:
            return nil
        }
    }
}

/// Answers the page's requests about notes. A request the app cannot read is answered with nothing, so the page
/// never waits on a reply that will not come.
final class NoteRequests: NSObject, WKScriptMessageHandlerWithReply {
    /// The titles to offer for what was typed, best first.
    var suggest: (String, ItemID?) async -> [String] = { _, _ in [] }
    /// The link the person chose from the note, which may take as long as they do; nil if they chose none.
    var pick: (ItemID) async -> String? = { _ in nil }
    /// Whether each link of the note names no note.
    var missing: ([NoteLink], ItemID) async -> [Bool] = { links, _ in links.map { _ in false } }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let request = NoteRequest(body: message.body) else { return replyHandler(nil, nil) }
        Task {
            switch request {
            case .suggest(let query, let source): replyHandler(await suggest(query, source), nil)
            case .pick(let item): replyHandler(await pick(item), nil)
            case .resolve(let links, let source): replyHandler(await answerMissing(links, in: source), nil)
            }
        }
    }

    /// One answer for each link the page posted. A link the core does not read as one link is not asked about and
    /// is answered as not missing, so the page draws it as a live link rather than a red one it cannot vouch for;
    /// the note's other links keep their marks.
    func answerMissing(_ links: [NoteLink?], in source: ItemID) async -> [Bool] {
        let readable = links.compactMap { $0 }
        let answers = readable.isEmpty ? [] : await missing(readable, source)
        guard answers.count == readable.count else { return links.map { _ in false } }
        var next = answers.makeIterator()
        return links.map { $0 == nil ? false : next.next() ?? false }
    }
}

extension NoteLink {
    /// The link as the page posts it: its `raw` text with the brackets. The core reads that text again, so what the
    /// page decoded of it (Inkkit takes a backslash as an escape, Marfa does not) is not used.
    nonisolated init?(page dict: [String: Any]) {
        guard let raw = dict["raw"] as? String else { return nil }
        self.init(linkText: raw)
    }
}
