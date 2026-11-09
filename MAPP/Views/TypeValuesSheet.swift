import MarfaIcons
import SwiftUI

/// Asks for the values a type needs that the items lack, once a person has chosen that type in the Change Type panel.
/// The panel holds no field for them, so this is the one case that still asks; every other change is made at the
/// choosing. Items that can't become the type are named by the change and left as they are.
struct TypeValuesSheet: View {
    @CurrentLibrary private var library
    @Environment(\.dismiss) private var dismiss
    let request: TypeValuesRequest
    /// The values picked or committed for the required fields, by key.
    @State private var values: [String: PropertyValue] = [:]
    /// What is typed in each required field, which a text field commits only on Return or when it loses focus.
    @State private var drafts: [String: ItemPropertyDraft] = [:]

    var body: some View {
        let preview = library.typeChangePreview(for: request.ids, to: request.type)
        let label = library.catalogue.label(for: request.type)
        VStack(alignment: .leading, spacing: 12) {
            Text("Change Type").interfaceFont(.title2.bold())
            Text("\(label) needs these values:").foregroundStyle(.secondary)
            ForEach(preview.missing, id: \.key) { field in
                ItemPropertyRow(definition: field, value: values[field.key], isEditable: true, onChange: { value in
                    values[field.key] = value
                    return true
                }, retainedDraft: draft(for: field.key), handsOffOnLeave: false)
                if field.kind == .number, isNotANumber(field) {
                    Text(numberRefusal(field))
                        .interfaceFont(.caption).foregroundStyle(.orange)
                        .accessibilityIdentifier("TypeChangeNotANumber.\(field.key)")
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Change Type") { change() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canChange)
                    .accessibilityIdentifier("TypeChangeConfirm")
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            drafts = Dictionary(uniqueKeysWithValues: preview.missing.map { ($0.key, ItemPropertyDraft()) })
        }
        // An item that goes or can no longer change, as when it is deleted elsewhere, leaves nothing to change.
        .onChange(of: library.offersTypeChange(for: request.ids)) { if !library.offersTypeChange(for: request.ids) { dismiss() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("TypeChangeSheet")
    }

    private func draft(for key: String) -> ItemPropertyDraft {
        drafts[key] ?? ItemPropertyDraft()
    }

    /// The values to fill with: those committed, and what is typed and not committed yet.
    private var filling: [String: PropertyValue] {
        var filling = values
        for (key, draft) in drafts where draft.isDirty {
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let field = library.catalogue.itemTypes[request.type]?.fields.first(where: { $0.key == key }) else { continue }
            let value: PropertyValue? = switch field.kind {
            case .number: PropertyNumber.parse(text, rule: field.numberRule).map(PropertyValue.number)
            default: text.isEmpty ? nil : .string(text)
            }
            filling[key] = value
        }
        return filling
    }

    /// Whether the number typed in `field` is text that is not a number, which keeps Change Type off.
    private func isNotANumber(_ field: ItemTypeInfo.Field) -> Bool {
        let draft = draft(for: field.key)
        guard draft.isDirty else { return false }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && PropertyNumber.parse(text, rule: field.numberRule) == nil
    }

    /// Why the number typed in `field` is refused: not a number at all, or outside what the field takes, in the
    /// field's own words where it declares a range.
    private func numberRefusal(_ field: ItemTypeInfo.Field) -> String {
        let text = draft(for: field.key).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PropertyNumber.parse(text, integer: field.isInteger) != nil else { return PropertyLoss.notANumber.reason }
        return field.numberRule.requirement ?? PropertyLoss.outOfRange.reason
    }

    private var canChange: Bool {
        let plan = library.typeChangePlan(request.ids, to: request.type, filling: filling)
        return plan.missing.isEmpty && !plan.items.isEmpty
    }

    private func change() {
        guard canChange else { return }
        // A change refused before anything is sent leaves the sheet open with what was typed.
        library.changeTypeAfterSaving(request.ids, to: request.type, filling: filling, undoManager: request.undoManager) { sent in
            if sent { dismiss() }
        }
    }
}

extension ItemLibrary {
    /// Changes the items' type once every open page has handed over what was just typed, so the change moves the
    /// text the person sees, and the page then reads it from the new type's key. `done` says whether it was sent.
    func changeTypeAfterSaving(
        _ ids: Set<ItemID>, to type: TypeID, filling: [String: PropertyValue], undoManager: UndoManager?,
        then done: @escaping (Bool) -> Void
    ) {
        EditorController.flushAll(leaving: false) { [self] kept in
            guard kept else {
                notices.tell(String(localized: "Can’t Change Type"), String(localized: "Finish editing the current note, then try again."))
                return done(false)
            }
            done(changeType(ids, to: type, filling: filling, undoManager: undoManager))
        }
    }
}
