import AppKit

/// Which separators in a menu have nothing to separate.
///
/// A `Divider` in a SwiftUI command group is always drawn, even when the views around it render nothing, and the
/// system adds separators of its own around its toolbar and tab groups. Neither knows about the other, so a menu
/// can open with two separators in a row, or with one at an end. Only the finished menu can say.
enum MenuSeparators {
    struct Entry: Equatable {
        var isSeparator: Bool
        /// Hidden by something other than this tidy.
        var isHidden = false
    }

    /// The indexes of the separators to hide: any with no item before it, any right after a separator that stays, and any
    /// with no item after it. Hidden entries count for nothing.
    static func redundant(in entries: [Entry]) -> Set<Int> {
        var hidden = Set<Int>()
        var kept: Int?
        var itemSinceSeparator = false
        for (index, entry) in entries.enumerated() where !entry.isHidden {
            if !entry.isSeparator {
                itemSinceSeparator = true
                kept = nil
            } else if itemSinceSeparator {
                kept = index
                itemSinceSeparator = false
            } else {
                hidden.insert(index)
            }
        }
        if let kept { hidden.insert(kept) }
        return hidden
    }
}

/// Hides the redundant separators of the menu bar's menus as one opens.
@MainActor
final class MenuSeparatorTidy {
    private let hiddenByTidy = NSHashTable<NSMenuItem>.weakObjects()
    private var observer: (any NSObjectProtocol)?

    func start() {
        guard observer == nil else { return }
        // The whole menu bar is tidied, not the menu named, since a notification cannot hand its menu to the main actor.
        observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let bar = NSApp.mainMenu { self?.tidy(bar) }
            }
        }
    }

    /// A separator this tidy hid comes back when the items around it change enough to need it.
    func tidy(_ menu: NSMenu) {
        let items = menu.items
        let entries = items.map { item in
            MenuSeparators.Entry(isSeparator: item.isSeparatorItem, isHidden: item.isHidden && !hiddenByTidy.contains(item))
        }
        let redundant = MenuSeparators.redundant(in: entries)
        for (index, item) in items.enumerated() where item.isSeparatorItem {
            if redundant.contains(index) {
                item.isHidden = true
                hiddenByTidy.add(item)
            } else if hiddenByTidy.contains(item) {
                item.isHidden = false
                hiddenByTidy.remove(item)
            }
        }
        for item in items {
            if let submenu = item.submenu { tidy(submenu) }
        }
    }
}
