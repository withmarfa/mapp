import SwiftUI
import WebKit

/// An HTML document shown as it was written, in a page that can reach nothing outside it (`SealedWebPage`). It draws
/// no header, border or other chrome; the place that shows it decides what goes around.
struct WebPageView: View {
    private let html: Data
    @State private var sealed: SealedWebPage?
    @State private var failure: String?

    /// An HTML document already in hand.
    init(html: Data) {
        self.html = html
    }

    var body: some View {
        Group {
            if let sealed {
                WebView(sealed.page)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .webViewMagnificationGestures(.disabled)
                    .webViewLinkPreviews(.disabled)
                    // Each document has a page of its own, so a new one gets a new web view, which lets go of the
                    // page that held the last document and stops its scripts.
                    .id(ObjectIdentifier(sealed.page))
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
        .task(id: html) { await load() }
    }

    private func load() async {
        failure = nil
        do {
            let page: SealedWebPage
            if let sealed { page = sealed } else { page = try await SealedWebPage.make() }
            try await page.show(html)
            sealed = page
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}
