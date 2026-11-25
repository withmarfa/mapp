import Foundation

/// The commands that move a selection between the Library and the Feed, or in and out of the archive.
nonisolated enum ItemMove: Hashable, Sendable, CaseIterable {
    /// To the Library.
    case keep
    case moveToFeed
    case archive
    case unarchive
}

/// What a move command queued, and every item it or the engine skipped.
nonisolated struct CommandOutcome: Equatable, Sendable {
    var changed: Int
    var onlyItem: ItemID?
    var skips: BatchSkips

    static let nothing = CommandOutcome(changed: 0, onlyItem: nil, skips: BatchSkips())

    init(changed: Int, onlyItem: ItemID?, skips: BatchSkips) {
        self.changed = changed
        self.onlyItem = onlyItem
        self.skips = skips
    }

    init(_ changed: some Collection<ItemID>, skips: BatchSkips) {
        self.init(changed: changed.count, onlyItem: changed.count == 1 ? changed.first : nil, skips: skips)
    }
}

/// The question before Move to Feed or Unarchive of items older than the type's feed window, which the Feed would let go.
nonisolated struct FeedLimitQuestion: Equatable, Sendable {
    /// What the items past the window share, where they are of one type.
    struct Window: Equatable, Sendable {
        /// What the core calls a list of the type's items, such as `Messages`.
        let typePlural: String
        let days: Int
    }

    /// How many of the items are older than the window.
    let pastWindow: Int
    var window: Window?
}

extension ItemMove {
    /// What the toast says once `count` items moved. One item is named by `title` where it has one.
    func movedMessage(count: Int, title: String?) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if count == 1, let title, !title.isEmpty {
            return switch self {
            case .keep: String(localized: "Kept “\(title)” in the Library")
            case .moveToFeed: String(localized: "Moved “\(title)” to the Feed")
            case .archive: String(localized: "Archived “\(title)”")
            case .unarchive: String(localized: "Unarchived “\(title)”")
            }
        }
        return switch self {
        case .keep: AttributedString(localized: "^[Kept \(count) item](inflect: true) in the Library").text
        case .moveToFeed: AttributedString(localized: "^[Moved \(count) item](inflect: true) to the Feed").text
        case .archive: AttributedString(localized: "^[Archived \(count) item](inflect: true)").text
        case .unarchive: AttributedString(localized: "^[Unarchived \(count) item](inflect: true)").text
        }
    }

    /// The moves a menu lists out of those `selectionCommands` offered, in the menu's order: Keep, Move to Feed, then
    /// Archive, or Unarchive where nothing in the selection can be archived. A selection in both tiers lists both tier moves.
    static func inMenu(_ offered: Set<ItemMove>) -> [ItemMove] {
        var moves: [ItemMove] = [.keep, .moveToFeed].filter(offered.contains)
        if offered.contains(.archive) {
            moves.append(.archive)
        } else if offered.contains(.unarchive) {
            moves.append(.unarchive)
        }
        return moves
    }

    /// The command's name, which its undo step carries.
    var name: String {
        switch self {
        case .keep: String(localized: "Keep in Library")
        case .moveToFeed: String(localized: "Move to Feed")
        case .archive: String(localized: "Archive")
        case .unarchive: String(localized: "Unarchive")
        }
    }

    /// The command's symbol, which its menu items and its toast draw.
    var symbol: String {
        switch self {
        case .keep: "tray.and.arrow.down"
        case .moveToFeed: "water.waves"
        case .archive: "archivebox"
        case .unarchive: "arrow.uturn.backward"
        }
    }

    /// The title of the notice where the command changed nothing.
    var failing: String {
        switch self {
        case .keep: String(localized: "Can’t Keep in Library")
        case .moveToFeed: String(localized: "Can’t Move to Feed")
        case .archive: String(localized: "Can’t Archive")
        case .unarchive: String(localized: "Can’t Unarchive")
        }
    }
}

extension ItemLibrary {
    func setTier(_ ids: Set<ItemID>, to tier: Tier, undoManager: UndoManager?) {
        setTier(ids, to: tier, undoManager: undoManager, moved: nil)
    }

    func archive(_ ids: Set<ItemID>, beneath: Bool, undoManager: UndoManager?) {
        archive(ids, beneath: beneath, undoManager: undoManager, moved: nil)
    }

    func unarchive(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        unarchive(ids, undoManager: undoManager, moved: nil)
    }

    /// Formats the move, using the item's name where it moved one item.
    func movedMessage(_ move: ItemMove, _ outcome: CommandOutcome) -> String {
        move.movedMessage(count: outcome.changed, title: outcome.onlyItem.flatMap(item)?.name)
    }

    /// The items among `ids` that move to `tier`, and why the others do not. An item already there needs nothing.
    /// A collection, a view or the app's settings stays in the Library.
    func tierPlan(_ ids: Set<ItemID>, to tier: Tier) -> (changing: Set<ItemID>, skips: BatchSkips) {
        var changing = Set<ItemID>()
        var skips = BatchSkips()
        for id in ids {
            guard let item = item(id) else {
                skips.skip(.gone)
                continue
            }
            guard item.tier != tier else { continue }
            if let reason = item.obstacle(to: .tier) {
                skips.skip(reason)
            } else if tier == .feed, !canGoToFeed(item) {
                skips.skip(.staysInLibrary)
            } else {
                changing.insert(id)
            }
        }
        return (changing, skips)
    }

    /// The items among `ids` that Archive moves, every active item beneath them through `parent-of` at any depth,
    /// and why the others do not move. An item already archived needs nothing and adds nothing beneath it, and one
    /// beneath that is archived or in Recently Deleted is left as it is. `beneath` holds none of `archiving`.
    func archivePlan(_ ids: Set<ItemID>) -> (archiving: Set<ItemID>, beneath: Set<ItemID>, skips: BatchSkips) {
        var archiving = Set<ItemID>()
        var skips = BatchSkips()
        var roots: [ItemID] = []
        for id in ids {
            guard let item = item(id) else {
                skips.skip(.gone)
                continue
            }
            if let reason = item.obstacle(to: .state) {
                skips.skip(reason)
                continue
            }
            if item.state == .active {
                archiving.insert(id)
                roots.append(id)
            }
        }
        var beneath = Set<ItemID>()
        var seen = Set(roots)
        var next = roots
        while let id = next.popLast() {
            for child in childIDs(of: id) where seen.insert(child).inserted {
                next.append(child)
                if !ids.contains(child), item(child)?.state == .active { beneath.insert(child) }
            }
        }
        return (archiving, beneath, skips)
    }

    /// The items among `ids` that Unarchive moves, and why the others do not. An active item needs nothing.
    func unarchivePlan(_ ids: Set<ItemID>) -> (changing: Set<ItemID>, skips: BatchSkips) {
        var changing = Set<ItemID>()
        var skips = BatchSkips()
        for id in ids {
            guard let item = item(id) else {
                skips.skip(.gone)
                continue
            }
            if let reason = item.obstacle(to: .state) {
                skips.skip(reason)
            } else if item.state == .archived {
                changing.insert(id)
            }
        }
        return (changing, skips)
    }

    /// The moves the selection offers: each one that would change at least one of its items. A selection of items
    /// in both tiers offers Keep and Move to Feed.
    func selectionCommands(_ ids: Set<ItemID>) -> Set<ItemMove> {
        var offered = Set<ItemMove>()
        for id in ids {
            guard let item = item(id) else { continue }
            if item.allows(.tier) {
                if item.tier == .feed { offered.insert(.keep) } else if canGoToFeed(item) { offered.insert(.moveToFeed) }
            }
            if item.allows(.state) { offered.insert(item.state == .archived ? .unarchive : .archive) }
            if offered.count == ItemMove.allCases.count { break }
        }
        return offered
    }

    /// Asks only where the move would leave an item in the bin within the hour, the `feed-expiry` job running hourly:
    /// an active item that Move to Feed moves, or an archived item in the Feed that Unarchive makes active, past its
    /// type's window (`Catalogue.feedExpiry`). Nothing is asked of a type the catalogue does not hold or that keeps its
    /// feed items, nor of an archived item Move to Feed moves, which the job leaves.
    func feedLimitQuestion(_ move: ItemMove, for ids: Set<ItemID>) -> FeedLimitQuestion? {
        feedLimitQuestion(move, for: ids, now: .now)
    }

    func feedLimitQuestion(_ move: ItemMove, for ids: Set<ItemID>, now: Date) -> FeedLimitQuestion? {
        let moving: [Item]
        switch move {
        case .moveToFeed: moving = tierPlan(ids, to: .feed).changing.compactMap(item).filter { $0.state == .active }
        case .unarchive: moving = unarchivePlan(ids).changing.compactMap(item).filter { $0.tier == .feed }
        case .keep, .archive: return nil
        }
        let past = moving.filter { item in catalogue.feedExpiry(of: item).map { now > $0 } == true }
        guard let first = past.first else { return nil }
        let days = catalogue.itemTypes[first.type]?.feedDays
        let window = days.flatMap { days in
            past.allSatisfy { $0.type == first.type }
                ? FeedLimitQuestion.Window(typePlural: catalogue.plural(for: first.type), days: days) : nil
        }
        return FeedLimitQuestion(pastWindow: past.count, window: window)
    }

    /// A collection, a view or the app's settings stays in the Library.
    private func canGoToFeed(_ item: Item) -> Bool {
        !catalogue.isCollection(item.type) && !item.type.isHidden
    }
}

nonisolated extension Catalogue {
    /// When the type's feed window ends for `item`: its creation plus the type's days of 24 hours, as Marfa's `feed-expiry`
    /// job counts them. Once it has passed, the job moves the item to the bin if it is active in the Feed and nothing it
    /// would take with it is still held. Nil where the type keeps its feed items, the catalogue does not hold the type, or
    /// the item's creation is unknown (`MarfaMapping.timestamp` gives the oldest moment, which is no age).
    func feedExpiry(of item: Item) -> Date? {
        guard let days = itemTypes[item.type]?.feedDays, days > 0, item.created > .distantPast else { return nil }
        return item.created.addingTimeInterval(Double(days) * 86_400)
    }

    /// The day Info says `item` leaves the Feed: an active Feed item whose window has not yet ended. A date already past
    /// says nothing, since the job may be behind or off, or the item may have been restored from the bin, which keeps it.
    func leavesTheFeed(_ item: Item, now: Date = .now) -> Date? {
        guard item.tier == .feed, item.state == .active, let expiry = feedExpiry(of: item), expiry > now else { return nil }
        return expiry
    }
}
