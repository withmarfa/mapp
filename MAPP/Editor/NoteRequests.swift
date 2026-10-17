import Foundation
import WebKit

/// What the page asks of the app's notes through the `notes` message handler, which answers each request.
nonisolated enum NoteRequest: Equatable, Sendable {
    /// Titles that answer what was typed after `[[`.
    case suggest(String, in: ItemID?)
    /// The Link to Note command, from the note it was typed in.
    case pick(ItemID)
    /// Which of a note's links name no note.
    case resolve([NoteLink], in: ItemID)

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
            let parsed = links.compactMap(NoteLink.init(page:))
            guard parsed.count == links.count else { return nil }
            self = .resolve(parsed, in: ItemID(item))
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
    var missing: ([NoteLink], ItemID) -> [Bool] = { links, _ in links.map { _ in false } }

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
            case .resolve(let links, let source): replyHandler(missing(links, source), nil)
            }
        }
    }
}

extension NoteLink {
    /// A link as the page posts it: `target`, and `heading` and `alias` when it has them.
    nonisolated init?(page dict: [String: Any]) {
        guard let target = dict["target"] as? String else { return nil }
        self.init(name: target, heading: dict["heading"] as? String, alias: dict["alias"] as? String)
    }
}
