import SwiftUI

/// Where a file item's file is, however the library gets it.
enum ItemFileResolution: Equatable {
    case ready(URL)
    /// The library has no file for the item, as a library without files has none.
    case unavailable
    /// The library has one but could not get it.
    case failed

    /// A file at hand, as a folder's are, which needs no wait.
    @MainActor static func atHand(_ id: ItemID, in library: any ItemLibrary) -> Self? {
        library.fileURL(for: id).map { .ready($0) }
    }

    /// A file fetched where it is not at hand, as a server's are.
    @MainActor static func fetch(_ id: ItemID, in library: any ItemLibrary) async -> Self {
        do {
            return try await library.fileURL(of: id).map { .ready($0) } ?? .unavailable
        } catch {
            return .failed
        }
    }
}

/// A file item's file, shown as soon as it is at hand and fetched where it is not. A library without files has
/// nothing to show, and says so.
struct ItemFileView: View {
    @CurrentLibrary private var library
    let id: ItemID
    /// Told where the file is once it is, and nil when it is not, so a window can offer to share it.
    var onResolved: (URL?) -> Void = { _ in }

    @State private var resolution: ItemFileResolution?

    var body: some View {
        Group {
            switch resolution {
            case nil:
                ProgressView("Getting File…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let url):
                FileItemContent(url: url)
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
        if let atHand = ItemFileResolution.atHand(id, in: library) {
            resolution = atHand
        } else {
            resolution = nil
            onResolved(nil)
            let fetched = await ItemFileResolution.fetch(id, in: library)
            guard !Task.isCancelled else { return }
            resolution = fetched
        }
        if case .ready(let url) = resolution { onResolved(url) }
    }
}
