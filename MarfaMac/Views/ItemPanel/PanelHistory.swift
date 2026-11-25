import Foundation
import Observation

/// The versions the panel's History lists. They are asked for only while Info shows, once for each version of an item,
/// so another selection or an edit starts a new read and a return to Info reads nothing again. An item at version 1 has
/// no earlier version to ask for.
@MainActor @Observable
final class PanelHistory {
    /// Most earlier versions drawn before Show All.
    static let shown = 10

    private struct Key: Equatable {
        let item: ItemID
        let version: ItemVersion
    }

    private(set) var model: ItemHistoryModel?
    @ObservationIgnored private var key: Key?

    /// Reads the versions of `item` at `version` unless they are already read or on their way.
    func ask(_ item: ItemID, version: ItemVersion, in library: any ItemLibrary) {
        let wanted = Key(item: item, version: version)
        guard key != wanted else { return }
        stop()
        key = wanted
        guard version.rawValue > 1 else { return }
        let model = ItemHistoryModel(id: item, source: library.history)
        self.model = model
        model.load()
    }

    func stop() {
        model?.cancel()
        model = nil
        key = nil
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
