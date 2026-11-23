import Foundation
import Observation

/// The versions of one item that Version History lists. The server gives them oldest first and no other way, while the
/// thread reads newest first, so the pages are read one after another until the end (up to `autoPages` of them),
/// and the thread grows as each arrives. A history longer than that stops with Load More.
@Observable final class ItemHistoryModel {
    enum Phase: Equatable {
        case idle
        /// The first page is on its way.
        case loading
        case loaded
        /// Nothing could be listed; a failure after the first page keeps the list and is in `moreFailure`.
        case failed(ItemHistoryFailure)
    }

    /// How many snapshots one request asks for. The server allows 200.
    static let pageSize = 200
    /// How many pages one read follows before it stops and offers Load More: 2,000 versions, more than the server
    /// keeps by default, so a server that answers only empty pages with a cursor never keeps the thread busy.
    static let autoPages = 10

    let id: ItemID
    @ObservationIgnored private let source: (any ItemHistorySource)?
    private(set) var snapshots: [ItemSnapshot] = []
    private(set) var phase = Phase.idle
    /// Whether the server has more versions after those listed.
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    /// Why the last Load More failed. The versions listed stay.
    private(set) var moreFailure: ItemHistoryFailure?
    var selection: String?

    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var loading: Task<Void, Never>?

    init(id: ItemID, source: (any ItemHistorySource)?) {
        self.id = id
        self.source = source
    }

    /// Whether every version the server holds has been read, so the thread is whole.
    var isComplete: Bool { phase == .loaded && !hasMore }

    var selected: ItemSnapshot? {
        selection.flatMap { id in snapshots.first { $0.id == id } }
    }

    /// Reads the first page. Run again to try again after a failure.
    func load() {
        guard let source else {
            phase = .failed(.unsupported)
            return
        }
        loading?.cancel()
        snapshots = []
        cursor = nil
        hasMore = false
        moreFailure = nil
        selection = nil
        phase = .loading
        isLoadingMore = false
        loading = Task { await self.fetch(from: source, first: true) }
    }

    func loadMore() {
        guard let source, hasMore, !isLoadingMore, phase == .loaded else { return }
        moreFailure = nil
        isLoadingMore = true
        loading = Task { await self.fetch(from: source, first: false) }
    }

    /// Stops a read still under way, as Version History closes.
    func cancel() {
        loading?.cancel()
        loading = nil
    }

    private func fetch(from source: any ItemHistorySource, first: Bool) async {
        var pages = 0
        while !Task.isCancelled {
            let page: ItemHistoryPage
            do {
                page = try await source.page(of: id, after: cursor, limit: Self.pageSize)
            } catch {
                guard !Task.isCancelled else { return }
                if first && pages == 0 { phase = .failed(error) } else { moreFailure = error }
                isLoadingMore = false
                return
            }
            guard !Task.isCancelled else { return }
            pages += 1
            // Versions are not contiguous, since the server thins old ones, so they are told apart by number alone.
            let held = Set(snapshots.map(\.version))
            let fresh = page.snapshots.filter { !held.contains($0.version) }
            snapshots = (snapshots + fresh).sorted { $0.version < $1.version }
            // A cursor that leads back to the page just read ends the list instead of looping.
            let next = page.next == cursor ? nil : page.next
            cursor = next
            hasMore = next != nil
            phase = .loaded
            guard next != nil, pages < Self.autoPages else {
                isLoadingMore = false
                return
            }
            isLoadingMore = true
        }
    }
}
