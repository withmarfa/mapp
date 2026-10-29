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
    /// The library refused the write: the item is gone, or no longer has the property.
    case notSaved

    var reason: String {
        switch self {
        case .conflict: String(localized: "The value changed while you were editing it.")
        case .notANumber: String(localized: "The value isn’t a number.")
        case .notEditable: String(localized: "The item can no longer be edited.")
        case .notSaved: String(localized: "The value could not be saved.")
        }
    }
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
        guard isDirty, text != current, text != base else { return nil }
        guard isEditable else { return .notEditable }
        switch commit(as: kind, current: current) {
        case .conflict: return .conflict
        case .invalid: return .notANumber
        case .unchanged, .alreadyCurrent, .write: return nil
        }
    }

    /// Leaves nothing the person typed behind. A draft that can be written is written; one that cannot goes back to
    /// the person through `notices`, which puts it on the clipboard, and is dropped so it is told once. Nothing is
    /// told for a draft the item already holds, or that is back at what it began from.
    func handOff(
        label: String, as kind: ItemTypeInfo.Field.Kind, current: String, isEditable: Bool,
        write: (PropertyValue?) -> Bool, to notices: Notices
    ) {
        guard isDirty else { return }
        if isEditable, case .write(let value) = commit(as: kind, current: current) {
            rejected = !write(value)
            if !rejected {
                isDirty = false
                return
            }
        }
        guard let loss = loss(as: kind, current: current, isEditable: isEditable) ?? (rejected && text != current && text != base ? .notSaved : nil) else {
            discard(toMatch: current)
            return
        }
        notices.notKept(String(localized: "Property Not Saved"), text: "\(label): \(text)", reason: loss.reason)
        discard(toMatch: current)
    }

    /// Starts again from the text the item holds now, dropping what was typed.
    func discard(toMatch current: String) {
        text = current
        base = current
        isDirty = false
        rejected = false
    }
}

extension DetailsPresentation {
    /// Writes or hands back the property drafts held for `itemID`, or for every item, since the row that showed them
    /// is gone for good: the item switched, the window closed or the app is quitting. A section folded, or an
    /// inspector hidden, does not come here, so a held-back edit is still there when it shows again.
    func handOffProperties(of itemID: ItemID? = nil, in library: any ItemLibrary, undoManager: UndoManager?) {
        for (id, key, draft) in unsavedProperties(of: itemID) {
            guard let field = draft.field else { continue }
            let item = library.item(id)
            draft.handOff(
                label: field.displayLabel, as: field.kind, current: item?.value(of: key).map(ItemValueText.string) ?? "",
                isEditable: item?.isEditable ?? false,
                write: { library.setItemProperty(id, key: key, value: $0, undoManager: undoManager) }, to: library.notices)
        }
    }
}
