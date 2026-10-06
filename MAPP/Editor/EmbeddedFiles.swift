import AppKit
import Darwin
import Synchronization
import UniformTypeIdentifiers
import WebKit

/// An embed as a note names a file: by a path from the note, as `![](path)` does, or by name, as `![[name]]`
/// does. A path is as the markdown writes it, still percent-encoded and with any query or fragment.
nonisolated enum EmbedReference: Hashable, Sendable {
    case path(String)
    case name(String)

    /// The item and embed the page names, as `{ item, path }` or `{ item, name }`.
    static func request(_ body: Any?) -> (item: ItemID, reference: EmbedReference)? {
        guard let dict = body as? [String: Any], let item = dict["item"] as? String, !item.isEmpty else { return nil }
        if let path = dict["path"] as? String { return (ItemID(item), .path(path)) }
        if let name = dict["name"] as? String { return (ItemID(item), .name(name)) }
        return nil
    }
}

// MARK: Resolving

extension ItemLibrary {
    /// The local file an item's embed names, or nil where there is none: a file inside the notes folder, reached
    /// without a symbolic link, read as Marfa's core reads the embed (`EmbedPaths`). The one place an embed
    /// becomes a file, which the page's scheme and its Open both ask.
    func embeddedFile(_ reference: EmbedReference, in item: ItemID) async -> URL? {
        guard let root = folderURL, let directory = imageBase(of: item) else { return nil }
        return await EmbedPaths.file(reference, from: directory, in: root)
    }

    /// The embedded file opened for reading, or nil where there is none. The folder can change between
    /// finding the file and opening it, so the file opened is checked again by what it is, not by the path
    /// it was found at: everything the page is told and served comes from this descriptor.
    func openEmbeddedFile(_ reference: EmbedReference, in item: ItemID) async -> OpenFile? {
        guard let root = folderURL, let file = await embeddedFile(reference, in: item) else { return nil }
        return await OpenFile.open(file, inside: root)
    }
}

/// How Marfa's core reads an embed's path or name (`body/embed.rs` and `body/text.rs` in marfa-core), and the
/// folder's files it can name.
nonisolated enum EmbedPaths {
    /// A document embedded is a note shown in the note, which is text, not a file.
    static let documentExtensions: Set<String> = ["md", "markdown", "txt"]

    @concurrent static func file(_ reference: EmbedReference, from directory: String, in root: URL) async -> URL? {
        let path: String?
        switch reference {
        case .path(let destination):
            guard !isAddress(destination) else { return nil }
            let local = decoded(destination)
            path = local.isEmpty || isDocument(local) ? nil : joined(directory, local)
        case .name(let typed):
            let name = typed.trimmingCharacters(in: .whitespaces)
            if name.isEmpty || isDocument(name) {
                path = nil
            } else if name.hasPrefix("./") || name.hasPrefix("../") {
                path = joined(directory, name)
            } else {
                // A file just written may be newer than the folder's listing, so a name nothing answers to is
                // looked for again in the folder as it now is.
                path = named(name, from: directory, among: FolderFiles.paths(in: root))
                    ?? named(name, from: directory, among: FolderFiles.paths(in: root, fresh: true))
            }
        }
        return path.flatMap { FolderFiles.file(at: $0, in: root) }
    }

    /// An address, which the page never loads: a scheme, `//` or `#`.
    static func isAddress(_ destination: String) -> Bool {
        if destination.hasPrefix("//") || destination.hasPrefix("#") { return true }
        guard let colon = destination.firstIndex(of: ":") else { return false }
        let scheme = destination[..<colon]
        return scheme.first?.isASCII == true && scheme.first?.isLetter == true
            && scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) }
    }

    /// The path without its query or fragment, its percent escapes decoded byte by byte.
    static func decoded(_ destination: String) -> String {
        let path = Array(destination.prefix { $0 != "?" && $0 != "#" }.utf8)
        var bytes: [UInt8] = []
        var index = 0
        while index < path.count {
            if path[index] == UInt8(ascii: "%"), index + 2 < path.count,
               let byte = UInt8(String(decoding: path[index + 1...index + 2], as: UTF8.self), radix: 16) {
                bytes.append(byte)
                index += 3
            } else {
                bytes.append(path[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func isDocument(_ path: String) -> Bool {
        let name = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return documentExtensions.contains(name[name.index(after: dot)...].lowercased())
    }

    /// The path read from the note's directory, or from the folder's root where it opens with `/`; nil where it
    /// leads out of the folder.
    static func joined(_ directory: String, _ path: String) -> String? {
        let rooted = path.hasPrefix("/")
        var parts = rooted ? [] : directory.split(separator: "/").map(String.init)
        for part in path.split(separator: "/").map(String.init) {
            switch part {
            case ".": continue
            case "..":
                guard parts.popLast() != nil else { return nil }
            default: parts.append(part)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// Names compared as macOS and Obsidian compare them, without regard to case or Unicode form.
    static func folded(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
    }

    /// The file `![[name]]` names: the path from the folder's root, else the file whose path ends in the name at
    /// a directory's edge, nearest the note, in its own directory first, then the shallowest, then the first in
    /// path order, so every machine resolves it alike.
    static func named(_ name: String, from directory: String, among paths: [String]) -> String? {
        let wanted = folded(String(name.drop { $0 == "/" }))
        let here = folded(directory.isEmpty ? "" : directory + "/")
        func folder(_ path: String) -> String {
            path.lastIndex(of: "/").map { String(path[...$0]) } ?? ""
        }
        return paths
            .map { (path: $0, folded: folded($0)) }
            .filter { $0.folded == wanted || $0.folded.hasSuffix("/" + wanted) }
            .min { one, other in
                let left = (one.folded == wanted ? 0 : 1, folder(one.folded) == here ? 0 : 1, one.path.count { $0 == "/" })
                let right = (other.folded == wanted ? 0 : 1, folder(other.folded) == here ? 0 : 1, other.path.count { $0 == "/" })
                if left != right { return left < right }
                return one.path.utf8.lexicographicallyPrecedes(other.path.utf8)
            }?
            .path
    }
}

/// The notes folder's own files, as an embed may name them: inside the folder, never through a symbolic link or
/// a name starting with a dot, and only an ordinary file. Each URL is the file's real path, with no symbolic
/// link anywhere in it, so `OpenFile` can refuse one put in the way after the file was found.
nonisolated enum FolderFiles {
    /// The folder's real path. `resolvingSymlinksInPath` keeps `/var` rather than `/private/var`, a path
    /// that still runs through a link.
    static func realPath(of root: URL) -> URL? {
        guard let real = realpath(root.path, nil) else { return nil }
        defer { free(real) }
        return URL(filePath: String(cString: real), directoryHint: .isDirectory)
    }

    static func file(at path: String, in root: URL) -> URL? {
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty, var url = realPath(of: root) else { return nil }
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        for (index, part) in parts.enumerated() {
            guard !part.hasPrefix(".") else { return nil }
            var next = url.appending(path: part, directoryHint: .notDirectory)
            var values = try? next.resourceValues(forKeys: keys)
            if values == nil {
                // A path names a file whatever its case or Unicode form, as Marfa reads one on every machine.
                let wanted = EmbedPaths.folded(part)
                guard let match = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
                    .first(where: { EmbedPaths.folded($0) == wanted })
                else { return nil }
                next = url.appending(path: match, directoryHint: .notDirectory)
                values = try? next.resourceValues(forKeys: keys)
            }
            guard let values, values.isSymbolicLink != true else { return nil }
            let last = index == parts.count - 1
            guard last ? values.isRegularFile == true : values.isDirectory == true else { return nil }
            url = next
        }
        return url
    }

    /// Every embed by name on a page reads the folder, so one reading serves those asked for together.
    private static let recent = Mutex<(root: URL, at: ContinuousClock.Instant, paths: [String])?>(nil)

    /// The paths of the folder's ordinary files, relative to it, as Marfa's core walks the folder: into every
    /// directory, packages among them, but none whose name starts with a dot.
    static func paths(in root: URL, fresh: Bool = false) -> [String] {
        let now = ContinuousClock.now
        if !fresh, let held = recent.withLock({ $0 }), held.root == root, now - held.at < .seconds(2) {
            return held.paths
        }
        guard let base = realPath(of: root) else { return [] }
        let depth = base.pathComponents.count
        var paths: [String] = []
        let walk = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        while let url = walk?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            paths.append(url.pathComponents.dropFirst(depth).joined(separator: "/"))
        }
        recent.withLock { $0 = (root, now, paths) }
        return paths
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
    var open: (EmbedReference, ItemID) async -> OpenFile? = { _, _ in nil }
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
        Task {
            guard let file = await open(reference, item) else { return replyHandler(nil, nil) }
            let type = UTType(filenameExtension: file.url.pathExtension)
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
        let (key, value) = switch reference {
        case .path(let path): ("path", path)
        case .name(let name): ("name", name)
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "file"
        components.path = "/"
        components.percentEncodedQueryItems = [("item", item.rawValue), (key, value), ("v", String(version))].map {
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
        guard let item = value("item"), !item.isEmpty else { return nil }
        if let path = value("path") { return (ItemID(item), .path(path)) }
        if let name = value("name") { return (ItemID(item), .name(name)) }
        return nil
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
        guard let (item, reference) = Self.request(in: url), let file = await open(reference, item) else {
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
/// notes folder, under no name starting with a dot. That check is of the descriptor, so a folder or file
/// changed after the path was found can never put anything else behind it.
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

    private static func path(of descriptor: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { return nil }
        return URL(filePath: String(cString: buffer), directoryHint: .notDirectory)
    }

    /// The folder's path as the system writes a descriptor's, which keeps the case on disk and the firmlinked
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
