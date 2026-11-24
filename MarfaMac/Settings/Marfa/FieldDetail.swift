import Marfa
import SwiftUI

/// One field's page: what it means, its kind, the rules an owner sets and removing it. A field a type above gives has no
/// page of its own: it is that type's to change.
struct FieldDetail: View {
    let model: TypesModel
    let type: TypeRecord
    let field: TypeFieldRecord
    let host: any MarfaSettingsHost
    @Environment(\.settingsBack) private var back

    private var name: String { TypesModel.title(of: field) }
    private var kind: FieldKind? { FieldKind(rawValue: field.kind) }
    /// What the type calls one of its items, and several, as the sentences under the rules say them.
    private var singular: String { type.label.localizedLowercase }
    private var plural: String { model.title(of: type).localizedLowercase }

    var body: some View {
        @Bindable var model = model
        SettingsPageColumn {
            SettingsHead(
                symbol: Self.symbol(of: field.kind), tone: .gray, title: Text(verbatim: name),
                line: Text("A field of \(model.title(of: type)).")
            ) {
                SettingsButton("Rename…") { model.beginRename() }
            }
            if let failure = model.pageFailure { OwnerProblem(title: "Not Changed", failure: failure, page: .types, host: host) }
            SettingsSection("Field") {
                SettingsStackRow(
                    title: Text("What It Means"),
                    line: Text("\(TypesModel.length(of: model.fieldMeaning)) of \(TypesModel.fieldMeaningLimit) characters."),
                    error: model.fieldErrors[.fieldMeaning]
                ) {
                    SettingsField(
                        title: "What It Means", text: $model.fieldMeaning, isError: model.fieldErrors[.fieldMeaning] != nil, width: nil,
                        onSubmit: { Task { await model.commitFieldMeaning() } }, onEndEditing: { Task { await model.commitFieldMeaning() } })
                }
                SettingsRow("Kind") { SettingsLockedValue(text: FieldKind.title(ofKind: field.kind)) }
                if kind == .choice { choicesRow }
            }
            SettingsSection("Rules") {
                SettingsRow(title: Text("Required"), line: Text("Every \(singular) must have one."), error: model.fieldErrors[.fieldRule]) {
                    SettingsToggle(title: "Required", isOn: Binding { field.isRequired } set: { on in Task { await model.setRequired(on) } })
                }
                SettingsRow(title: Text("Searchable"), line: Text("Search finds \(plural) by it."), error: model.fieldErrors[.fieldSearchable]) {
                    SettingsToggle(title: "Searchable", isOn: Binding { field.isSearchable } set: { on in Task { await model.setSearchable(on) } })
                }
                if kind == .text {
                    SettingsRow("Longest", error: model.fieldErrors[.fieldLongest]) {
                        SettingsNumberField(
                            title: "Longest", text: $model.fieldLongest, unit: "characters", prompt: "No limit",
                            isError: model.fieldErrors[.fieldLongest] != nil,
                            onSubmit: { Task { await model.commitLongest() } }, onEndEditing: { Task { await model.commitLongest() } })
                    }
                }
            }
            SettingsSection("Remove") {
                SettingsRow(title: Text("Remove \(name)"), line: Text("Each \(singular) keeps its value."), error: model.fieldErrors[.fieldRemove]) {
                    SettingsButton("Remove…", role: .destructive) { askToRemove() }
                }
            }
        }
    }

    private var choicesRow: some View {
        @Bindable var model = model
        return SettingsRow("Choices", error: model.fieldErrors[.choice]) {
            SettingsWordChips(
                words: field.choices.map { SettingsWord(id: $0, title: $0, isLocked: false) }, addTitle: "Add a Choice",
                isAdding: model.isAddingChoice, draft: $model.choiceDraft, isError: model.fieldErrors[.choice] != nil,
                begin: { model.beginChoice() }, commit: { Task { await model.commitChoice() } }, cancel: { model.cancelChoice() },
                menu: { word in AnyView(Button("Remove Choice") { Task { await model.removeChoice(word.id) } }) })
        }
    }

    private func askToRemove() {
        SettingsAlert.confirm(
            title: String(localized: "Remove \(name)?"),
            message: String(localized: "Each item keeps the value it holds, and \(model.title(of: type)) stops asking for it."),
            confirm: String(localized: "Remove Field"), window: NSApp.keyWindow
        ) { confirmed, _ in
            guard confirmed else { return }
            Task {
                await model.removeField()
                if model.openFieldKey == nil { back() }
            }
        }
    }

    private static func symbol(of kind: String) -> String {
        switch kind {
        case "number", "integer": "number"
        case "boolean": "checkmark.circle"
        case "date", "datetime": "calendar"
        case "url": "link"
        case "email": "envelope"
        case "enum": "list.bullet"
        case "status": "circle.lefthalf.filled"
        default: "textformat"
        }
    }
}
