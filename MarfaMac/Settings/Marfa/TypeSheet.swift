import Marfa
import SwiftUI

/// The one sheet over a type's page: its icon, a new type, or what a word means.
struct TypeSheet: View {
    let model: TypesModel
    let host: any MarfaSettingsHost

    var body: some View {
        if model.iconTarget != nil {
            iconSheet
        } else if model.isMakingChild {
            childSheet
        } else if model.isAddingField {
            fieldSheet
        } else if model.isRenamingField {
            renameSheet
        } else if model.meaningWord != nil {
            meaningSheet
        }
    }

    private var fieldSheet: some View {
        @Bindable var model = model
        return SettingsSheet(title: Text("New Field"), line: Text("Every item of this type, and of any type based on it, can hold it.")) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                SettingsSheetField(label: "Name", error: model.fieldErrors[.newField]) {
                    SettingsField(
                        title: "Name", text: $model.newFieldName, isError: model.fieldErrors[.newField] != nil, width: nil,
                        onSubmit: { Task { await model.makeField() } })
                }
                SettingsSheetField(label: "Kind") {
                    SettingsPopUp(title: "Kind", selection: $model.newFieldKind) {
                        ForEach(FieldKind.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    }
                }
                if model.newFieldKind == .choice {
                    SettingsSheetField(label: "Choices") {
                        SettingsField(title: "Choices", text: $model.newFieldChoices, prompt: "Separated by commas", width: nil)
                    }
                }
            }
        } buttons: {
            SettingsButton("Cancel") { model.cancelField() }.disabled(model.isWorking)
            SettingsButton("Add", role: .confirm) { Task { await model.makeField() } }.disabled(!model.canMakeField)
        }
    }

    private var renameSheet: some View {
        @Bindable var model = model
        return SettingsSheet(title: Text("Rename Field"), line: Text("The name people read. Items keep their values.")) {
            SettingsSheetField(label: "Name", error: model.fieldErrors[.fieldName]) {
                SettingsField(
                    title: "Name", text: $model.fieldNameDraft, isError: model.fieldErrors[.fieldName] != nil, width: nil,
                    onSubmit: { Task { await model.commitRename() } })
            }
        } buttons: {
            SettingsButton("Cancel") { model.cancelRename() }.disabled(model.isWorking)
            SettingsButton("Save", role: .confirm) { Task { await model.commitRename() } }.disabled(model.isWorking)
        }
    }

    private var childSheet: some View {
        @Bindable var model = model
        return SettingsSheet(
            title: Text("New Type"), line: Text("It starts with the words and fields of the type it is based on, and adds its own.")
        ) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                SettingsSheetField(label: "Name", error: model.fieldErrors[.newType]) {
                    SettingsField(
                        title: "Name", text: $model.childName, isError: model.fieldErrors[.newType] != nil, width: nil,
                        onSubmit: { Task { await model.makeChild() } })
                }
                SettingsSheetField(label: "Based On") {
                    SettingsPopUp(title: "Based On", selection: $model.childParent) {
                        ForEach(model.basedOnChoices(for: "")) { Text(verbatim: model.title(of: $0)).tag(Optional($0.id)) }
                    }
                }
            }
        } buttons: {
            SettingsButton("Cancel") { model.cancelChild() }.disabled(model.isWorking)
            SettingsButton("Add", role: .confirm) { Task { await model.makeChild() } }.disabled(!model.canMakeChild)
        }
    }

    private var meaningSheet: some View {
        @Bindable var model = model
        let word = model.meaningWord.map(TypesModel.title(ofWord:)) ?? ""
        return SettingsSheet(
            title: Text("What \(word) Means"),
            line: Text("A sentence for anyone who reads this type. \(TypesModel.length(of: model.meaningDraft)) of \(TypesModel.wordMeaningLimit) characters.")
        ) {
            SettingsSheetField(label: "Meaning", error: model.fieldErrors[.meaning]) {
                SettingsField(
                    title: "Meaning", text: $model.meaningDraft, isError: model.fieldErrors[.meaning] != nil, width: nil,
                    onSubmit: { Task { await model.saveMeaning() } })
            }
        } buttons: {
            SettingsButton("Cancel") { model.cancelMeaning() }.disabled(model.isSavingMeaning)
            SettingsButton("Save", role: .confirm) { Task { await model.saveMeaning() } }.disabled(model.isSavingMeaning)
        }
    }

    private var iconSheet: some View {
        @Bindable var model = model
        return SettingsSheet(
            title: Text("Choose an Icon"), line: Text("The icon shows in every app that uses \(host.serverName)."), isWide: true
        ) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                if model.markSets.count > 1 {
                    SettingsPopUp(title: "Icon Set", selection: $model.iconSet) {
                        ForEach(model.markSets) { Text(verbatim: $0.title).tag($0) }
                    }
                }
                SettingsField(title: "Search Icons", text: $model.iconSearch, width: nil)
                SettingsSection(name: nil) {
                    let choices = model.iconChoices
                    if choices.isEmpty { SettingsRow("No Icons Match", look: .off) }
                    ForEach(choices, id: \.self) { icon in
                        Button { Task { await model.chooseIcon(icon) } } label: {
                            SettingsRow(
                                title: Text(verbatim: host.markTitle(icon)),
                                lead: .custom(AnyView(host.markGlyph(icon).frame(width: SettingsTokens.Metric.tile, height: SettingsTokens.Metric.tile)))
                            ) {
                                if icon == model.currentIcon { Image(systemName: "checkmark").accessibilityLabel("Chosen") }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isChangingIcon)
                    }
                }
                if let failure = model.iconFailure {
                    Text(verbatim: failure).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed)
                }
            }
        } leading: {
            SettingsButton("Use Default") { Task { await model.chooseIcon(nil) } }.disabled(model.isChangingIcon)
        } buttons: {
            SettingsButton("Cancel") { model.closeIcon() }.disabled(model.isChangingIcon)
        }
    }
}
