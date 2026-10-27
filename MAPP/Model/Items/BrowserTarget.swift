import Foundation
import UniformTypeIdentifiers

/// What "Open in Browser" opens for a Web Page: the address the page came from where the item names one, since the
/// live page is what a person means, and otherwise the saved HTML file.
nonisolated enum BrowserTarget: Equatable, Sendable {
    case address(URL)
    /// The page's own file, which the browser is given a copy of under a name that ends in `.html`.
    case file(URL)

    /// The properties that hold the page's address, in the order they are preferred: `url` (Web address) and then
    /// `source_url` (where the file was sourced from).
    static let addressKeys = ["url", "source_url"]

    static func of(_ item: Item, fetchedFile: URL?) -> BrowserTarget? {
        for key in addressKeys {
            let text = item.value(of: key)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let address = ReadingHeader.webAddress(text) { return .address(address) }
        }
        return fetchedFile.map { .file($0) }
    }
}

/// Whether a Web Page's file can be shown as one.
nonisolated enum WebPageFile {
    /// A file the library does not know the type of is given the benefit of the doubt; any type it does know must be
    /// HTML.
    static func isHTML(_ type: UTType?) -> Bool {
        guard let type, type != .data else { return true }
        if type.conforms(to: .html) { return true }
        return UTType(mimeType: "application/xhtml+xml").map { type.conforms(to: $0) } ?? false
    }
}
