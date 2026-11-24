import Foundation
import Marfa

extension ValueEditModel {
    static func text(of value: PropertyValue?) -> String { value.map(ItemValueText.editing) ?? "" }

    /// What the field in a text or a number panel holds, as the person types it.
    var typed: String {
        get { draft.text }
        set {
            guard newValue != draft.text else { return }
            if !draft.isDirty { draft.base = currentText }
            draft.text = newValue
            draft.isDirty = true
            draft.rejected = false
            hasConflict = false
            notice = nil
        }
    }

    var currentText: String { Self.text(of: value) }

    /// Writes what was typed, and closes on success. A refusal keeps the text and the panel and says why; a value that
    /// changed under the text waits for the person to say which they mean.
    func commitText(overwriting: Bool = false) {
        guard let field = kind.field else { return }
        guard isEditable else {
            close()
            return
        }
        switch draft.commit(as: field.kind, rule: field.numberRule, current: currentText, overwriting: overwriting) {
        case .unchanged:
            close()
        case .alreadyCurrent:
            draft.discard(toMatch: currentText)
            close()
        case .conflict:
            hasConflict = true
            notice = String(localized: "This value changed while you were editing. Your edit hasn’t been saved.")
        case .invalid:
            draft.rejected = true
            notice = field.numberRule.requirement ?? String(localized: "The value isn’t a number.")
        case .outOfRange:
            draft.rejected = true
            notice = field.numberRule.requirement ?? PropertyLoss.outOfRange.reason
        case .write(let new):
            if request.write(new) {
                draft.isDirty = false
                draft.base = Self.text(of: new)
                close()
            } else {
                draft.rejected = true
                notice = refusalReason(String(localized: "The value could not be saved. Your input has been kept."))
            }
        }
    }

    /// The person chose to keep their text over the value that changed.
    func keepEdit() { commitText(overwriting: true) }

    /// The person chose the value that changed over their text.
    func useCurrentValue() {
        draft.discard(toMatch: currentText)
        hasConflict = false
        notice = nil
    }
}
