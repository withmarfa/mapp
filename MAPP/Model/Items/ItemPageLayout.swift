import Foundation
import UniformTypeIdentifiers

/// How an item's page is laid out: its text in the editor, a file in its preview, or an HTML document in the sealed web
/// page under the item's title and byline.
nonisolated enum ItemPageLayout: Equatable, Sendable {
    /// The editor, with the item's header and text.
    case text
    /// The file's preview, for a file that is not HTML.
    case file
    /// The HTML of `document`, which is the item itself or an HTML file attached to it, in the sealed web page.
    /// `runsScripts` is true only for a Web Page, whose saved page may need its scripts to draw; any other document
    /// is shown as written, with none of its scripts run.
    case webPage(document: ItemID, runsScripts: Bool)
}

extension ItemLibrary {
    /// The one rule that chooses an item's page. It reads only what the library holds now, so the page does not change
    /// layout while a file is fetched.
    ///
    /// - A file whose type is HTML (or a Web Page) opens in the sealed web page, never Quick Look, which fetches every
    ///   picture the HTML points to without asking. A file the library does not know the type of is judged by its
    ///   title's extension.
    /// - Any other file opens in its preview.
    /// - An item to read (`PageHeaderKind.reading`: a bookmark or media) that is not a file, but has a file attached
    ///   that is not in the bin and is HTML by its content type (or, where that is unknown, its extension), opens to
    ///   that document under the item's own title and byline, as an article saved with its source does. Of several,
    ///   the oldest is shown. Any other item keeps its text, even with an HTML file attached, so a note is never
    ///   hidden by one.
    /// - Every other item opens to its text.
    func pageLayout(of item: Item) -> ItemPageLayout {
        if item.isFile {
            if isWebPage(item) { return .webPage(document: item.id, runsScripts: true) }
            return Self.isHTMLFile(item) ? .webPage(document: item.id, runsScripts: false) : .file
        }
        guard PageHeaderKind.of(item.type, in: catalogue) == .reading else { return .text }
        let documents = attachments(of: item.id).compactMap { self.item($0) }
            .filter { file in
                file.isFile && file.state != .trashed && Self.isHTMLFile(file)
            }
            .sorted { ($0.created, $0.id.rawValue) < ($1.created, $1.id.rawValue) }
        if let document = documents.first { return .webPage(document: document.id, runsScripts: false) }
        return .text
    }

    private static func isHTMLFile(_ file: Item) -> Bool {
        var type = file.fileType
        if type == nil || type == .data {
            type = UTType(filenameExtension: (file.title as NSString).pathExtension)
        }
        guard let type else { return false }
        if type.conforms(to: .html) { return true }
        return UTType(mimeType: "application/xhtml+xml").map { type.conforms(to: $0) } ?? false
    }
}
