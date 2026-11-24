import Marfa
import SwiftUI

/// The one sheet over a type's page: its icon, a new type, a field, what a word means, or deleting a type in use.
struct TypeSheet: View {
    let model: TypesModel
    let host: any MarfaSettingsHost

    /// The open type's plural as a sentence says it: "Only for jobs."
    private var lowercasePlural: String { model.openID.map { model.title(of: $0).localizedLowercase } ?? "" }

    var body: some View {
        if model.iconTarget != nil || model.isChoosingChildIcon {
            iconSheet
        } else if model.isConfirmingDelete {
            TypeDeleteSheet(model: model, host: host)
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
        return SettingsSheet(title: Text("Add Field"), line: Text("Only for \(lowercasePlural).")) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFormGap) {
                SettingsSheetField(label: "Name", error: model.fieldErrors[.newField]) {
                    SettingsField(
                        title: "Name", text: $model.newFieldName, isError: model.fieldErrors[.newField] != nil, width: nil,
                        onSubmit: { Task { await model.makeField() } })
                }
                SettingsSection("Field") {
                    SettingsRow("Kind") {
                        SettingsPopUp(title: "Kind", selection: $model.newFieldKind) {
                            ForEach(FieldKind.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                        }
                    }
                    if model.newFieldKind == .choice {
                        SettingsStackRow(title: Text("Choices")) {
                            SettingsField(title: "Choices", text: $model.newFieldChoices, prompt: "Separated by commas", width: nil)
                        }
                    }
                    SettingsRow("Required") { SettingsToggle(title: "Required", isOn: $model.newFieldRequired) }
                    SettingsRow("Searchable") { SettingsToggle(title: "Searchable", isOn: $model.newFieldSearchable) }
                }
            }
        } buttons: {
            SettingsButton("Cancel") { model.cancelField() }.disabled(model.isWorking)
            SettingsButton("Add Field", role: .confirm) { Task { await model.makeField() } }.disabled(!model.canMakeField)
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
        let name = model.trimmedChildName
        return SettingsSheet(title: Text("New Type"), line: Text("A kind of item, with fields of its own.")) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFormGap) {
                VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                    SettingsSheetField(label: "Name", error: model.fieldErrors[.newType]) {
                        SettingsField(
                            title: "Name", text: $model.childName, isError: model.fieldErrors[.newType] != nil, width: nil,
                            onSubmit: { Task { await model.makeChild() } })
                    }
                    SettingsSheetField(label: "Plural") {
                        SettingsField(
                            title: "Plural", text: $model.childPlural, prompt: name.isEmpty ? nil : TypesModel.regularPlural(of: name), width: nil,
                            onSubmit: { Task { await model.makeChild() } })
                    }
                }
                SettingsSection("Type") {
                    SettingsRow("Based On", line: "It keeps that type’s statuses and fields.") {
                        SettingsPopUp(title: "Based On", selection: $model.childParent) {
                            Text("Nothing").tag(String?.none)
                            Divider()
                            ForEach(model.basedOnChoices(for: "")) { Text(verbatim: model.title(of: $0)).tag(Optional($0.id)) }
                        }
                    }
                    SettingsRow(title: Text("Icon"), lead: .custom(childIconGlyph)) {
                        SettingsButton("Choose…") { model.beginChildIcon() }
                    }
                }
            }
        } buttons: {
            SettingsButton("Cancel") { model.cancelChild() }.disabled(model.isWorking)
            SettingsButton("Create Type", role: .confirm) { Task { await model.makeChild() } }.disabled(!model.canMakeChild)
        }
    }

    /// The icon the new type will show: the one chosen, else the one of the type it is based on.
    private var childIconGlyph: AnyView {
        if let icon = model.childIcon {
            return AnyView(host.markGlyph(icon).frame(width: SettingsTokens.Metric.tile, height: SettingsTokens.Metric.tile))
        }
        return host.typeMark(for: model.childParent ?? "")
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

/// What happens to the items and settings that use a type being deleted: they move to another type first, or stay as they
/// are, naming a type that is gone. The delete is the sheet's own, so it stands alone at the leading edge.
struct TypeDeleteSheet: View {
    let model: TypesModel
    let host: any MarfaSettingsHost

    private var id: String { model.openID ?? "" }
    private var plural: String { model.title(of: id) }
    private var singular: String { model.record(id)?.label ?? plural }

    /// How many items use the type: the move's count once read, else the server's refusal or the library's own count.
    private var items: Int {
        model.movePreview?.items ?? model.refusedUse?.items ?? model.ownItemCount(of: id)
    }

    private func counted(_ count: Int) -> String {
        String(localized: "\(count.formatted()) \(count == 1 ? singular.localizedLowercase : plural.localizedLowercase)")
    }

    /// "18 jobs, a view and a webhook use it."
    private var line: String {
        var parts: [String] = []
        if items > 0 { parts.append(counted(items)) }
        let settings = model.movePreview?.settings ?? []
        for (kind, one, many) in [
            (TypeSettingRecord.Kind.folder, String(localized: "a folder"), String(localized: "folders")),
            (.view, String(localized: "a view"), String(localized: "views")),
            (.webhook, String(localized: "a webhook"), String(localized: "webhooks")),
        ] {
            let count = settings.filter { $0.kind == kind }.count
            if count == 1 { parts.append(one) } else if count > 1 { parts.append("\(count.formatted()) \(many)") }
        }
        if parts.isEmpty, let settings = model.refusedUse?.settings, settings > 0 {
            return String(AttributedString(localized: "^[\(settings) setting](inflect: true) use it.").characters)
        }
        guard !parts.isEmpty else { return String(localized: "Something uses it.") }
        let list = parts.formatted(.list(type: .and))
        let one = parts.count == 1 && (items == 1 || items == 0)
        let sentence = one ? String(localized: "\(list) uses it.") : String(localized: "\(list) use it.")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    var body: some View {
        SettingsSheet(title: Text("Delete \(plural)"), line: Text(verbatim: line), isWide: true) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFormGap) {
                SettingsSection(name: items > 0 ? Text("Its \(items.formatted()) \(items == 1 ? singular : plural)") : nil) {
                    SettingsRadioRow(
                        title: Text("Move Them to Another Type"), line: Text("Their own fields stay on each item."),
                        isOn: model.deleteChoice == .move, choose: { model.deleteChoice = .move }
                    ) {
                        SettingsPopUp(
                            title: "Move To", selection: Binding<String?> { model.moveTarget } set: { target in
                                model.deleteChoice = .move
                                model.setMoveTarget(target)
                            }
                        ) {
                            ForEach(model.moveChoices(for: id)) { Text(verbatim: model.title(of: $0)).tag(Optional($0.id)) }
                        }
                    }
                    SettingsRadioRow(
                        title: Text("Leave Them As They Are"), line: Text("Their fields stay read-only until \(plural) exists again."),
                        isOn: model.deleteChoice == .leave, choose: { model.deleteChoice = .leave })
                }
                if model.deleteChoice == .move { alsoChanges }
                if let failure = model.deleteSheetFailure ?? model.movePreviewFailure {
                    Text(verbatim: failure).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.isDeleting, model.deleteChoice == .move {
                    SettingsSheetStatus(text: Text("Moving \(counted(items)) to \(model.moveTarget.map { model.title(of: $0) } ?? "")…"), isMet: false)
                }
            }
        } leading: {
            SettingsButton("Delete", role: .destructive) { Task { await model.confirmDelete() } }.disabled(!model.canConfirmDelete)
        } buttons: {
            SettingsButton("Cancel") { model.cancelDelete() }.disabled(model.isDeleting)
        }
    }

    /// The folders, views and webhooks a move changes to name the new type, and any it can't change.
    @ViewBuilder private var alsoChanges: some View {
        let settings = model.movePreview?.settings ?? []
        if !settings.isEmpty {
            let target = model.moveTarget.map { model.title(of: $0).localizedLowercase } ?? ""
            SettingsSection("Also Changes") {
                ForEach(Array(settings.enumerated()), id: \.offset) { _, setting in
                    SettingsRow(
                        title: Text(verbatim: Self.title(of: setting.kind)),
                        line: Text(verbatim: setting.blocked ?? Self.line(of: setting.kind, target: target)),
                        error: nil, lead: .symbol(Self.symbol(of: setting.kind)), lines: nil)
                }
            }
        }
    }

    private static func title(of kind: TypeSettingRecord.Kind) -> String {
        switch kind {
        case .folder: String(localized: "A Folder")
        case .view: String(localized: "A View")
        case .webhook: String(localized: "A Webhook")
        }
    }

    private static func line(of kind: TypeSettingRecord.Kind, target: String) -> String {
        switch kind {
        case .folder: String(localized: "Its settings will use \(target).")
        case .view: String(localized: "Its type filter will use \(target).")
        case .webhook: String(localized: "It will send events for \(target).")
        }
    }

    private static func symbol(of kind: TypeSettingRecord.Kind) -> String {
        switch kind {
        case .folder: "folder"
        case .view: "line.3.horizontal.decrease"
        case .webhook: "dot.radiowaves.up.forward"
        }
    }
}
