import MarfaIcons
import SwiftUI

/// Changes the type of the items a window asked for: the types any of them can become, a value for each required field
/// they lack, and the fields the new type does not use, which stay on the items. Items that can't become the type are
/// named and left as they are.
struct TypeChangeSheet: View {
    @CurrentLibrary private var library
    @Environment(\.dismiss) private var dismiss
    let request: TypeChangeRequest
    @State private var selected: TypeID?
    /// The values picked or committed for the required fields, by key.
    @State private var values: [String: PropertyValue] = [:]
    /// What is typed in each required field, which a text field commits only on Return or when it loses focus.
    @State private var drafts: [String: ItemPropertyDraft] = [:]

    var body: some View {
        let options = library.typeChangeOptions(for: request.ids)
        let preview = selected.map { library.typeChangePreview(for: request.ids, to: $0) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Change Type").interfaceFont(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            List(options, selection: $selected) { option in
                Label { Text(option.label) } icon: { TypeIcon(id: option.icon) }
                    .tag(option.id)
                    .accessibilityIdentifier("TypeChangeOption.\(option.id.rawValue)")
            }
            .frame(height: 200)
            .overlay {
                if options.isEmpty { ContentUnavailableView("No Other Types", systemImage: "square.on.square.dashed") }
            }
            if let selected, let preview, let label = options.first(where: { $0.id == selected })?.label {
                if !preview.missing.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(label) needs these values:").interfaceFont(.callout)
                        ForEach(preview.missing, id: \.key) { field in
                            ItemPropertyRow(definition: field, value: values[field.key], isEditable: true, onChange: { value in
                                values[field.key] = value
                                return true
                            }, retainedDraft: draft(for: field.key), handsOffOnLeave: false)
                            if field.kind == .number, isNotANumber(field) {
                                Text(PropertyLoss.notANumber.reason)
                                    .interfaceFont(.caption).foregroundStyle(.orange)
                                    .accessibilityIdentifier("TypeChangeNotANumber.\(field.key)")
                            }
                        }
                    }
                }
                if !preview.unused.isEmpty {
                    Text("\(label) doesn’t use \(preview.unused.formatted(.list(type: .and))). They stay on the item, and show again if you change it back.")
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("TypeChangeUnused")
                }
                if let skipped = library.typeChangePlan(request.ids, to: selected, filling: filling).skips.message {
                    Text(skipped)
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("TypeChangeSkipped")
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Change Type") { change() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canChange(preview))
                    .accessibilityIdentifier("TypeChangeConfirm")
            }
        }
        .padding(20)
        .frame(width: 400)
        .onChange(of: selected) {
            values = [:]
            let missing = selected.map { library.typeChangePreview(for: request.ids, to: $0).missing } ?? []
            drafts = Dictionary(uniqueKeysWithValues: missing.map { ($0.key, ItemPropertyDraft()) })
        }
        // An item that goes or can no longer change, as when it is deleted elsewhere, leaves nothing to change.
        .onChange(of: options.isEmpty) { if options.isEmpty { dismiss() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("TypeChangeSheet")
    }

    private var subtitle: String {
        if request.ids.count == 1, let item = request.ids.first.flatMap({ library.item($0) }) {
            String(localized: "Choose a new type for “\(item.title)”.")
        } else {
            String(localized: "Choose a new type for \(request.ids.count) items.")
        }
    }

    private func draft(for key: String) -> ItemPropertyDraft {
        drafts[key] ?? ItemPropertyDraft()
    }

    /// The values to fill with: those committed, and what is typed and not committed yet.
    private var filling: [String: PropertyValue] {
        var filling = values
        for (key, draft) in drafts where draft.isDirty {
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let field = selected.flatMap({ library.catalogue.itemTypes[$0] })?.fields.first(where: { $0.key == key }) else { continue }
            let value: PropertyValue? = switch field.kind {
            case .number: PropertyNumber.parse(text, integer: field.isInteger).map(PropertyValue.number)
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
        return !text.isEmpty && PropertyNumber.parse(text, integer: field.isInteger) == nil
    }

    private func canChange(_ preview: TypeChangePreview?) -> Bool {
        guard let selected, preview != nil else { return false }
        let plan = library.typeChangePlan(request.ids, to: selected, filling: filling)
        return plan.missing.isEmpty && !plan.items.isEmpty
    }

    private func change() {
        guard let selected, canChange(library.typeChangePreview(for: request.ids, to: selected)) else { return }
        // A change refused before anything is sent leaves the sheet open with what was typed.
        library.changeTypeAfterSaving(request.ids, to: selected, filling: filling, undoManager: request.undoManager) { sent in
            if sent { dismiss() }
        }
    }
}

/// Opens the Change Type sheet for the items, in the window whose presentation it is given.
struct TypeChangeButton: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let details: DetailsPresentation?
    let undoManager: UndoManager?

    var body: some View {
        Button("Change Type…", systemImage: "square.on.square") {
            details?.typeChange = TypeChangeRequest(ids: ids, undoManager: undoManager)
        }
        .disabled(details == nil || !library.offersTypeChange(for: ids))
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
