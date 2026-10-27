import MarfaIcons
import SwiftUI

/// A Web Page item's page: its title and byline in the manner of the note page's header, then the HTML filling the
/// rest of the detail area, shown as it was written (`WebPageView`). The body is read only, and a file's title and
/// properties are not edited on the page, as for every file; the inspector shows them.
struct WebPageItemPage: View {
    private enum Content: Equatable {
        case loading
        case ready(Data)
        /// The library has no file for the item.
        case unavailable
        /// The library has one but could not get it.
        case failed
        /// The file is not an HTML page.
        case notHTML
    }

    private struct Load: Hashable {
        let id: ItemID
        let version: ItemVersion
    }

    @CurrentLibrary private var library
    @StoredPageStyle private var style
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    let item: Item
    /// Told where the file is once it is, and nil when it is not, so the window can share it and open it in a browser.
    var onResolved: (URL?) -> Void = { _ in }

    @State private var loader = ItemFileLoader()
    @State private var content = Content.loading
    @State private var shownID: ItemID?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                WebPageHeader(item: item, inset: style.horizontalInset(for: geometry.size.width))
                pageBody
            }
        }
        .accessibilityIdentifier("WebPageItemPage")
        .task(id: Load(id: item.id, version: item.version)) { await load() }
    }

    @ViewBuilder private var pageBody: some View {
        switch content {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let html):
            WebPageView(html: html)
        case .unavailable:
            ContentUnavailableView("File Unavailable", systemImage: "doc.badge.ellipsis")
        case .failed:
            ContentUnavailableView {
                Label("Can’t Get This File", systemImage: "exclamationmark.icloud")
            } description: {
                Text("MAPP couldn’t get the file from the server. Check your connection, then try again.")
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        case .notHTML:
            ContentUnavailableView {
                Label("Can’t Show This Page", systemImage: "doc.questionmark")
            } description: {
                Text("This file isn’t an HTML page.")
            }
        }
    }

    private func load() async {
        onResolved(nil)
        // A change to the same item's file is shown over the page it replaces, not a blank one.
        if shownID != item.id { content = .loading }
        shownID = item.id
        guard WebPageFile.isHTML(item.fileType) else {
            content = .notHTML
            return
        }
        switch await loader.load(item.id, in: library) {
        case nil:
            return
        case .unavailable:
            content = .unavailable
        case .failed:
            content = .failed
        case .ready(let url):
            onResolved(url)
            do {
                let html = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                guard !Task.isCancelled else { return }
                content = .ready(html)
            } catch {
                guard !Task.isCancelled else { return }
                content = .failed
            }
        }
    }
}

/// The title and the line under it: what the item is, who it came from and when. The sizes follow the note page's
/// header, a bold title at nearly twice the text size and a quiet secondary line at the interface's text size.
private struct WebPageHeader: View {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    @StoredPageStyle private var style
    let item: Item
    let inset: CGFloat

    var body: some View {
        let byline = PageByline(item: item, now: library.now())
        let type = library.catalogue.itemTypes[item.type]
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: item.title)
                .font(.system(size: CGFloat(style.textSize) * 1.9, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("WebPageTitle")
            HStack(spacing: 4) {
                TypeIcon(name: library.catalogue.icon(for: item.type))
                if let type { Text(verbatim: ItemPageHeader.localized(type.label)) }
                ForEach(Array([byline.source, byline.date].compactMap { $0 }.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, part in
                    Circle().fill(.secondary).opacity(0.7).frame(width: 2, height: 2).accessibilityHidden(true)
                    Text(verbatim: part)
                }
            }
            .font(.system(size: CGFloat(interfaceTextSize)))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("WebPageByline")
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, inset)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}
