import SwiftUI

/// A change to one field of a type that needs words from the person: its new name, or its list of choices. `type` is the
/// type as the page showed it, which the change is checked against and the server is asked to still match.
struct FieldEditRequest: Identifiable {
    enum Kind { case rename, choices }

    let id = UUID()
    let kind: Kind
    let type: ItemTypeInfo
    let key: String

    var field: ItemTypeInfo.Field? { type.fields.first { $0.key == key } }
}

/// Renames a field or edits a choice field's choices, for every item of the type. The sheet keeps what was typed where
/// the change is refused, and says why in place; it closes only when the server has taken the change.
struct FieldEditSheet: View {
    @CurrentLibrary private var library
    @Environment(\.dismiss) private var dismiss
    let request: FieldEditRequest
    @State private var label: String
    @State private var draft: ChoiceDraft
    @State private var problem: String?
    @State private var isSaving = false

    init(request: FieldEditRequest) {
        self.request = request
        _label = State(initialValue: request.field?.label ?? "")
        if case .choice(let choices)? = request.field?.kind {
            _draft = State(initialValue: ChoiceDraft(existing: choices))
        } else {
            _draft = State(initialValue: ChoiceDraft(existing: []))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.kind == .rename ? "Rename Field" : "Edit Choices").interfaceFont(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch request.kind {
            case .rename:
                TextField("Name", text: $label)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                    .accessibilityIdentifier("FieldRenameField")
            case .choices:
                choiceList
            }
            if let problem {
                Text(problem)
                    .interfaceFont(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("FieldEditProblem")
            }
            HStack {
                if isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .mappButton(.secondary)
                Button(request.kind == .rename ? "Rename" : "Done", action: save)
                    .keyboardShortcut(.defaultAction)
                    .mappButton(.primary)
                    .disabled(isSaving)
                    .accessibilityIdentifier("FieldEditDone")
            }
        }
        .padding(20)
        .frame(width: 380)
        .onChange(of: label) { problem = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FieldEditSheet")
    }

    private var choiceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            List {
                ForEach($draft.rows) { $row in
                    HStack {
                        // A word the field already offers is not retyped: items holding it would keep the old word.
                        if row.isNew {
                            TextField("Choice", text: $row.text)
                                .labelsHidden()
                                .textFieldStyle(.plain)
                                .onChange(of: row.text) { problem = nil }
                        } else {
                            Text(row.text).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("Remove Choice", systemImage: "minus.circle") {
                            draft.remove(row.id)
                            problem = nil
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { draft.rows.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 180)
            Button("Add Choice", systemImage: "plus") {
                draft.add()
                problem = nil
            }
            Text("Items that already hold a choice you take out keep it.")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let name = request.field?.label ?? ""
        let type = request.type.label
        switch request.kind {
        case .rename:
            return String(localized: "This changes “\(name)” on every \(type), in every app.")
        case .choices:
            return String(localized: "These are the choices “\(name)” offers on every \(type), in every app.")
        }
    }

    private func save() {
        guard !isSaving, request.field != nil else { return }
        let edit: FieldEdit = switch request.kind {
        case .rename: .rename(key: request.key, label: label)
        case .choices: .setChoices(key: request.key, choices: draft.choices)
        }
        let plan: FieldEditPlan
        do {
            plan = try request.type.plan(edit, in: library.catalogue)
        } catch {
            problem = error.message
            return
        }
        // Naming the field what it is called already changes nothing.
        if case .rename(_, let name) = plan.edit, name == request.field?.label { return dismiss() }
        if case .setChoices(_, let choices) = plan.edit, case .choice(let before)? = request.field?.kind, choices == before { return dismiss() }
        isSaving = true
        let library = library
        Task {
            let failure = await library.editField(plan)
            isSaving = false
            if let failure { problem = failure.message } else { dismiss() }
        }
    }
}

/// The question before a field is removed from its type, which says plainly what becomes of the values.
@MainActor
enum FieldRemoval {
    /// Asks on `window`, or on its own where there is none, and carries out `remove` only on the person's yes.
    static func confirm(_ plan: FieldEditPlan, typeLabel: String, on window: NSWindow?, remove: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Remove “\(plan.shown.label)” from every \(typeLabel)?")
        alert.informativeText = String(localized: "The field leaves every \(typeLabel), in every app. Items keep the values they hold, and an app can still read them.")
        let removeButton = alert.addButton(withTitle: String(localized: "Remove Field"))
        removeButton.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        if let window {
            alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { remove() } }
        } else if alert.runModal() == .alertFirstButtonReturn {
            remove()
        }
    }
}

/// Presents the sheet for the field edit a window was asked for.
struct FieldEditSheets: ViewModifier {
    let details: DetailsPresentation

    func body(content: Content) -> some View {
        content.sheet(item: Binding { details.fieldEdit } set: { details.fieldEdit = $0 }) { FieldEditSheet(request: $0) }
    }
}
