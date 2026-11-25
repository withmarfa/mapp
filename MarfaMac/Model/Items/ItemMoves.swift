import Foundation

/// The commands that move a selection between the Library and the Feed, or in and out of the archive.
nonisolated enum ItemMove: Hashable, Sendable, CaseIterable {
    /// To the Library.
    case keep
    case moveToFeed
    case archive
    case unarchive
}

/// What a tier or state command did, for the toast that says so: how many items changed, the one item where only one
/// did, and what it left alone, which the library has already told (`ItemLibrary.tellSkipped`).
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

/// The question before Move to Feed of items older than the type's feed window, which the Feed would let go.
nonisolated struct FeedLimitQuestion: Equatable, Sendable {
    /// How many of the items are older than the window.
    let pastWindow: Int
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

    /// The command's name, which its undo step carries.
    var name: String {
        switch self {
        case .keep: String(localized: "Keep in Library")
        case .moveToFeed: String(localized: "Move to Feed")
        case .archive: String(localized: "Archive")
        case .unarchive: String(localized: "Unarchive")
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
    /// What the toast says for `outcome` of `move`, naming the one item it changed where there was one.
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
    /// and why the others do not move. An item already archived needs nothing, and one beneath that is archived or in
    /// Recently Deleted is left as it is. `beneath` holds none of `archiving`.
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
            roots.append(id)
            if item.state == .active { archiving.insert(id) }
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

    /// The question to ask before Move to Feed of `ids`. Nil for now: it waits for the type's feed window in the
    /// catalogue (withmarfa/marfa#3560, withmarfa/marfa-swift#559), which `GET /types` alone does not give the copy.
    func feedLimitQuestion(for ids: Set<ItemID>) -> FeedLimitQuestion? { nil }

    /// A collection, a view or the app's settings stays in the Library.
    private func canGoToFeed(_ item: Item) -> Bool {
        !catalogue.isCollection(item.type) && !item.type.isHidden
    }
}
