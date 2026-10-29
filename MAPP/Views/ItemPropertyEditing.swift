import Foundation

/// What committing a draft does.
nonisolated enum PropertyCommit: Equatable {
    /// Nothing was typed.
    case unchanged
    /// Nothing is left to write: the typed text is what the item holds, or what the draft began from, so the person
    /// has no edit to keep.
    case alreadyCurrent
    /// The item's value changed since the draft began, so writing would replace a change the person has not seen.
    case conflict
    /// The text is not a number.
    case invalid
    case write(PropertyValue?)
}

/// Why typed text cannot be written when its row leaves the screen.
nonisolated enum PropertyLoss: Equatable {
    /// The item's value changed since the draft began.
    case conflict
    case notANumber
    /// The item can no longer be edited.
    case notEditable
}

extension ItemPropertyDraft {
    /// Whether the item's value changed under a draft that differs from it.
    func conflicts(with current: String) -> Bool {
        isDirty && base != nil && base != current && text != current && text != base
    }

    /// What committing the draft does for a field of this kind, given the text the item holds now. A draft over a
    /// value that changed since it began is held back unless the person chose to overwrite it.
    func commit(as kind: ItemTypeInfo.Field.Kind, current: String, overwriting: Bool = false) -> PropertyCommit {
        guard isDirty else { return .unchanged }
        if text == current || text == base { return .alreadyCurrent }
        if !overwriting, conflicts(with: current) { return .conflict }
        if text.isEmpty { return .write(nil) }
        if case .number = kind {
            let scanner = Scanner(string: text)
            scanner.locale = Locale(identifier: "en_US_POSIX")
            guard let number = scanner.scanDecimal(), scanner.isAtEnd, !number.isNaN else { return .invalid }
            return .write(.number(number))
        }
        return .write(.string(text))
    }

    /// What the person typed that a row leaving the screen would lose: a draft that cannot be written, and that nothing
    /// else keeps. Nil where leaving loses nothing, because the text is written, is already the item's, or was never
    /// typed.
    func loss(as kind: ItemTypeInfo.Field.Kind, current: String, isEditable: Bool) -> PropertyLoss? {
        guard isDirty, text != current else { return nil }
        guard isEditable else { return .notEditable }
        switch commit(as: kind, current: current) {
        case .conflict: return .conflict
        case .invalid: return .notANumber
        case .unchanged, .alreadyCurrent, .write: return nil
        }
    }

    /// Starts again from the text the item holds now, dropping what was typed.
    func discard(toMatch current: String) {
        text = current
        base = current
        isDirty = false
        rejected = false
    }
}
