import Foundation
import Observation

/// The Items index's rows under each tab, in the order of the person's sort, kept by the window so that leaving the page
/// for another place or an item's full page and coming back shows them at once, and works them out again behind.
///
/// A library of tens of thousands of items must not be read, ordered and split by tier on the main thread each time
/// the person changes tab or types in another window. The rows are worked out once for the items and the sort, off the
/// main thread when there are many, and a change of tab only reads one of the arrays. A run of edits to a large library
/// is let settle before the rows are worked out again; an item that has gone, deleted or erased, leaves the rows at
/// once rather than when they have settled, and the chosen item keeps its place until the person chooses another, so a
/// sort by the latest change does not carry the row they are editing off from under them (`pin`).
@MainActor
@Observable
final class ItemIndexModel {
    /// Up to this many items the rows are worked out in place, so a small library never shows the page empty first.
    nonisolated static let inlineLimit = 2_000
    /// How long a run of changes to a large library is let settle.
    nonisolated static let settling = Duration.milliseconds(300)

    /// How long this model lets a run of changes settle; a test holds it long to see what happens before.
    @ObservationIgnored private let settleTime: Duration

    init(settling: Duration = ItemIndexModel.settling) { settleTime = settling }

    /// The rows under each tab; nil until they have been worked out.
    private(set) var tabs: ItemIndexTabs?

    /// Names the library followed. A change of library, or stopping, makes every answer still on its way stale.
    @ObservationIgnored private var generation = 0
    /// Names the arrangement last asked for. A change to the library or the sort makes an earlier answer stale, so one
    /// that lists less than the library does is never shown.
    @ObservationIgnored private var stamp = 0
    @ObservationIgnored private var library: (any ItemLibrary)?
    @ObservationIgnored private var sort = IndexPlace.items.defaultSort
    @ObservationIgnored private var settle: Task<Void, Never>?
    @ObservationIgnored private var itemCount = 0
    /// Names the read whose observation is armed, so a read made for a new sort leaves the earlier one's alone.
    @ObservationIgnored private var armed = 0
    /// The library whose items `tabs` lists, kept while the page is away so that coming back to the same library shows them.
    @ObservationIgnored private var listed: ObjectIdentifier?
    /// The library's membership when `tabs` was last true to it, so that only a change of membership looks for gone items.
    @ObservationIgnored private var membership = 0
    /// The item whose row keeps its place through a re-sort.
    @ObservationIgnored private var pinned: ItemID?

    /// Starts following `library`, ordering by `sort`. Following the library already followed only changes the order.
    func follow(_ library: any ItemLibrary, sort: IndexSort) {
        if let followed = self.library, followed === library {
            guard sort != self.sort else { return }
            self.sort = sort
            pinned = nil
            read(generation: generation)
            return
        }
        generation += 1
        stamp += 1
        settle?.cancel()
        self.library = library
        if listed == ObjectIdentifier(library) {
            // What was listed when the page went away shows until it is worked out again, less what has gone since.
            removeGone(from: library)
        } else {
            tabs = nil
            listed = ObjectIdentifier(library)
        }
        self.sort = sort
        read(generation: generation)
    }

    /// Stops following the library, which the window's other pages need no rows of. The rows stay, for the page's return.
    func stop() {
        generation += 1
        stamp += 1
        settle?.cancel()
        library = nil
        pinned = nil
    }

    /// Forgets everything, for a window that changes library.
    func reset() {
        stop()
        tabs = nil
        listed = nil
    }

    /// Keeps the row of `id`, the item chosen, where it is while the rows are worked out again. Nil, or another item,
    /// lets the earlier one go to its place at the next change.
    func pin(_ id: ItemID?) { pinned = id }

    private func read(generation: Int) {
        guard let library, generation == self.generation else { return }
        stamp += 1
        armed += 1
        let (stamp, armed) = (stamp, armed)
        let (items, catalogue, directory) = withObservationTracking {
            (library.items(in: .allItems), library.catalogue, library.sources)
        } onChange: { [weak self] in
            // Called before the change lands, so the library is read again after it.
            Task { @MainActor [weak self] in self?.changed(generation: generation, armed: armed) }
        }
        itemCount = items.count
        membership = library.membershipRevision
        let sort = sort
        guard items.count > Self.inlineLimit else {
            show(ItemIndexRows.tabs(of: items, catalogue: catalogue, directory: directory, sort: sort), generation: generation, stamp: stamp)
            return
        }
        Task { [weak self] in
            let arranged = await Task.detached(priority: .userInitiated) {
                ItemIndexRows.tabs(of: items, catalogue: catalogue, directory: directory, sort: sort)
            }.value
            self?.show(arranged, generation: generation, stamp: stamp)
        }
    }

    private func changed(generation: Int, armed: Int) {
        guard generation == self.generation, armed == self.armed else { return }
        settle?.cancel()
        stamp += 1
        if let library, library.membershipRevision != membership {
            membership = library.membershipRevision
            removeGone(from: library)
        }
        guard itemCount > Self.inlineLimit else { return read(generation: generation) }
        let wait = settleTime
        settle = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.read(generation: generation)
        }
    }

    private func show(_ arranged: ItemIndexTabs, generation: Int, stamp: Int) {
        guard generation == self.generation, stamp == self.stamp else { return }
        guard let pinned, let earlier = tabs else { return tabs = arranged }
        tabs = arranged.holding(pinned, as: earlier)
    }

    /// Takes out the rows of items the library no longer lists, which a re-sort of many items would otherwise leave
    /// for a few hundred milliseconds to be chosen and opened. Where the library has not loaded nothing is known to be gone.
    private func removeGone(from library: any ItemLibrary) {
        guard let current = tabs, library.isLoaded else { return }
        let isListed = { (row: ItemIndexRow) in library.item(row.id).map { $0.state != .trashed } ?? false }
        guard current.all.contains(where: { !isListed($0) }) else { return }
        tabs = current.keeping(where: isListed)
    }
}
