import Foundation

/// The items a command on a selection left alone, counted by why, so the person is told how many and why and no
/// item is passed over without a word. An item already as the command would leave it is not skipped: there was
/// nothing to do for it.
nonisolated struct BatchSkips: Equatable, Sendable {
    /// Why an item took no part. The words say what the person can do about it, or that nothing can be.
    enum Reason: CaseIterable, Sendable {
        /// Another device removed it for good, or the selection named an item the library no longer holds.
        case gone
        case inBin
        /// Archived, with a problem the library found in it, or its text not yet read.
        case cantChange
        /// A file, which keeps its type.
        case file
        case cantBecomeType
        case cantJoinCollection
        case fullOfTags
        case cantMoveToLane
    }

    private(set) var counts: [Reason: Int] = [:]

    var isEmpty: Bool { counts.isEmpty }
    var total: Int { counts.values.reduce(0, +) }

    mutating func skip(_ reason: Reason) {
        counts[reason, default: 0] += 1
    }

    /// One sentence for each reason, in a steady order, or nil where nothing was skipped.
    var message: String? {
        let sentences = Reason.allCases.compactMap { reason in counts[reason].map { Self.sentence(reason, count: $0) } }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    static func sentence(_ reason: Reason, count: Int) -> String {
        switch reason {
        case .gone: String(localized: "\(count) items are no longer in the library.")
        case .inBin: String(localized: "\(count) items are in Recently Deleted.")
        case .cantChange: String(localized: "\(count) items can’t be changed right now.")
        case .file: String(localized: "\(count) items are files, which keep their type.")
        case .cantBecomeType: String(localized: "\(count) items can’t become this type.")
        case .cantJoinCollection: String(localized: "\(count) items can’t be filed in a collection.")
        case .fullOfTags: String(localized: "\(count) items already have the most tags an item can have.")
        case .cantMoveToLane: String(localized: "\(count) items can’t go in this lane.")
        }
    }
}

nonisolated extension Item {
    /// Why a command that only sets a tag leaves the item alone: it is in Recently Deleted or archived.
    var stateObstacle: BatchSkips.Reason? {
        switch state {
        case .active: nil
        case .archived: .cantChange
        case .trashed: .inBin
        }
    }

    /// Why a command that writes the item's tags, properties or links leaves it alone.
    var writeObstacle: BatchSkips.Reason? {
        stateObstacle ?? (problem == nil ? nil : .cantChange)
    }
}

extension ItemLibrary {
    /// Tells the person what a command left alone, in one notice. Where it changed nothing at all the notice carries
    /// the command's own title, as any other refusal does; otherwise it says some items were skipped.
    func tellSkipped(_ skips: BatchSkips, didChange: Bool, failing title: String) {
        guard let message = skips.message else { return }
        notices.tell(didChange ? String(localized: "Some Items Were Skipped") : title, message)
    }

    /// The items among `ids` that take Favorite or Unfavorite, and why the others do not. An item in the bin keeps
    /// its tags, so it is left as it is.
    func favoritePlan(_ ids: Set<ItemID>, _ isFavorite: Bool) -> (changing: Set<ItemID>, skips: BatchSkips) {
        var skips = BatchSkips()
        var changing: Set<ItemID> = []
        for id in ids {
            guard let item = item(id) else {
                skips.skip(.gone)
                continue
            }
            if let reason = item.stateObstacle {
                skips.skip(reason)
            } else if item.isFavorite != isFavorite {
                changing.insert(id)
            }
        }
        return (changing, skips)
    }

    /// The items among `ids` to file in `collection`, less those already in it, and why the others can't be: an
    /// item in the bin, one with a problem, or one of a type a collection can't hold, a collection among them.
    func collectionPlan(_ ids: Set<ItemID>, joining collection: ItemID?) -> (joining: [Item], skips: BatchSkips) {
        var skips = BatchSkips()
        var joining: [Item] = []
        for id in ids {
            guard let item = item(id) else {
                skips.skip(.gone)
                continue
            }
            if let collection, item.collectionIDs.contains(collection) { continue }
            if let reason = item.writeObstacle {
                skips.skip(reason)
            } else if !catalogue.canJoinCollection(item.type) {
                skips.skip(.cantJoinCollection)
            } else {
                joining.append(item)
            }
        }
        return (joining, skips)
    }
}
