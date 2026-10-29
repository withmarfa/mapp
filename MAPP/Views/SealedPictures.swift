import Foundation
import UniformTypeIdentifiers
import WebKit

/// The pictures of the HTML document shown for one item in the sealed web page, answered by the app as the note page's
/// are (`PictureRequests`), so the page itself fetches nothing. They use the editor's scheme and URLs for a picture
/// saved in an item (`EmbeddedFiles`), which in a sealed page only `SealedPictureScheme` answers.
///
/// `SealedPictureRewrite` points each picture at this scheme, and only the addresses it found are answered, for this
/// item alone. A picture saved as a file attached to the item from the same address comes first, under every setting,
/// with no request to the website (`ItemLibrary.openSavedPicture`); then the Remote Pictures setting answers
/// (`WebPictures.answer`), as for a note. Whatever is not loaded is drawn as an empty picture that keeps its place.
@MainActor @Observable final class SealedPictures {
    nonisolated static let scheme = EmbeddedFiles.scheme

    let item: ItemID
    @ObservationIgnored private let pictures: WebPictures
    /// Whether the item is in the feed tier, the only place Always loads without asking.
    @ObservationIgnored private let inFeed: () -> Bool
    /// The picture saved for an address on the item.
    @ObservationIgnored private let saved: (URL) async -> SavedPictureResolution
    /// Every address a document shown for the item named, so a page that is still drawing an earlier version is answered.
    @ObservationIgnored private var allowed: Set<URL> = []
    /// The addresses of the document shown last.
    private var shown: [URL] = []
    private var waiting: Set<URL> = []
    /// Whether the person chose to load the pictures waiting.
    private(set) var chosen = false
    /// Changed each time the page is to ask for its pictures again. Only an answer to a request of this version
    /// counts a picture as waiting, so an answer under a setting since changed is not counted.
    private(set) var version = 0
    /// The version the document shown last was written with, which `version` may have passed while it loaded.
    @ObservationIgnored private(set) var documentVersion = 0

    init(
        item: ItemID, pictures: WebPictures, inFeed: @escaping () -> Bool,
        saved: @escaping (URL) async -> SavedPictureResolution
    ) {
        self.item = item
        self.pictures = pictures
        self.inFeed = inFeed
        self.saved = saved
    }

    /// How many of the document's pictures wait for the person to load them.
    var waitingCount: Int { chosen ? 0 : shown.count { waiting.contains($0) } }

    /// The addresses of a document about to be shown, whose pictures were written with `version`
    /// (`SealedPictureRewrite`).
    func show(_ addresses: [URL], version: Int) {
        allowed.formUnion(addresses)
        shown = addresses
        documentVersion = version
    }

    /// The person chose to load the pictures waiting.
    func loadWaiting() {
        chosen = true
        redraw()
    }

    /// Has the page ask for every picture again, as when the setting or a saved picture changes.
    func redraw() { version += 1 }

    // MARK: Answering

    enum Reply {
        case file(OpenFile)
        /// Nothing to draw, in the picture's place.
        case placeholder
        /// Not a picture of this page.
        case refused
    }

    func answer(_ url: URL?) async -> Reply {
        guard let url, let request = Self.request(in: url), request.item == item, allowed.contains(request.address)
        else { return .refused }
        let address = request.address
        switch await saved(address) {
        case .file(let file): return .file(file)
        case .unavailable: return .placeholder
        case .none: break
        }
        let answer = await pictures.answer(address, ask: chosen ? .chosen : .drawing, inFeed: inFeed())
        if request.version == version {
            if answer == .waiting { waiting.insert(address) } else { waiting.remove(address) }
        }
        guard case .loaded = answer, let file = await pictures.openKept(address) else { return .placeholder }
        return .file(file)
    }

    // MARK: URLs

    /// Where the page draws the picture at `address` in `item`'s document from: the editor's URL for a picture saved
    /// in an item (`EmbeddedFiles.pictureURL(for:version:savedIn:)`), answered here by this type instead.
    nonisolated static func url(for address: URL, in item: ItemID, version: Int) -> URL {
        EmbeddedFiles.pictureURL(for: address, version: version, savedIn: item)
    }

    nonisolated static func request(in url: URL) -> (item: ItemID, address: URL, version: Int)? {
        guard let (item, address) = EmbeddedFiles.savedPicture(in: url),
              let version = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                  .first(where: { $0.name == "v" })?.value.flatMap(Int.init)
        else { return nil }
        return (item, address, version)
    }

    /// An empty picture with the shape of a photograph, which takes the size the document gives the `img`, or the width
    /// it has where it gives none.
    nonisolated static let placeholder = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4 3"/>"#.utf8)
}

/// Serves a sealed page's pictures from its `SealedPictures`.
nonisolated struct SealedPictureScheme: URLSchemeHandler {
    let pictures: SealedPictures

    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let url = request.url ?? URL(string: "\(SealedPictures.scheme):")!
                func respond(_ status: Int, _ type: String, length: UInt64) {
                    continuation.yield(.response(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [
                        "Content-Type": type, "Content-Length": String(length), "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
                    ])!))
                }
                switch await pictures.answer(request.url) {
                case .refused:
                    respond(404, "text/plain", length: 0)
                case .placeholder:
                    respond(200, "image/svg+xml", length: UInt64(SealedPictures.placeholder.count))
                    continuation.yield(.data(SealedPictures.placeholder))
                case .file(let file):
                    guard let type = UTType(filenameExtension: file.url.pathExtension), type.conforms(to: .image) else {
                        respond(200, "image/svg+xml", length: UInt64(SealedPictures.placeholder.count))
                        continuation.yield(.data(SealedPictures.placeholder))
                        break
                    }
                    respond(200, type.preferredMIMEType ?? "application/octet-stream", length: file.length)
                    var offset: UInt64 = 0
                    while offset < file.length, !Task.isCancelled {
                        let count = Int(min(UInt64(EmbeddedFiles.piece), file.length - offset))
                        guard let data = await file.read(at: offset, count: count), !data.isEmpty else {
                            return continuation.finish(throwing: CocoaError(.fileReadUnknown))
                        }
                        continuation.yield(.data(data))
                        offset += UInt64(data.count)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
