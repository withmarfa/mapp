import AppKit
import Darwin
import UniformTypeIdentifiers
import WebKit

/// An embed as the note's text holds it, such as `![[photo.png|400]]` or `![](a\_b.png)`: the page names an embed
/// this way and Marfa's core lists each one it bound this way (`BoundEmbed.text`), so the two are matched whole,
/// kind included, and MAPP reads no name out of an embed itself.
nonisolated struct EmbedReference: Hashable, Sendable {
    let text: String

    /// The item and embed the page names, as `{ item, text }`.
    static func request(_ body: Any?) -> (item: ItemID, reference: EmbedReference)? {
        guard let dict = body as? [String: Any], let item = dict["item"] as? String, !item.isEmpty,
              let text = dict["text"] as? String, !text.isEmpty
        else { return nil }
        return (ItemID(item), EmbedReference(text: text))
    }
}

// MARK: Resolving

/// What an embed shows: its file, opened for reading, nothing, or why its file can't be shown now.
nonisolated enum EmbedResolution: Sendable {
    case file(OpenFile)
    case missing
    case unavailable(String)

    var file: OpenFile? {
        if case .file(let file) = self { file } else { nil }
    }
}

extension ItemLibrary {
    /// The file an item's embed shows, the one place an embed becomes a file, which the page's scheme, its Open
    /// and the gallery all ask. Marfa's core binds each embed to its file item when the text is saved
    /// (`Item.boundEmbeds`), and lists no embed it does not take for a file, such as one of a note. An embed is
    /// waited on, for up to `waiting`, only while the text holding it has not been read by the copy, as one just
    /// pasted has not; once it has, an embed the core did not bind is no file. The file is fetched if this Mac
    /// doesn't hold it, unless `wanted` turns its item down, which answers `missing`.
    func openEmbeddedFile(
        _ reference: EmbedReference, in item: ItemID, waiting: Duration = .zero, if wanted: (Item) -> Bool = { _ in true }
    ) async -> EmbedResolution {
        let deadline = ContinuousClock.now + waiting
        var bound = binding(of: reference, in: item)
        while bound == nil, isUnread(reference, in: item), ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            bound = binding(of: reference, in: item)
        }
        switch bound {
        case .resolved(let file):
            if let held = self.item(file), !wanted(held) { return .missing }
            return await open(file)
        case .ambiguous:
            return .unavailable(String(localized: "More than one file has this name."))
        case .refused(let reason):
            return .unavailable(reason)
        case .pending:
            return .unavailable(String(localized: "This file isn’t in Marfa yet."))
        case .missing, nil:
            return .missing
        }
    }

    private func binding(of reference: EmbedReference, in item: ItemID) -> NoteReferenceResolution? {
        self.item(item)?.boundEmbeds.first { $0.text == reference.text }?.resolution
    }

    /// Whether the copy may not yet have read the text holding the embed: a save of the item is on its way, or the
    /// page shows the embed before its text reached the library.
    private func isUnread(_ reference: EmbedReference, in item: ItemID) -> Bool {
        hasUnreadSave(item) || body(of: item)?.text.contains(reference.text) != true
    }

    private func open(_ file: ItemID) async -> EmbedResolution {
        let url: URL
        do {
            guard let fetched = try await fileURL(of: file) else { return .missing }
            url = fetched
        } catch {
            return .unavailable(error.localizedDescription)
        }
        // Opened by its real path, since the descriptor is opened through no link and a temporary folder is under one.
        guard let folder = OpenFile.realPath(of: url.deletingLastPathComponent()),
              let opened = await OpenFile.open(folder.appending(path: url.lastPathComponent), inside: folder)
        else { return .unavailable(String(localized: "This file can’t be opened.")) }
        return .file(opened)
    }
}

// MARK: Serving

/// Serves the page the files its note embeds, through the app's own URL scheme, and tells it what each is. The
/// page loads nothing else: a file is streamed from disk in pieces, answering ranges as sound and video ask for
/// them, and never read whole into memory.
final class EmbeddedFiles: NSObject, WKURLSchemeHandler, WKScriptMessageHandlerWithReply {
    nonisolated static let scheme = "mapp-embed"
    /// How much of a file is read and handed over at a time.
    nonisolated static let piece = 1 << 20

    /// The file an item's embed names, opened; `ItemLibrary.openEmbeddedFile` for the editor's library.
    var open: (EmbedReference, ItemID) async -> EmbedResolution = { _, _ in .missing }
    /// Changed for each note the page shows, so a file changed on disk is loaded again rather than taken from
    /// WebKit's memory of the page.
    var version = 0

    private var running: Set<ObjectIdentifier> = []
    private var icons: [String: Data] = [:]

    // MARK: What a file is

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let (item, reference) = EmbedReference.request(message.body) else { return replyHandler(nil, nil) }
        let version = version
        let exporting = (message.body as? [String: Any])?["export"] as? Bool == true
        Task {
            let resolution = await open(reference, item)
            guard self.version == version else { return replyHandler(nil, nil) }
            if case .unavailable(let reason) = resolution, !exporting { return replyHandler(["unavailable": reason], nil) }
            guard let file = resolution.file else { return replyHandler(nil, nil) }
            let type = UTType(filenameExtension: file.url.pathExtension)
            if exporting {
                // Portable exports read the checked descriptor, never the path resolved before it opened.
                guard type?.conforms(to: .image) == true, file.length <= 16 << 20,
                      let data = await file.read(at: 0, count: Int(file.length)), data.count == Int(file.length),
                      self.version == version else { return replyHandler(nil, nil) }
                return replyHandler(["data": data.base64EncodedString(), "mimeType": type?.preferredMIMEType ?? "application/octet-stream"], nil)
            }
            replyHandler([
                "url": Self.url(for: reference, in: item, version: version).absoluteString,
                "kind": Self.kind(of: type),
                "name": file.url.lastPathComponent,
                "detail": Int64(file.length).formatted(.byteCount(style: .file)),
                "icon": Self.iconURL(for: type).absoluteString,
                "opens": Self.opens(file.url),
            ], nil)
        }
    }

    /// What the page shows a file as. WebKit draws the images, sound and video it can, and a PDF in a frame.
    nonisolated static func kind(of type: UTType?) -> String {
        guard let type else { return "file" }
        if type.conforms(to: .pdf) { return "pdf" }
        if type.conforms(to: .image) { return "image" }
        if type.conforms(to: .audio) { return "audio" }
        if type.conforms(to: .movie) { return "video" }
        return "file"
    }

    // MARK: Opening

    /// Whether Open may hand the file to the app the system opens it with: only a document or media file, never
    /// one that runs or points elsewhere when opened, such as a script, a program, a Terminal setting or an
    /// internet location, nor any file marked executable, nor one of a kind this cannot tell. A note shared
    /// with a file beside it must not be able to run that file. Anything else is shown in the Finder instead.
    nonisolated static func opens(_ url: URL) -> Bool {
        var status = stat()
        guard lstat(url.path, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_mode & 0o111 == 0,
              let type = UTType(filenameExtension: url.pathExtension)
        else { return false }
        // An SVG, a web page and a web archive open in a browser, which runs the scripts they carry.
        let refused: [UTType] = [
            .executable, .unixExecutable, .script, .sourceCode, .application, .bundle, .package, .archive,
            .html, .svg, .webArchive, .internetLocation,
        ]
        let documents: [UTType] = [
            .image, .audiovisualContent, .pdf, .plainText, .rtf, .delimitedText, .spreadsheet, .presentation,
            .compositeContent,
        ]
        return !refused.contains { type.conforms(to: $0) } && documents.contains { type.conforms(to: $0) }
    }

    // MARK: URLs

    /// `&`, `=` and `+` are allowed in a query but would split or change a value.
    private nonisolated static let valueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?"))

    nonisolated static func url(for reference: EmbedReference, in item: ItemID, version: Int) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "file"
        components.path = "/"
        components.percentEncodedQueryItems = [("item", item.rawValue), ("text", reference.text), ("v", String(version))].map {
            URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: valueAllowed))
        }
        return components.url!
    }

    nonisolated static func iconURL(for type: UTType?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "icon"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "type", value: (type ?? .data).identifier)]
        return components.url!
    }

    /// The item and embed a URL of `url(for:in:version:)` names.
    nonisolated static func request(in url: URL) -> (item: ItemID, reference: EmbedReference)? {
        guard url.scheme == scheme, url.host == "file",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems
        else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.removingPercentEncoding
        }
        guard let item = value("item"), !item.isEmpty, let text = value("text"), !text.isEmpty else { return nil }
        return (ItemID(item), EmbedReference(text: text))
    }

    // MARK: Ranges

    nonisolated enum Span: Equatable, Sendable {
        case whole
        case part(UInt64, UInt64)
        case unsatisfiable
    }

    /// The bytes a `Range` header asks for, in a file of `length` bytes. Only one range is answered, as WebKit
    /// asks for one; a header this cannot read is answered with the whole file, as HTTP allows.
    nonisolated static func span(_ header: String?, length: UInt64) -> Span {
        guard let header, header.hasPrefix("bytes="), !header.contains(",") else { return .whole }
        let bounds = header.dropFirst("bytes=".count).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return .whole }
        let first = bounds[0].trimmingCharacters(in: .whitespaces)
        let last = bounds[1].trimmingCharacters(in: .whitespaces)
        if first.isEmpty {
            guard let suffix = UInt64(last) else { return .whole }
            guard suffix > 0, length > 0 else { return .unsatisfiable }
            return .part(length - min(suffix, length), length - 1)
        }
        guard let start = UInt64(first) else { return .whole }
        guard start < length else { return .unsatisfiable }
        guard !last.isEmpty else { return .part(start, length - 1) }
        guard let end = UInt64(last), end >= start else { return .whole }
        return .part(start, min(end, length - 1))
    }

    // MARK: The scheme

    /// How much an open-ended range is answered with at most. WebKit gives a scheme no way to say it has taken
    /// what it was sent, so a sound or video asking for the rest of a large file is sent this much and asks
    /// again, rather than having the whole file pushed at it as fast as the disk reads.
    nonisolated static let window: UInt64 = 8 << 20

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        running.insert(id)
        Task {
            await serve(task, id)
            running.remove(id)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        running.remove(ObjectIdentifier(task))
    }

    /// Every answer goes through these, so a task WebKit has stopped, or one already finished, hears nothing:
    /// WebKit raises an exception for either.
    private func respond(
        _ task: any WKURLSchemeTask, _ id: ObjectIdentifier, status: Int, headers: [String: String] = [:]
    ) -> Bool {
        guard running.contains(id), let url = task.request.url else { return false }
        task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        return true
    }

    private func send(_ task: any WKURLSchemeTask, _ id: ObjectIdentifier, _ data: Data) -> Bool {
        guard running.contains(id) else { return false }
        task.didReceive(data)
        return true
    }

    private func finish(_ task: any WKURLSchemeTask, _ id: ObjectIdentifier, failing error: (any Error)? = nil) {
        guard running.remove(id) != nil else { return }
        if let error { task.didFailWithError(error) } else { task.didFinish() }
    }

    private func serve(_ task: any WKURLSchemeTask, _ id: ObjectIdentifier) async {
        guard let url = task.request.url else { return finish(task, id, failing: URLError(.badURL)) }
        if url.host == "icon" { return serveIcon(task, id, url) }
        guard let (item, reference) = Self.request(in: url), let file = await open(reference, item).file else {
            if respond(task, id, status: 404) { finish(task, id) }
            return
        }
        let type = UTType(filenameExtension: file.url.pathExtension)
        var headers = [
            "Content-Type": type?.preferredMIMEType ?? "application/octet-stream",
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        ]
        let range = task.request.value(forHTTPHeaderField: "Range")
        let start: UInt64
        let end: UInt64
        switch Self.span(range, length: file.length) {
        case .unsatisfiable:
            headers["Content-Range"] = "bytes */\(file.length)"
            if respond(task, id, status: 416, headers: headers) { finish(task, id) }
            return
        case .whole:
            (start, end) = (0, file.length)
            headers["Content-Length"] = String(file.length)
            guard respond(task, id, status: 200, headers: headers) else { return }
        case .part(let first, var last):
            if range?.hasSuffix("-") == true { last = min(last, first + Self.window - 1) }
            (start, end) = (first, last + 1)
            headers["Content-Length"] = String(end - start)
            headers["Content-Range"] = "bytes \(first)-\(last)/\(file.length)"
            guard respond(task, id, status: 206, headers: headers) else { return }
        }
        var offset = start
        while offset < end {
            let count = Int(min(UInt64(Self.piece), end - offset))
            guard let data = await file.read(at: offset, count: count), !data.isEmpty else {
                return finish(task, id, failing: CocoaError(.fileReadUnknown))
            }
            // A request WebKit has stopped, as when a video seeks, must hear nothing more.
            guard send(task, id, data) else { return }
            offset += UInt64(data.count)
        }
        finish(task, id)
    }

    /// The system's icon for a kind of file, for the card that stands for it.
    private func serveIcon(_ task: any WKURLSchemeTask, _ id: ObjectIdentifier, _ url: URL) {
        let identifier = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "type" }?.value ?? UTType.data.identifier
        let png = icons[identifier] ?? {
            let image = NSWorkspace.shared.icon(for: UTType(identifier) ?? .data)
            var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
            let data = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
                .flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
            icons[identifier] = data
            return data
        }()
        guard let png else {
            if respond(task, id, status: 404) { finish(task, id) }
            return
        }
        let headers = ["Content-Type": "image/png", "Content-Length": String(png.count)]
        guard respond(task, id, status: 200, headers: headers), send(task, id, png) else { return }
        finish(task, id)
    }
}

/// A file opened for reading by offset, so pieces can be read away from the main thread while WebKit asks for
/// more. Opened through no symbolic link anywhere in its path and without waiting, so a pipe put in its place
/// cannot hold a thread; then kept only if the file opened is an ordinary one whose real path is inside the
/// directory it was looked for in, under no name starting with a dot. That check is of the descriptor, so a
/// directory or file changed after the path was found can never put anything else behind it.
nonisolated final class OpenFile: Sendable {
    let descriptor: Int32
    let length: UInt64
    /// Where the opened file is, as the system knows the descriptor.
    let url: URL

    private init(descriptor: Int32, length: UInt64, url: URL) {
        self.descriptor = descriptor
        self.length = length
        self.url = url
    }

    deinit { close(descriptor) }

    @concurrent static func open(_ file: URL, inside root: URL) async -> OpenFile? {
        let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              let opened = path(of: descriptor), let folder = folderPath(of: root), contains(folder, opened)
        else {
            close(descriptor)
            return nil
        }
        return OpenFile(descriptor: descriptor, length: UInt64(status.st_size), url: opened)
    }

    /// A directory's real path. `resolvingSymlinksInPath` keeps `/var` rather than `/private/var`, a path that
    /// still runs through a link.
    static func realPath(of root: URL) -> URL? {
        guard let real = realpath(root.path, nil) else { return nil }
        defer { free(real) }
        return URL(filePath: String(cString: real), directoryHint: .isDirectory)
    }

    private static func path(of descriptor: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { return nil }
        return URL(filePath: String(cString: buffer), directoryHint: .notDirectory)
    }

    /// The directory's path as the system writes a descriptor's, which keeps the case on disk and the firmlinked
    /// form, so the file's can be compared with it exactly.
    private static func folderPath(of root: URL) -> URL? {
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        return path(of: descriptor)
    }

    private static func contains(_ folder: URL, _ file: URL) -> Bool {
        let base = folder.pathComponents
        let parts = file.pathComponents
        guard parts.count > base.count, Array(parts.prefix(base.count)) == base else { return false }
        return !parts.dropFirst(base.count).contains { $0.hasPrefix(".") }
    }

    /// Nil when the file could not be read.
    @concurrent func read(at offset: UInt64, count: Int) async -> Data? {
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, count, off_t(offset)) }
        guard read >= 0 else { return nil }
        data.count = read
        return data
    }
}
