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
    /// The text is a number the field does not take: not whole, or outside its bounds.
    case outOfRange
    case write(PropertyValue?)
}

/// Why typed text cannot be written when its row leaves the screen.
nonisolated enum PropertyLoss: Equatable {
    /// The item's value changed since the draft began.
    case conflict
    case notANumber
    /// A number the field's range or whole-number rule refuses.
    case outOfRange
    /// The item can no longer be edited.
    case notEditable
    /// The library refused the write: the item is gone, or no longer has the property.
    case notSaved

    var reason: String {
        switch self {
        case .conflict: String(localized: "The value changed while you were editing it.")
        case .notANumber: String(localized: "The value isn’t a number.")
        case .outOfRange: String(localized: "The value is outside what the field takes.")
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
    func commit(
        as kind: ItemTypeInfo.Field.Kind, rule: NumberRule = NumberRule(), current: String, overwriting: Bool = false, locale: Locale = .current
    ) -> PropertyCommit {
        guard isDirty else { return .unchanged }
        if text == current || text == base { return .alreadyCurrent }
        if !overwriting, conflicts(with: current) { return .conflict }
        if text.isEmpty { return .write(nil) }
        if case .number = kind {
            guard let number = PropertyNumber.parse(text, integer: rule.integer, locale: locale) else { return .invalid }
            guard rule.allows(number) else { return .outOfRange }
            return .write(.number(number))
        }
        return .write(.string(text))
    }

    /// What the person typed that a row leaving the screen would lose: a draft that cannot be written, and that nothing
    /// else keeps. Nil where leaving loses nothing, because the text is written, is already the item's, or was never
    /// typed.
    func loss(
        as kind: ItemTypeInfo.Field.Kind, rule: NumberRule = NumberRule(), current: String, isEditable: Bool, locale: Locale = .current
    ) -> PropertyLoss? {
        guard isDirty, text != current, text != base else { return nil }
        guard isEditable else { return .notEditable }
        switch commit(as: kind, rule: rule, current: current, locale: locale) {
        case .conflict: return .conflict
        case .invalid: return .notANumber
        case .outOfRange: return .outOfRange
        case .unchanged, .alreadyCurrent, .write: return nil
        }
    }

    /// Leaves nothing the person typed behind. A draft that can be written is written; one that cannot goes back to
    /// the person through `notices`, which puts it on the clipboard, and is dropped so it is told once. Nothing is
    /// told for a draft the item already holds, or that is back at what it began from.
    func handOff(
        label: String, as kind: ItemTypeInfo.Field.Kind, rule: NumberRule = NumberRule(), current: String, isEditable: Bool,
        locale: Locale = .current, write: (PropertyValue?) -> Bool, to notices: Notices
    ) {
        guard isDirty else { return }
        if isEditable, case .write(let value) = commit(as: kind, rule: rule, current: current, locale: locale) {
            rejected = !write(value)
            if !rejected {
                isDirty = false
                return
            }
        }
        guard let loss = loss(as: kind, rule: rule, current: current, isEditable: isEditable, locale: locale) ?? (rejected && text != current && text != base ? .notSaved : nil) else {
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
        handOff(unsavedProperties(of: itemID), in: library, undoManager: undoManager)
    }

    /// Hands back the property drafts of every item but `shown`, the one the inspector lists. The selection changing
    /// comes here whether or not the inspector is on screen, so a draft held back while it was hidden is not left
    /// waiting unseen.
    func handOffProperties(except shown: ItemID?, in library: any ItemLibrary, undoManager: UndoManager?) {
        handOff(unsavedProperties().filter { $0.item != shown }, in: library, undoManager: undoManager)
    }

    private func handOff(
        _ drafts: [(item: ItemID, key: String, draft: ItemPropertyDraft)], in library: any ItemLibrary, undoManager: UndoManager?
    ) {
        for (id, key, draft) in drafts {
            guard let field = draft.field else { continue }
            let item = library.item(id)
            draft.handOff(
                label: field.displayLabel, as: field.kind, rule: field.numberRule,
                current: item?.value(of: key).map(ItemValueText.editing) ?? "",
                isEditable: item?.isEditable ?? false,
                write: { library.setItemProperty(id, key: key, value: $0, undoManager: undoManager) }, to: library.notices)
        }
    }
}

/// Whole and decimal numbers as a person types them: in their own locale's way, with no grouping and no exponent.
nonisolated enum PropertyNumber {
    /// The number the text names, or nil where it is not one. The locale's decimal separator is the only one accepted
    /// ("1,5" in German, "1.5" in English), so a grouping separator is never mistaken for a decimal point. An integer
    /// field takes no decimal part, and neither takes an exponent.
    static func parse(_ text: String, integer: Bool, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator?.first ?? "."
        var digits = 0
        var sawSeparator = false
        var normalized = ""
        for (index, character) in trimmed.enumerated() {
            if character.isASCII, character.isNumber {
                digits += 1
            } else if (character == "-" || character == "+") && index == 0 {
            } else if character == separator && !integer && !sawSeparator {
                sawSeparator = true
                normalized.append(".")
                continue
            } else {
                return nil
            }
            normalized.append(character)
        }
        guard digits > 0 else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The number the text names if the rule takes it: whole, and within the bounds.
    static func parse(_ text: String, rule: NumberRule, locale: Locale = .current) -> Decimal? {
        parse(text, integer: rule.integer, locale: locale).flatMap { rule.allows($0) ? $0 : nil }
    }

    /// The text that edits `value`: exact, with the locale's decimal separator and no grouping, so it reads back as the
    /// same number through `parse`.
    static func editing(_ value: Decimal, locale: Locale = .current) -> String {
        let text = NSDecimalNumber(decimal: value).stringValue
        guard let separator = locale.decimalSeparator, separator != "." else { return text }
        return text.replacingOccurrences(of: ".", with: separator)
    }
}
