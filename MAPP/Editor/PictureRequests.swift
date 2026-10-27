import Foundation
import UniformTypeIdentifiers
import WebKit

/// What the page asks of the app about a picture at a web address, through the `pictures` message handler. The page
/// fetches nothing: this is the only way a web address becomes a picture on it.
nonisolated struct PictureRequest: Equatable, Sendable {
    let item: ItemID
    let address: URL
    let ask: PictureAsk
    /// The picture's bytes for a portable export, rather than a URL to show it from.
    let exporting: Bool

    init?(body: Any) {
        guard let dict = body as? [String: Any], dict["type"] as? String == "load",
              let item = dict["item"] as? String, !item.isEmpty,
              let text = dict["address"] as? String, let address = URL(string: text),
              ["http", "https"].contains(address.scheme?.lowercased()),
              let ask = (dict["ask"] as? String).flatMap(PictureAsk.init(rawValue:))
        else { return nil }
        self.item = ItemID(item)
        self.address = address
        self.ask = ask
        exporting = dict["export"] as? Bool == true
    }
}

/// Answers the page's requests for pictures at web addresses. A request the app cannot read is answered with
/// nothing, so the page never waits on a reply that will not come.
final class PictureRequests: NSObject, WKScriptMessageHandlerWithReply {
    let pictures: WebPictures
    /// Whether the item is in the feed tier (`Item.tier`), the only place Always loads pictures without asking: connectors
    /// write there and captures land there. `Item.source` cannot tell, since Marfa stamps every item with the source of
    /// the key that wrote it, a note the person wrote in MAPP included.
    var inFeed: (ItemID) -> Bool = { _ in false }
    /// Changed for each note the page shows, as `EmbeddedFiles.version` is, so an answer to a note since left is dropped.
    var version: () -> Int = { 0 }

    /// The largest picture handed to a portable export, as for any embedded image.
    nonisolated static let largestExport = 16 << 20

    init(pictures: WebPictures) {
        self.pictures = pictures
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let request = PictureRequest(body: message.body) else { return replyHandler(nil, nil) }
        Task { replyHandler(await reply(to: request), nil) }
    }

    /// `state` is `loaded` with the `url` to show it from, `waiting` where the person may choose to load it, `off`
    /// where Settings says never, or `refused` with the `reason`, and `retry` where choosing the card again may end differently.
    func reply(to request: PictureRequest) async -> [String: String]? {
        let version = version()
        let answer = await pictures.answer(
            request.address, ask: request.exporting ? .cached : request.ask, inFeed: inFeed(request.item)
        )
        guard version == self.version() else { return nil }
        switch answer {
        case .waiting: return ["state": "waiting"]
        case .off: return ["state": "off"]
        case .refused(let failure):
            var reply = ["state": "refused", "reason": failure.message]
            if failure.isTransient { reply["retry"] = "true" }
            return reply
        case .loaded:
            if request.exporting { return await export(request.address) }
            return ["state": "loaded", "url": EmbeddedFiles.pictureURL(for: request.address, version: version).absoluteString]
        }
    }

    private func export(_ address: URL) async -> [String: String]? {
        guard let file = await pictures.openKept(address), file.length <= UInt64(Self.largestExport),
              let data = await file.read(at: 0, count: Int(file.length)), data.count == Int(file.length),
              let type = UTType(filenameExtension: file.url.pathExtension)
        else { return nil }
        return ["state": "loaded", "data": data.base64EncodedString(), "mimeType": type.preferredMIMEType ?? "application/octet-stream"]
    }
}

extension WebPictures {
    /// The kept picture, opened for reading through the checked descriptor the embedded files use, so what is served
    /// is a file inside the cache whatever happened to its folder since.
    func openKept(_ address: URL) async -> OpenFile? {
        guard let kept = await cache.file(for: address), let folder = OpenFile.realPath(of: cache.folder) else { return nil }
        let inside = folder
            .appending(path: kept.deletingLastPathComponent().lastPathComponent, directoryHint: .isDirectory)
            .appending(path: kept.lastPathComponent, directoryHint: .notDirectory)
        return await OpenFile.open(inside, inside: folder)
    }
}
