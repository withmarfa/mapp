import Foundation

/// When the column beside a layout follows the selection as it moves quickly down it. The column follows the selection
/// once the selection has rested, so passing over rows loads no page for them, and the text of the item on the page is
/// handed over the moment the selection leaves it. The column shows the item the editor holds
/// (`EditorController.heldItemID`), never one of its own, so it changes item only once the page holds the new one.
@MainActor
final class BesideSettler {
    /// How long the selection rests before the column follows it.
    let rest: Duration
    private var following: Task<Void, Never>?
    /// Each choice in turn, so a hand-over answering for one the selection has left behind stops nothing.
    private var choice = 0
    /// Whether the column shows nothing of its own choosing yet, as before the first item or after the selection
    /// emptied, so the next item is followed at once.
    private var isAway = true

    init(rest: Duration = .milliseconds(150)) { self.rest = rest }

    /// The selection is now `id`, or nothing (or several items), which takes the page away; `held` is the item the
    /// editor holds. `handOver` asks the page for the text it has not reported yet and answers whether it is in; `open`
    /// puts an item on the page once that is in. A hand-over that fails keeps the column where it is: the person has
    /// been told, and choosing again goes ahead.
    func choose(
        _ id: ItemID?, held: ItemID?, handOver: (@escaping (Bool) -> Void) -> Void, open: @escaping (ItemID) -> Void
    ) {
        following?.cancel()
        following = nil
        choice += 1
        let choice = choice
        guard let id else {
            handOver { _ in }
            isAway = true
            return
        }
        let wasAway = isAway
        isAway = false
        // The first item, and a return to the one held, which the page may have been leaving, need no rest.
        guard !wasAway, let held, held != id else { return open(id) }
        following = Task { [rest] in
            try? await Task.sleep(for: rest)
            guard !Task.isCancelled else { return }
            open(id)
        }
        // After the follow is set, since a hand-over can answer at once.
        handOver { [weak self] kept in
            guard !kept, let self, self.choice == choice else { return }
            following?.cancel()
            following = nil
        }
    }
}
