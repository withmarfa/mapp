import SwiftUI
import WebKit

/// An HTML document shown as it was written, in a page that can reach nothing outside it (`SealedWebPage`). It draws
/// no header, border or other chrome; the place that shows it decides what goes around. Its pictures come from
/// `pictures`, once `SealedPictureRewrite` has pointed them there; the page it was first shown with keeps answering, so a
/// place that shows another item's document gives it a view of its own.
struct WebPageView: View {
    private let html: Data
    private let pictures: SealedPictures?
    private let runsScripts: Bool
    @State private var sealed: SealedWebPage?
    @State private var failure: String?

    /// An HTML document already in hand, which runs its own scripts only where `runsScripts` says so.
    init(html: Data, pictures: SealedPictures? = nil, runsScripts: Bool) {
        self.html = html
        self.pictures = pictures
        self.runsScripts = runsScripts
    }

    var body: some View {
        Group {
            // The failure comes first, since the page that is still held is the last document's, not this one's.
            if let failure {
                ContentUnavailableView {
                    Label("Can’t Show This Page", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                }
            } else if let sealed {
                WebView(sealed.page)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .webViewMagnificationGestures(.disabled)
                    .webViewLinkPreviews(.disabled)
                    // Each document has a page of its own, so a new one gets a new web view, which lets go of the
                    // page that held the last document and stops its scripts.
                    .id(ObjectIdentifier(sealed.page))
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("WebPageView")
        .task(id: html) { await load() }
        .onChange(of: pictures?.version) { _, version in
            guard let version, let sealed else { return }
            Task { await sealed.redrawPictures(version: version) }
        }
    }

    private func load() async {
        failure = nil
        do {
            let page: SealedWebPage
            if let sealed { page = sealed } else { page = try await SealedWebPage.make(pictures: pictures, runsScripts: runsScripts) }
            try await page.show(html)
            sealed = page
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}
