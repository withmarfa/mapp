import Foundation

/// Counts the items a command skipped by reason for a single notice.
nonisolated struct BatchSkips: Equatable, Sendable {
    /// Why an item took no part. The words say what the person can do about it, or that nothing can be.
    enum Reason: CaseIterable, Sendable {
        /// Another device removed it for good, or the selection named an item the library no longer holds.
        case gone
        case inBin
        /// With a problem the library found in it, such as values or text it could not read.
        case cantChange
        case typeWriteDenied
        /// Held read only: a person's connector keeps it and would put back a change made here.
        case readOnly
        /// A file, which keeps its type.
        case file
        case cantBecomeType
        /// A collection, which collections are flat and can't join.
        case isCollection
        case cantJoinCollection
        /// A collection, a view or the app's settings, which stays in the Library.
        case staysInLibrary
        case fullOfTags
        case cantMoveToLane
        /// Its type requires the field a Not Set lane would clear.
        case needsValue
        /// A file, which has no lane to move to.
        case fileHasNoLane
        /// Marfa sets this field on the file.
        case fileFact
        /// Selected, but not on the board now, as when a search or filter has hidden it since.
        case notShown
        /// No longer as this Mac left it, so an Undo or Redo would overwrite a change made since.
        case changedSince
    }

    private(set) var counts: [Reason: Int] = [:]

    var isEmpty: Bool { counts.isEmpty }
    var total: Int { counts.values.reduce(0, +) }

    mutating func skip(_ reason: Reason) {
        counts[reason, default: 0] += 1
    }

    mutating func add(_ other: BatchSkips) {
        counts.merge(other.counts, uniquingKeysWith: +)
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
        case .typeWriteDenied: AttributedString(localized: "The app doesn’t have write access to ^[\(count) item](inflect: true).").text
        case .readOnly: String(localized: "\(count) items are managed by a connector, so changes made here would be overwritten.")
        case .file: String(localized: "\(count) items are files, which keep their type.")
        case .cantBecomeType: String(localized: "\(count) items can’t become this type.")
        case .isCollection: String(localized: "\(count) items are collections, which can’t be in another collection.")
        case .cantJoinCollection: String(localized: "\(count) items can’t be filed in a collection.")
        case .staysInLibrary: String(localized: "\(count) items must stay in the Library.")
        case .fullOfTags: String(localized: "\(count) items already have the most tags an item can have.")
        case .cantMoveToLane: String(localized: "\(count) items can’t go in this lane.")
        case .needsValue: String(localized: "\(count) items need a value there, so it can’t be cleared.")
        case .fileHasNoLane: String(localized: "\(count) items are files, which can’t be moved between lanes.")
        case .fileFact: String(localized: "\(count) files were skipped because Marfa sets this property.")
        case .notShown: String(localized: "\(count) items aren’t on this board.")
        case .changedSince: String(localized: "\(count) items have changed since, so they were left as they are.")
        }
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
            if let reason = item.obstacle(to: .favorite) {
                skips.skip(reason)
            } else if item.isFavorite != isFavorite {
                changing.insert(id)
            }
        }
        return (changing, skips)
    }

    /// A connector's item can move because the next sync keeps it in Recently Deleted (`items/natural-key-trashed`).
    func deletePlan(_ ids: Set<ItemID>) -> (moving: Set<ItemID>, skips: BatchSkips) {
        var skips = BatchSkips()
        var moving: Set<ItemID> = []
        for id in ids {
            guard let item = item(id) else {
                skips.skip(.gone)
                continue
            }
            if item.state == .trashed {
                skips.skip(.inBin)
            } else if let reason = item.obstacle(to: .delete) {
                skips.skip(reason)
            } else {
                moving.insert(id)
            }
        }
        return (moving, skips)
    }

    /// The items among `ids` to file in `collection`, less those already in it, and why the others can't be: an
    /// item in the bin, or one of a type a collection can't hold, a collection among them.
    func collectionPlan(_ ids: Set<ItemID>, joining collection: ItemID?) -> (joining: [Item], skips: BatchSkips) {
        var skips = BatchSkips()
        var joining: [Item] = []
        for id in ids {
            guard let item = item(id) else {
                skips.skip(.gone)
                continue
            }
            if let collection, item.collectionIDs.contains(collection) { continue }
            if let reason = item.obstacle(to: .collections) {
                skips.skip(reason)
            } else if catalogue.isCollection(item.type) {
                skips.skip(.isCollection)
            } else if !catalogue.canJoinCollection(item.type) {
                skips.skip(.cantJoinCollection)
            } else {
                joining.append(item)
            }
        }
        return (joining, skips)
    }
}
