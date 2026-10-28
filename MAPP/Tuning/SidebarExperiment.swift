#if DEBUG
import Foundation

/// The sidebar design experiment's switch: the sidebar and landing page as they are, or the Claude-app-style mock.
/// Delete this file, its knob in `Tuning.shared`, and every `#if DEBUG` branch that reads it once August has chosen,
/// or promote the experiment into the real sidebar.
enum SidebarStyle: String, CaseIterable {
    case current
    case experiment

    static let knob = Knob.picker("sidebar", "style", SidebarStyle.current)

    /// The style the tuning panel has set, read in a view's `body` so the view follows a change at once.
    static var selected: SidebarStyle {
        Tuning.shared.choice(knob, as: SidebarStyle.self) ?? .current
    }
}

/// The places above the experiment sidebar's More row, kept as a comma-separated list of keys. The mock keeps it in
/// this Mac's defaults, not per server, and leaves the real sidebar's layout alone.
struct ExperimentMainBlock: Equatable {
    static let storageKey = "experiment.sidebar.mainBlock"
    static let defaultStored = "all,sources,collections"

    /// Places that are not types, by key, in the order the Edit list offers them.
    static let placeKeys = ["all", "sources", "collections", "inbox", "recents", "favorites", "deleted"]
    static let typePrefix = "type:"

    private(set) var keys: [String]

    init(stored: String) {
        var seen: Set<String> = []
        keys = stored.split(separator: ",").map { String($0) }.filter { seen.insert($0).inserted }
    }

    var stored: String { keys.joined(separator: ",") }

    func contains(_ key: String) -> Bool { keys.contains(key) }

    /// Adds a place at the end of the block, or takes it out.
    mutating func toggle(_ key: String) {
        if let index = keys.firstIndex(of: key) { keys.remove(at: index) } else { keys.append(key) }
    }

    static func typeKey(_ id: String) -> String { typePrefix + id }

    /// The sidebar item a key opens; nil for a key this build does not know.
    static func item(forKey key: String) -> SidebarItem? {
        switch key {
        case "all": .allNotes
        case "sources": .sources
        case "collections": .collections
        case "inbox": .inbox
        case "recents": .recents
        case "favorites": .favorites
        case "deleted": .recentlyDeleted
        default: key.hasPrefix(typePrefix) ? .itemType(String(key.dropFirst(typePrefix.count))) : nil
        }
    }
}

/// Which types the landing page offers as chips, and which wait under its More chip.
enum ExperimentChips {
    static let shownCount = 4

    /// The types people hold most items of come first, then the rest in the order given. A type with no items still
    /// fills the row, so a new library has chips too.
    static func split(_ options: [ItemTypeOption], usedMost: [TypeID], limit: Int = shownCount) -> (shown: [ItemTypeOption], more: [ItemTypeOption]) {
        var ordered = usedMost.compactMap { id in options.first { $0.id == id } }
        ordered += options.filter { option in !ordered.contains(option) }
        let shown = Array(ordered.prefix(limit))
        return (shown, Array(ordered.dropFirst(limit)))
    }
}
#endif
