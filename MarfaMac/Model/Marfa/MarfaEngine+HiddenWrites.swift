import Foundation
import Marfa

/// The writes the app makes to its own settings (`PreferencesSync`) share the copy's queue with the person's writes to the
/// library. They are no change the person made to an item, so they are kept out of what waits for the person, the
/// problems and the text shown before a copy is left. They still count as writes not sent, so leaving a copy covers them.
extension MarfaEngine {
    /// `writes` without those to a hidden item (`TypeID.isHidden`). The app writes rows only to its own settings.
    func libraryWrites(_ writes: [Marfa.QueuedWrite]) async -> [Marfa.QueuedWrite] {
        let unknown = Set(writes.compactMap(\.itemId)).filter { rows[$0] == nil && hiddenItems[$0] == nil }
        if !unknown.isEmpty, let found = try? await Self.asking({ try await copy.items.get(Array(unknown), includingBin: true) }) {
            for row in found.rows { hiddenItems[row.id] = TypeID.isHidden(row.type) }
        }
        return writes.filter { write in
            if [.writeRows, .undoRows].contains(write.kind) { return false }
            if let type = write.body["type"]?.string, TypeID.isHidden(type) { return false }
            return !(write.itemId.flatMap { hiddenItems[$0] } ?? false)
        }
    }
}
