import Foundation
import Observation

/// The versions of one item that the Version History sheet lists: read a page at a time from the library's source,
/// oldest first as the server gives them, never all at once.
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
    static let pageSize = 100
    /// Empty pages followed in a row before the list stops and offers Load More, so a server that answers only
    /// empty pages with a cursor never keeps the sheet busy.
    private static let emptyPagesFollowed = 20

    let id: ItemID
    @ObservationIgnored private let source: (any ItemHistorySource)?
    private(set) var snapshots: [ItemSnapshot] = []
    private(set) var phase = Phase.idle
    /// Whether the server has more versions after those listed.
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    /// Why the last Load More failed. The versions listed stay.
    private(set) var moreFailure: ItemHistoryFailure?
    var selection: ItemSnapshot.ID?

    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var loading: Task<Void, Never>?

    init(id: ItemID, source: (any ItemHistorySource)?) {
        self.id = id
        self.source = source
    }

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

    /// Stops a read still under way, as the sheet closes.
    func cancel() {
        loading?.cancel()
        loading = nil
    }

    private func fetch(from source: any ItemHistorySource, first: Bool) async {
        var empty = 0
        while !Task.isCancelled {
            let page: ItemHistoryPage
            do {
                page = try await source.page(of: id, after: cursor, limit: Self.pageSize)
            } catch {
                guard !Task.isCancelled else { return }
                if first { phase = .failed(error) } else { moreFailure = error }
                isLoadingMore = false
                return
            }
            guard !Task.isCancelled else { return }
            // Versions are not contiguous, since the server thins old ones, so they are told apart by number alone.
            let held = Set(snapshots.map(\.version))
            let fresh = page.snapshots.filter { !held.contains($0.version) }
            snapshots = (snapshots + fresh).sorted { $0.version < $1.version }
            // A cursor that leads back to the page just read ends the list instead of looping.
            let next = page.next == cursor ? nil : page.next
            cursor = next
            hasMore = next != nil
            phase = .loaded
            isLoadingMore = false
            if fresh.isEmpty && next != nil {
                empty += 1
                guard empty < Self.emptyPagesFollowed else { return }
                isLoadingMore = true
                continue
            }
            return
        }
    }
}
