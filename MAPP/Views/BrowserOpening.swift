import AppKit
import UniformTypeIdentifiers

/// Hands a Web Page to the person's default browser.
enum BrowserOpening {
    @MainActor
    static func open(_ target: BrowserTarget, titled title: String) {
        switch target {
        case .address(let address):
            NSWorkspace.shared.open(address)
        case .file(let file):
            // The kept file has no extension, and a browser chooses how to read a file by its name.
            guard let copy = QuickLookFile.copy(of: file, titled: title, as: .html, in: "Open in Browser") else { return }
            let browser = URL(string: "https://example.com").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
            if let browser {
                NSWorkspace.shared.open([copy.url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(copy.url)
            }
        }
    }
}
