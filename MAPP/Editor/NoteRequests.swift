import Foundation
import WebKit

/// What the page asks of the app's notes through the `notes` message handler, which answers each request.
nonisolated enum NoteRequest: Equatable, Sendable {
    /// Titles that answer what was typed after `[[`.
    case suggest(String)
    /// The Link to Note command, from the note it was typed in.
    case pick(ItemID)

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "suggest":
            guard let query = dict["query"] as? String else { return nil }
            self = .suggest(query)
        case "pick":
            guard let item = dict["item"] as? String, !item.isEmpty else { return nil }
            self = .pick(ItemID(item))
        default:
            return nil
        }
    }
}

/// Answers the page's requests about notes. A request the app cannot read is answered with nothing, so the page
/// never waits on a reply that will not come.
final class NoteRequests: NSObject, WKScriptMessageHandlerWithReply {
    /// The titles to offer for what was typed, best first.
    var suggest: (String) async -> [String] = { _ in [] }
    /// The link the person chose from the note, which may take as long as they do; nil if they chose none.
    var pick: (ItemID) async -> String? = { _ in nil }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let request = NoteRequest(body: message.body) else { return replyHandler(nil, nil) }
        Task {
            switch request {
            case .suggest(let query): replyHandler(await suggest(query), nil)
            case .pick(let item): replyHandler(await pick(item), nil)
            }
        }
    }
}
