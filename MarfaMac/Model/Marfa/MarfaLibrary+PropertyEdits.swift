import Foundation

/// An undo of a property edit puts back the item as the person wrote it: the copy, with this Mac's earlier edits
/// still on their way laid over it in the order they were made. The copy does not show an edit until it takes it, so
/// an undo read from the copy alone would skip an edit the person saw made.
extension MarfaLibrary {
    /// One property edit this Mac made, from when it is made until the source answers it.
    final class PropertyEdit {
        enum State {
            case onItsWay
            case made
            /// Refused, so the person was told it was not saved.
            case notMade
        }

        let item: ItemID
        /// Its place among this Mac's property edits (`lastPropertyWrite`), which is the order the engine makes them.
        let mark: Int
        let changes: [String: PropertyValue?]
        /// The keys whose value it still decides: a later edit the copy took first decides the keys they share, as
        /// does the server for a key it kept its own value of.
        var laid: Set<String>
        var state = State.onItsWay

        init(item: ItemID, mark: Int, changes: [String: PropertyValue?]) {
            self.item = item
            self.mark = mark
            self.changes = changes
            laid = Set(changes.keys)
        }
    }

    /// What an edit's keys held as the person wrote them when it was made.
    struct PropertiesBefore {
        /// The copy's values when the edit was made.
        let shown: [String: PropertyValue?]
        /// The edits of the item that were on their way then and set any of the keys, in the order they were made.
        let earlier: [(id: WriteID, edit: PropertyEdit)]

        /// Read when the person chooses Undo, so an earlier edit refused since is left out. The writes still on their
        /// way are the ones the undo assumes are made (`ItemWrite.editProperties`).
        func resolved() -> (values: [String: PropertyValue?], assuming: Set<WriteID>) {
            var values = shown
            var assuming: Set<WriteID> = []
            for (id, edit) in earlier where edit.state != .notMade {
                let keys = edit.laid.intersection(shown.keys)
                for key in keys { if let value = edit.changes[key] { values.updateValue(value, forKey: key) } }
                if !keys.isEmpty, edit.state == .onItsWay { assuming.insert(id) }
            }
            return (values, assuming)
        }
    }
}
