import Foundation
import Observation

/// The versions the panel's History lists, kept beyond the life of the view that asked, so leaving Info or choosing another
/// item and coming back reads nothing again. One read for each version of an item; an edit is a new version and starts a
/// new read. The newest few are kept. A read that failed is made again when Info shows. An item at version 1 has no earlier
/// version to ask for.
@MainActor @Observable
final class PanelHistory {
    /// Most earlier versions drawn before Show All.
    static let shown = 10
    /// How many items' reads are kept.
    static let capacity = 8

    static let shared = PanelHistory()

    private struct Key: Hashable {
        let library: ObjectIdentifier
        let item: ItemID
        let version: ItemVersion
    }

    private var reads: [Key: ItemHistoryModel] = [:]
    @ObservationIgnored private var order: [Key] = []

    /// The read for `item` at `version` in the library, once asked for.
    func model(of item: ItemID, version: ItemVersion, in library: any ItemLibrary) -> ItemHistoryModel? {
        reads[Key(library: ObjectIdentifier(library), item: item, version: version)]
    }

    /// Reads the versions of `item` at `version` unless they are already read, or on their way.
    func ask(_ item: ItemID, version: ItemVersion, in library: any ItemLibrary) {
        guard version.rawValue > 1 else { return }
        let key = Key(library: ObjectIdentifier(library), item: item, version: version)
        if let held = reads[key] {
            if case .failed = held.phase { held.load() }
            return
        }
        let model = ItemHistoryModel(id: item, source: library.history)
        reads[key] = model
        order.append(key)
        while order.count > Self.capacity { reads.removeValue(forKey: order.removeFirst())?.cancel() }
        model.load()
    }

    /// The symbol that stands for who wrote a version, by the kind of sign-in. The name beside it says which.
    static func symbol(of writer: ItemSnapshot.Writer?) -> String {
        switch writer?.kind {
        case .browser?: "globe"
        case .app?: "laptopcomputer"
        case .key?: "key"
        case .local?: "internaldrive"
        case nil: "questionmark.circle"
        }
    }
}
