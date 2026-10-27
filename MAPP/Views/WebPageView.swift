import SwiftUI
import WebKit

/// An HTML document shown as it was written, in a page that can reach nothing outside it (`SealedWebPage`). It draws
/// no header, border or other chrome; the place that shows it decides what goes around.
///
/// A `core.file.webpage` item's file is read through the library, which fetches it from the server first if the Mac does
/// not hold it yet.
struct WebPageView: View {
    private enum Source: Equatable {
        case html(Data)
        case item(ItemID, ItemVersion)
    }

    @CurrentLibrary private var library
    private let source: Source
    @State private var sealed: SealedWebPage?
    @State private var failure: String?

    /// The file of a Web Page item.
    init(item: Item) {
        source = .item(item.id, item.version)
    }

    /// An HTML document already in hand.
    init(html: Data) {
        source = .html(html)
    }

    var body: some View {
        Group {
            if let sealed {
                WebView(sealed.page)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .webViewMagnificationGestures(.disabled)
                    .webViewLinkPreviews(.disabled)
            } else if let failure {
                ContentUnavailableView {
                    Label("Can’t Show This Page", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("WebPageView")
        .task(id: source) { await load() }
    }

    private func load() async {
        failure = nil
        do {
            let html = try await bytes()
            let page: SealedWebPage
            if let sealed { page = sealed } else { page = try await SealedWebPage.make() }
            try await page.show(html)
            sealed = page
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }

    private func bytes() async throws -> Data {
        switch source {
        case .html(let data): return data
        case .item(let id, _):
            guard let url = try await library.fileURL(of: id) else {
                throw WebPageFailure.noFile
            }
            return try Data(contentsOf: url)
        }
    }

    private enum WebPageFailure: LocalizedError {
        case noFile
        var errorDescription: String? { String(localized: "This item has no file to show.") }
    }
}
