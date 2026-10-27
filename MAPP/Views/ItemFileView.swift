import SwiftUI

/// Where a file item's file is, however the library gets it.
enum ItemFileResolution: Equatable {
    case ready(URL)
    /// The library has no file for the item.
    case unavailable
    /// The library has one but could not get it.
    case failed

    /// The file, fetched from the library.
    @MainActor static func fetch(_ id: ItemID, in library: any ItemLibrary) async -> Self {
        do {
            return try await library.fileURL(of: id).map { .ready($0) } ?? .unavailable
        } catch {
            return .failed
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

/// A file item's file, shown once it is fetched. An item the library has no file for shows that it has none.
struct ItemFileView: View {
    @CurrentLibrary private var library
    let id: ItemID
    /// Told where the file is once it is, and nil when it is not, so a window can offer to share it.
    var onResolved: (URL?) -> Void = { _ in }

    @State private var loader = ItemFileLoader()

    private var item: Item? { library.item(id) }

    var body: some View {
        // The task sits on one container. On the switch itself (`Group` hands a modifier to each branch) it would
        // start again with every branch, and a load changes the branch: the file would be fetched over and over.
        ZStack {
            switch loader.resolution(of: id) {
            case nil:
                ProgressView("Getting File…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let url):
                FileItemContent(url: url, title: item?.title ?? url.lastPathComponent, contentType: item?.fileType)
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
            }
        }
        .task(id: id) { await load() }
    }

    private func load() async {
        onResolved(nil)
        if case .ready(let url) = await loader.load(id, in: library) { onResolved(url) }
    }
}

/// A file item's page: a Web Page has its own, and every other file is previewed.
struct FileItemPage: View {
    @CurrentLibrary private var library
    let item: Item
    var onResolved: (URL?) -> Void = { _ in }

    var body: some View {
        if library.isWebPage(item) {
            WebPageItemPage(item: item, onResolved: onResolved)
        } else {
            ItemFileView(id: item.id, onResolved: onResolved)
        }
    }
}
