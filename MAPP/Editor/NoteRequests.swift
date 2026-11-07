import Foundation
import WebKit

/// What the page asks of the app's notes through the `notes` message handler, which answers each request.
nonisolated enum NoteRequest: Equatable, Sendable {
    /// Titles that answer what was typed after `[[`.
    case suggest(String, in: ItemID?)
    /// The Link to Note command, from the note it was typed in.
    case pick(ItemID)
    /// What each of a note's links names: no note, or a note of some type. A link the core does not read as the one link
    /// the page posted is nil, and keeps its place so the answer lines up with the page's links.
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
    /// What each link of the note names.
    var readings: ([NoteLink], ItemID) async -> [LinkReading] = { links, _ in links.map { _ in .plain } }
    /// The image of a type's icon as a data URL, nil where it cannot be drawn.
    var drawIcon: (String?) -> String? = { LinkIcons.dataURL(for: $0) }

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
            case .resolve(let links, let source): replyHandler(await answerLinks(links, in: source).propertyList, nil)
            }
        }
    }

    /// One answer for each link the page posted. A link the core does not read as one link is not asked about and
    /// is answered as live with no type, so the page draws it as a live link rather than a red one it cannot vouch for;
    /// the note's other links keep their marks. Each type icon is drawn and sent once, however many links name it.
    func answerLinks(_ links: [NoteLink?], in source: ItemID) async -> LinkReply {
        let readable = links.compactMap { $0 }
        let answers = readable.isEmpty ? [] : await readings(readable, source)
        guard answers.count == readable.count else { return LinkReply(links.map { _ in .plain }, draw: drawIcon) }
        var next = answers.makeIterator()
        return LinkReply(links.map { $0 == nil ? .plain : next.next() ?? .plain }, draw: drawIcon)
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
