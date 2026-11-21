import Foundation

/// The kind a new item takes outside a type's own list, as Settings > General > New Items says: one the person chose, or
/// the kind last used. A Mac setting, one value in the defaults (`key`), never written to Marfa.
nonisolated enum NewItemType {
    static let key = "newItemType"

    /// The chosen kind's identifier, or nil where the last used one is wanted. A kind the server no longer offers is
    /// passed over by `QuickAdd.startingType`.
    static func stored(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
    }
}
