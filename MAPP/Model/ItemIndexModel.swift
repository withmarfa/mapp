import Foundation
import Observation

/// The Items index's rows under each tab, in the order of the person's sort, kept by the window so that leaving the page
/// for an item's full page and coming back finds them as they were.
///
/// A library of tens of thousands of items must not be read, ordered and split by tier on the main thread each time
/// the person changes tab or types in another window. The rows are worked out once for the items and the sort, off the
/// main thread when there are many, and a change of tab only reads one of the arrays. A run of edits to a large library
/// is let settle before the rows are worked out again.
@MainActor
@Observable
final class ItemIndexModel {
    /// Up to this many items the rows are worked out in place, so a small library never shows the page empty first.
    nonisolated static let inlineLimit = 2_000
    /// How long a run of changes to a large library is let settle.
    nonisolated static let settling = Duration.milliseconds(300)

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

    /// Starts following `library`, ordering by `sort`. Following the library already followed only changes the order.
    func follow(_ library: any ItemLibrary, sort: IndexSort) {
        if let followed = self.library, followed === library {
            guard sort != self.sort else { return }
            self.sort = sort
            read(generation: generation)
            return
        }
        generation += 1
        stamp += 1
        settle?.cancel()
        self.library = library
        self.sort = sort
        tabs = nil
        read(generation: generation)
    }

    /// Stops following the library, which the window's other pages need no rows of.
    func stop() {
        generation += 1
        stamp += 1
        settle?.cancel()
        library = nil
    }

    /// Forgets everything, for a window that changes library.
    func reset() {
        stop()
        tabs = nil
    }

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
        guard itemCount > Self.inlineLimit else { return read(generation: generation) }
        settle = Task { [weak self] in
            try? await Task.sleep(for: Self.settling)
            guard !Task.isCancelled else { return }
            self?.read(generation: generation)
        }
    }

    private func show(_ arranged: ItemIndexTabs, generation: Int, stamp: Int) {
        guard generation == self.generation, stamp == self.stamp else { return }
        tabs = arranged
    }
}
