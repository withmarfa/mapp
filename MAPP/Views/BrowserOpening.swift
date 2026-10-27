import AppKit
import UniformTypeIdentifiers

/// Hands a Web Page to the person's default browser.
enum BrowserOpening {
    @MainActor
    static func open(_ target: BrowserTarget, for item: Item) {
        switch target {
        case .address(let address):
            NSWorkspace.shared.open(address)
        case .file(let file):
            // The kept file has no extension, and a browser chooses how to read a file by its name.
            // One copy per item, replaced each time, so opening a page again does not leave another behind.
            guard let copy = QuickLookFile.copy(of: file, titled: item.title, as: .html, in: "Web Pages", key: item.id.rawValue) else { return }
            let browser = URL(string: "https://example.com").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
            if let browser {
                NSWorkspace.shared.open([copy.url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(copy.url)
            }
        }
    }
}
