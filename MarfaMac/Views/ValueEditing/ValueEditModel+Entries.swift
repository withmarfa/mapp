import Foundation
import Marfa

extension ValueEditModel {
    /// Writes the list of entries the panel holds, and keeps it where no item holds the value yet (a form's).
    func writeEntries(_ new: PropertyValue?) -> Bool {
        guard isEditable else { return false }
        let taken = request.write(new)
        if taken { keep(new) }
        return taken
    }

    /// The panel is ending: what was typed into the list is written, or goes back to the person through the notices,
    /// unless they cancelled it.
    func leaveEntries(cancelled: Bool) {
        guard case .entries(let field, let shape) = kind, !cancelled else { return }
        entries.leave(shape, label: field.label, value: value, isEditable: isEditable, write: writeEntries, to: library.notices)
    }
}
