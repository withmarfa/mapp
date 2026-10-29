import Foundation

/// What committing a draft does.
nonisolated enum PropertyCommit: Equatable {
    /// Nothing was typed.
    case unchanged
    /// The typed text is already what the item holds.
    case alreadyCurrent
    /// The item's value changed since the draft began, so writing would replace a change the person has not seen.
    case conflict
    /// The text is not a number.
    case invalid
    case write(PropertyValue?)
}

extension ItemPropertyDraft {
    /// Whether the item's value changed under a draft that differs from it.
    func conflicts(with current: String) -> Bool {
        isDirty && base != nil && base != current && text != current
    }

    /// What committing the draft does for a field of this kind, given the text the item holds now. A draft over a
    /// value that changed since it began is held back unless the person chose to overwrite it.
    func commit(as kind: ItemTypeInfo.Field.Kind, current: String, overwriting: Bool = false) -> PropertyCommit {
        guard isDirty else { return .unchanged }
        if text == current { return .alreadyCurrent }
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

    /// Starts again from the text the item holds now, dropping what was typed.
    func discard(toMatch current: String) {
        text = current
        base = current
        isDirty = false
        rejected = false
    }
}
