import SwiftUI

/// Where a file item's file is, however the library gets it.
enum ItemFileResolution: Equatable {
    case ready(URL)
    /// The library has no file for the item.
    case unavailable
    /// The library has one but could not get it. `reason` is in the person's words where the library gave them, and
    /// nil where the person is only told to check the connection.
    case failed(reason: String?)

    /// The file, fetched from the library.
    @MainActor static func fetch(_ id: ItemID, in library: any ItemLibrary) async -> Self {
        do {
            return try await library.fileURL(of: id).map { .ready($0) } ?? .unavailable
        } catch let failure as SourceFailure {
            return .failed(reason: failure.message)
        } catch {
            return .failed(reason: nil)
        }
    }
}

/// Which item's file is shown. Each load names its item, and only the latest load is shown, so a slow answer
/// for one item, as from a Try Again before the window moved on, never shows or shares under another.
@Observable final class ItemFileLoader {
    private(set) var shown: (id: ItemID, resolution: ItemFileResolution)?
    @ObservationIgnored private var latest = 0

    func resolution(of id: ItemID) -> ItemFileResolution? {
        shown.flatMap { $0.id == id ? $0.resolution : nil }
    }

    /// The item's file as this load found it, or nil where a later load has taken its place.
    func load(_ id: ItemID, in library: any ItemLibrary) async -> ItemFileResolution? {
        latest += 1
        let load = latest
        shown = nil
        let fetched = await ItemFileResolution.fetch(id, in: library)
        guard load == latest, !Task.isCancelled else { return nil }
        shown = (id, fetched)
        return fetched
    }
}

/// A file item's file, shown once it is fetched, under the page's notice (`PageNotice`) where it has one: a deleted item,
/// a held write, and a file the library does not have. Its viewer keeps its own scroller, so the notice stays above it.
struct ItemFileView: View {
    @CurrentLibrary private var library
    @StoredPageStyle private var style
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @State private var width: CGFloat = 0
    let id: ItemID
    /// The window the file's size and page are offered to once it is ready (`FileItemContent`).
    var details: DetailsPresentation?
    /// Told where the file is once it is, and nil when it is not, so a window can offer to share it.
    var onResolved: (URL?) -> Void = { _ in }

    @State private var loader = ItemFileLoader()

    private var item: Item? { library.item(id) }

    private var notice: PageNotice? {
        guard let item else { return nil }
        if case .unavailable? = loader.resolution(of: id) { return PageNotice.of(item, fileIsMissing: true) }
        return PageNotice.of(item)
    }

    var body: some View {
        // The task sits on one container. On the switch itself (`Group` hands a modifier to each branch) it would
        // start again with every branch, and a load changes the branch: the file would be fetched over and over.
        ZStack {
            switch loader.resolution(of: id) {
            case nil:
                ProgressView("Getting File…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let url):
                FileItemContent(url: url, title: item?.name ?? url.lastPathComponent, contentType: item?.fileType, item: id, details: details)
            // The page's notice says so.
            case .unavailable:
                Color.clear
            case .failed(let reason):
                ContentUnavailableView {
                    Label("Can’t Get This File", systemImage: "exclamationmark.icloud")
                } description: {
                    if let reason {
                        Text(reason)
                    } else {
                        Text("The app couldn’t get the file from the server. Check your connection, then try again.")
                    }
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let notice {
                PageNoticeView(notice: notice) { action in
                    action.run(for: id, in: library, undoManager: undoManager, openWindow: openWindow)
                }
                .padding(.horizontal, style.horizontalInset(for: width))
                .padding(.vertical, 12)
            }
        }
        .task(id: id) { await load() }
    }

    private func load() async {
        onResolved(nil)
        if case .ready(let url) = await loader.load(id, in: library) { onResolved(url) }
    }
}

/// The page of an item that is not shown as text (`ItemLibrary.pageLayout(of:)`): an HTML document in the sealed web
/// page, under the item's title, or any other file in its preview.
struct FileItemPage: View {
    @CurrentLibrary private var library
    let item: Item
    let drafts: DetailsPresentation
    /// Shows the item a link in the page names.
    let open: (ItemID) -> Void
    var onResolved: (URL?) -> Void = { _ in }
    /// Whether a web page backs the toolbar with a band while it is scrolled under it (`WebPageItemPage`).
    var backsToolbar = true

    var body: some View {
        // The corner's Open takes the file from the window's presentation, so every window tells it.
        let resolved: (URL?) -> Void = { [id = item.id, drafts] url in
            drafts.fileResolved(url, for: id)
            onResolved(url)
        }
        if case .webPage(let document, let runsScripts) = library.pageLayout(of: item) {
            WebPageItemPage(
                item: item, document: document, runsScripts: runsScripts, drafts: drafts, open: open, onResolved: resolved,
                backsToolbar: backsToolbar)
        } else {
            ItemFileView(id: item.id, details: drafts, onResolved: resolved)
        }
    }
}
