import Foundation
import os
import Synchronization

/// The work that runs when a person moves around the window: each is a signpost interval, so Instruments shows
/// it under the app's `navigation` category (`Telemetry`), and a debug build also tallies how often it ran and for
/// how long, which `NavigationCostTests` reads.
nonisolated enum Cost: String, CaseIterable, Sendable {
    /// `Browser.items(in:)`, the place's items or the search's.
    case items
    case sections
    case viewModes
    /// One `ItemTableContent` made, whatever it was asked for afterwards.
    case tableContent
    case tableRows
    case tableGroups
    /// One run of the gallery's own body, timed over its listing of every item the place holds.
    case galleryBody
    /// What one gallery card derives from its item, the catalogue and the files it embeds (`GalleryCardFacts`).
    case galleryCard
    /// One placing of the soft selection's marks on a list or table.
    case softSelection
    case boardFields
    case timelineFields
    /// One build of the item page's header, from the library and the window's drafts.
    case pageHeader
    /// One `ItemLibrary.relationships(for:)` read.
    case relationships
    /// One `LinkedItem.list`, found and sorted.
    case linkedItems
    /// Drawing the symbols and type icons the page's header uses, as pictures.
    case headerIcons
    /// Drawing one symbol or type icon as a picture.
    case iconDraw
    /// One `SidebarPlan` made: the type tree, with its counts, ordered and laid out.
    case sidebarPlan
    /// One pass over the catalogue for the types that hold items (`itemTypeCounts`).
    case typeCounts
    /// The command palette's places and items, listed and sorted (`Browser.paletteIndex`).
    case paletteIndex
    /// One run of the body of `Sidebar` or of its Types section.
    case sidebarBody

    private static let signposter = Telemetry.signposter(.navigation)

    @discardableResult
    static func measure<Result>(_ cost: Cost, _ work: () -> Result) -> Result {
        let state = signposter.beginInterval("work", id: signposter.makeSignpostID(), "\(cost.rawValue, privacy: .public)")
        #if DEBUG
        let start = ContinuousClock.now
        defer {
            let elapsed = ContinuousClock.now - start
            tally.withLock { $0[cost, default: Tally()].add(elapsed) }
            signposter.endInterval("work", state)
        }
        #else
        defer { signposter.endInterval("work", state) }
        #endif
        return work()
    }

    /// For work that cannot be wrapped in a closure, such as an initializer.
    static func record(_ cost: Cost, since start: ContinuousClock.Instant) {
        #if DEBUG
        let elapsed = ContinuousClock.now - start
        tally.withLock { $0[cost, default: Tally()].add(elapsed) }
        #endif
    }

    /// How often a cost ran, and for how long in all, each counted inside the others that ran it.
    struct Tally: Sendable {
        private(set) var count = 0
        private(set) var total = Duration.zero

        fileprivate mutating func add(_ elapsed: Duration) {
            count += 1
            total += elapsed
        }

        var milliseconds: Double {
            Double(total.components.seconds) * 1000 + Double(total.components.attoseconds) / 1e15
        }
    }

    #if DEBUG
    private static let tally = Mutex<[Cost: Tally]>([:])

    static var tallies: [Cost: Tally] { tally.withLock { $0 } }

    static func resetTallies() { tally.withLock { $0 = [:] } }
    #endif
}
