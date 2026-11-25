import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Takes an item's page outside the app (`PageOpenTarget`) and says where: the default browser, the app that opens a
/// file, or Maps. The corner's Open and the File menu's command do the same.
enum PageOpener {
    @MainActor
    static func open(_ target: PageOpenTarget, for item: Item) {
        switch target {
        case .address(let address):
            NSWorkspace.shared.open(address)
        case .file(let file):
            NSWorkspace.shared.open(file)
        case .point(let point):
            if let address = PageOpenTarget.mapsAddress(for: point) { NSWorkspace.shared.open(address) }
        case .savedPage(let file):
            // The kept file has no extension, and a browser chooses how to read a file by its name.
            // One copy per item, replaced each time, so opening a page again does not leave another behind.
            guard let copy = QuickLookFile.copy(of: file, titled: item.displayTitle, as: .html, in: "Web Pages", key: item.id.rawValue) else { return }
            if let browser = browser() {
                NSWorkspace.shared.open([copy.url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(copy.url)
            }
        }
    }

    /// The name of the app that `target` opens in, as the person knows it: the default browser's, not a guess at Safari.
    /// Nil where no app is known to open it.
    @MainActor
    static func appName(for target: PageOpenTarget) -> String? {
        let app: URL? = switch target {
        case .address, .savedPage: browser()
        case .file(let file): NSWorkspace.shared.urlForApplication(toOpen: file)
        case .point(let point): PageOpenTarget.mapsAddress(for: point).flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        }
        return app.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    /// What the button's help and the command's title say: Open in the app's name, or just Open where none is known.
    static func title(opening name: String?) -> String {
        name.map { String(localized: "Open in \($0)") } ?? String(localized: "Open")
    }

    @MainActor
    private static func browser() -> URL? {
        URL(string: "https://example.com").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }
}

/// The corner's Open: an arrow out of an app, whose help names the app it opens in.
struct PageOpenButton: View {
    let target: PageOpenTarget
    let item: Item
    @State private var appName: String?

    var body: some View {
        let title = PageOpener.title(opening: appName)
        Button("Open", systemImage: "arrow.up.forward.app") { PageOpener.open(target, for: item) }
            .labelStyle(.iconOnly)
            .buttonStyle(CornerButtonStyle())
            .help(title)
            .accessibilityLabel(title)
            .accessibilityIdentifier("PageOpen")
            .task(id: target) { appName = PageOpener.appName(for: target) }
    }
}
