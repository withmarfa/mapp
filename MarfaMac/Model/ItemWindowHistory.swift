import Foundation
import Observation

/// The items an item's window showed before the one it shows, which Back and Forward walk. Only a link followed in the
/// window adds to it; the window's own history is not the main window's (`SelectionHistory`), and is not kept for
/// the next launch. It changes only once the window shows the item it went to (`ItemWindow.go`), so a hand-over that
/// fails leaves it as it was.
@MainActor @Observable
final class ItemWindowHistory {
    enum Step { case back, forward }

    private(set) var back: [ItemID] = []
    private(set) var forward: [ItemID] = []

    /// A link in the window's page showed `next` where `current` was. What lay ahead is gone, as in any history.
    func followed(from current: ItemID, to next: ItemID) {
        guard current != next else { return }
        back.append(current)
        forward = []
    }

    /// The item a step goes to, passing over any that has gone. Nil when there is none.
    func target(_ step: Step, isAvailable: (ItemID) -> Bool) -> ItemID? {
        (step == .back ? back : forward).last(where: isAvailable)
    }

    /// The window went a step from `current` to `target`, which `target(_:isAvailable:)` gave: it and those passed over
    /// leave that side, and `current` goes to the other.
    func went(_ step: Step, from current: ItemID, to target: ItemID) {
        let side = step == .back ? back : forward
        guard let index = side.lastIndex(of: target) else { return }
        if step == .back {
            back.removeSubrange(index...)
            forward.append(current)
        } else {
            forward.removeSubrange(index...)
            back.append(current)
        }
    }

    func canGoBack(isAvailable: (ItemID) -> Bool) -> Bool { back.contains(where: isAvailable) }
    func canGoForward(isAvailable: (ItemID) -> Bool) -> Bool { forward.contains(where: isAvailable) }
}
