import Foundation

/// Where an item opens when a person presses Return on it, double-clicks it or chooses Open, as Settings > Lists >
/// Open Items In says. A Mac setting, one value in the defaults (`ListKey.openItemsIn`), never written to Marfa.
nonisolated enum ItemOpening: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// A large page over the window, which dims what is behind it.
    case modal
    /// The item's page in place of the layout, with a Back button.
    case fullPage
    /// A window of its own.
    case newWindow

    static let standard = ItemOpening.modal

    var id: Self { self }

    /// The value Settings names.
    var title: String {
        switch self {
        case .modal: String(localized: "Over the List")
        case .fullPage: String(localized: "Full Page")
        case .newWindow: String(localized: "New Window")
        }
    }

    /// The command that opens an item this way, as a menu or the palette names it.
    var commandTitle: LocalizedStringResource {
        switch self {
        case .modal: "Open as Modal"
        case .fullPage: "Open as Full Page"
        case .newWindow: "Open in New Window"
        }
    }

    var symbol: String {
        switch self {
        case .modal: "rectangle.center.inset.filled"
        case .fullPage: "arrow.up.left.and.arrow.down.right"
        case .newWindow: "macwindow"
        }
    }

    /// The two ways Open does not do, in the order Settings lists them.
    var others: [ItemOpening] { Self.allCases.filter { $0 != self } }

    /// Whether `count` items can be opened this way: a modal and a full page show one item, and windows take as
    /// many as are chosen.
    func canOpen(_ count: Int) -> Bool {
        self == .newWindow ? count >= 1 : count == 1
    }

    /// What Settings holds, or the standard where nothing is stored or what is stored is not a way this version has.
    static func stored(in defaults: UserDefaults = .standard) -> ItemOpening {
        defaults.string(forKey: ListKey.openItemsIn).flatMap(ItemOpening.init(rawValue:)) ?? .standard
    }
}

/// The items before and after one in a list, which the modal's up and down arrows move to. Neither is given for an
/// item the list does not hold, as one that left it while the modal was open.
nonisolated struct ListNeighbors: Equatable, Sendable {
    let previous: ItemID?
    let next: ItemID?

    init(of id: ItemID, in order: [ItemID]) {
        guard let index = order.firstIndex(of: id) else {
            previous = nil
            next = nil
            return
        }
        previous = index > order.startIndex ? order[index - 1] : nil
        next = index + 1 < order.endIndex ? order[index + 1] : nil
    }
}

/// What a row's context menu holds, in order. Every layout and the list build the same menu from this, so the order
/// is decided once. Some entries are left out for a selection they do not suit; `ItemRowMenu` does that.
nonisolated enum RowMenuEntry: Equatable, Sendable {
    /// Open, as Settings says.
    case open
    /// One of the other ways to open.
    case openAs(ItemOpening)
    case quickLook, share
    case favorite, tag, collection
    /// What the layout adds, such as a board's Move To.
    case layoutActions
    case changeType, customizeLayout, versionHistory
    /// Recover, for items that are in Recently Deleted.
    case recover
    /// Delete, or Delete Immediately for items in Recently Deleted.
    case delete
    case divider

    /// The menu for items that are in use, or, for items all in Recently Deleted, the menu of the bin.
    static func entries(opening: ItemOpening, inBin: Bool) -> [RowMenuEntry] {
        let open: [RowMenuEntry] = [.open] + opening.others.map(RowMenuEntry.openAs)
        if inBin { return open + [.divider, .quickLook, .share, .divider, .recover, .versionHistory, .divider, .delete] }
        return open + [
            .divider, .quickLook, .share,
            .divider, .favorite, .tag, .collection, .layoutActions, .changeType, .customizeLayout, .versionHistory,
            .divider, .delete,
        ]
    }
}
