import Marfa
import SwiftUI

/// The Types page: the owner's own types, those plugins brought and those Marfa ships, each opening a page of its own. A type
/// of the owner's changes in place (its name, plural, icon, base, description and status words); a plugin's or Marfa's takes
/// only a child type and an icon. Guidance is shown, with the guidance of the types above, and never written here.
struct TypesPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: TypesModel
    @Environment(\.settingsPush) private var push
    @Environment(\.settingsBack) private var back

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        let access = TypeAccess(
            ownItems: { [host] in host.itemCount(ofType: $0) }, currentIcon: { [host] in host.typeIcon(of: $0) },
            setIcon: { [host] icon, id in await host.changeTypeIcon(icon, ofType: id) }, markSets: host.markSets,
            marks: { [host] query, set in host.marks(matching: query, in: set) }, plural: { [host] in host.typePlural(of: $0) })
        _model = State(initialValue: TypesModel(context: OwnerContext(host: host), calls: host.typeCalls, access: access))
    }

    private func subpage(for type: TypeRecord) -> SettingsSubpage {
        SettingsSubpage(id: "type:" + type.id, title: model.title(of: type))
    }

    private var openID: String? {
        guard let id = subpage?.id, id.hasPrefix("type:") else { return nil }
        return String(id.dropFirst(5))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .onChange(of: openID, initial: true) { if let id = openID { model.open(id) } else { model.close() } }
            .onChange(of: model.hasLoaded) { if let id = openID { model.open(id) } }
            .onChange(of: model.made) {
                guard let id = model.made, let type = model.record(id) else { return }
                model.acknowledgeMade()
                push(subpage(for: type))
            }
            .settingsSheet(presenting: model.hasSheet, dismiss: { model.closeSheet() }) { TypeSheet(model: model, host: host) }
            .accessibilityIdentifier("TypesPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .types, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let id = openID {
            if let type = model.record(id) {
                TypeDetail(model: model, type: type, host: host)
            } else {
                SettingsPageState(
                    symbol: "shippingbox", title: Text("This Type Is Gone"), line: Text("It was deleted, here or somewhere else."),
                    action: ("Back", back))
            }
        } else {
            list
        }
    }

    // MARK: The list

    private var list: some View {
        SettingsPageColumn {
            SettingsSection("Yours") {
                if model.yours.isEmpty {
                    SettingsEmptyCard(symbol: "shippingbox", title: Text("No Types of Your Own"), line: Text("Base a type on one below to make your own."))
                }
                ForEach(model.yours) { row($0) }
                SettingsAddRow("New Type…") { model.beginChild(of: nil) }
            }
            if !model.fromPlugins.isEmpty {
                SettingsSection("From Plugins", line: "Their plugins keep them. Add a child type to change one.") {
                    ForEach(model.fromPlugins) { row($0) }
                }
            }
            SettingsSection("Built In", line: "Every Marfa has these. Base a type on one to add to it.") {
                ForEach(model.builtIn) { row($0) }
            }
        }
    }

    private func row(_ type: TypeRecord) -> some View {
        SettingsLinkRow(
            verbatim: model.title(of: type), line: model.subtitle(of: type), lead: .custom(host.typeMark(for: type.id)),
            value: model.count(of: type.id).formatted()
        ) { push(subpage(for: type)) }
    }
}

/// One type's page.
private struct TypeDetail: View {
    let model: TypesModel
    let type: TypeRecord
    let host: any MarfaSettingsHost

    private var isEditable: Bool { model.isEditable(type) }

    var body: some View {
        SettingsPageColumn {
            SettingsHead(lead: host.largeTypeMark(for: type.id), title: Text(verbatim: model.title(of: type)), line: Text(verbatim: model.headLine(of: type))) {
                SettingsButton("New Child Type…") { model.beginChild(of: type.id) }
            }
            if let failure = model.pageFailure { OwnerProblem(title: "Not Changed", failure: failure, page: .types, host: host) }
            typeSection
            guidanceSection
            if model.hasStatus(type.id) { statusSection }
            fieldsSection
        }
    }

    // MARK: Type

    @ViewBuilder private var typeSection: some View {
        @Bindable var model = model
        SettingsSection("Type") {
            if isEditable {
                SettingsRow("Name", error: model.fieldErrors[.name]) {
                    SettingsField(
                        title: "Name", text: $model.name, isError: model.fieldErrors[.name] != nil,
                        onSubmit: { Task { await model.commit(.name) } }, onEndEditing: { Task { await model.commit(.name) } })
                }
                SettingsRow("Plural", error: model.fieldErrors[.plural]) {
                    SettingsField(
                        title: "Plural", text: $model.plural, isError: model.fieldErrors[.plural] != nil,
                        onSubmit: { Task { await model.commit(.plural) } }, onEndEditing: { Task { await model.commit(.plural) } })
                }
                iconRow
                SettingsRow("Based On", line: "Its words and fields come from here.", error: model.fieldErrors[.basedOn]) {
                    SettingsPopUp(
                        title: "Based On", selection: Binding<String?> { type.parent } set: { parent in Task { await model.setParent(parent, of: type.id) } },
                        isError: model.fieldErrors[.basedOn] != nil
                    ) {
                        Text("Nothing").tag(String?.none)
                        Divider()
                        ForEach(model.basedOnChoices(for: type.id)) { Text(verbatim: model.title(of: $0)).tag(Optional($0.id)) }
                    }
                }
                SettingsStackRow(
                    title: Text("Description"),
                    line: Text("\(TypesModel.length(of: model.descriptionText)) of \(TypesModel.descriptionLimit) characters."),
                    error: model.fieldErrors[.description]
                ) {
                    SettingsField(
                        title: "Description", text: $model.descriptionText, isError: model.fieldErrors[.description] != nil, width: nil,
                        onSubmit: { Task { await model.commit(.description) } }, onEndEditing: { Task { await model.commit(.description) } })
                }
            } else {
                iconRow
                SettingsRow("Description") { SettingsLockedValue(text: type.description ?? String(localized: "None")) }
            }
        }
    }

    private var iconRow: some View {
        let maker = type.origin == .plugin ? String(localized: "the plugin’s") : String(localized: "Marfa’s")
        return SettingsRow(
            title: Text("Icon"), line: isEditable ? nil : Text("Yours shows in place of \(maker)."),
            lead: .custom(host.typeMark(for: type.id))
        ) {
            SettingsButton("Change…") { model.beginIcon(of: type.id) }
        }
    }

    // MARK: Guidance

    private var guidanceSection: some View {
        let reading = model.reading(of: type.id)
        let own = (reading?.guidance ?? type.guidance) ?? ""
        let ancestors = reading?.ancestors ?? []
        return SettingsSection(
            "Guidance", line: "What an agent or an app builder reads to use the type. Change it with `marfa types replace` on the command line."
        ) {
            if own.isEmpty && ancestors.isEmpty {
                SettingsRow("No Guidance", look: .off)
            }
            if !own.isEmpty {
                SettingsStackRow(
                    title: Text(type.origin == .plugin ? "From the Plugin" : "Guidance"),
                    line: isEditable ? Text("\(TypesModel.length(of: own)) of \(TypesModel.guidanceLimit) characters.") : nil
                ) { SettingsStackText(text: own, isLocked: true) }
            }
            ForEach(ancestors, id: \.type) { above in
                SettingsStackRow(title: Text("From \(model.title(of: above.type))")) { SettingsStackText(text: above.guidance, isLocked: true) }
            }
        }
    }

    // MARK: Statuses

    private var statusLine: Text {
        if isEditable {
            if let parent = type.parent, model.record(parent) != nil {
                return Text("Each word counts as one of four. Words from \(model.title(of: parent)) can’t change here.")
            }
            return Text("Each word counts as one of four.")
        }
        if type.origin == .plugin { return Text("A plugin’s type can’t change here. A child type adds words and fields.") }
        return Text("Built-in types can’t change. Base a type on \(model.title(of: type)) to add words.")
    }

    private var statusSection: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: SettingsTokens.Metric.sectionGap) {
            SettingsSection(name: Text("Statuses"), line: statusLine) {
                ForEach(TypesModel.groups, id: \.id) { group in
                    SettingsRow(title: Text(verbatim: group.title), lead: .custom(AnyView(Self.mark(of: group.id)))) {
                        SettingsWordChips(
                            words: model.words(of: type.id, in: group.id), addTitle: "Add a Word", canAdd: isEditable,
                            isAdding: model.addingGroup == group.id, draft: $model.wordDraft, isError: model.fieldErrors[.word] != nil,
                            begin: { model.beginWord(in: group.id) }, commit: { Task { await model.commitWord() } },
                            cancel: { model.cancelWord() },
                            menu: { word in
                                AnyView(Button("Edit Meaning…") { model.beginMeaning(of: word.id, in: type.id) })
                            })
                    }
                }
            }
            if let line = model.fieldErrors[.word] {
                Text(verbatim: "\(line) \(host.serverName) kept the words as they were.")
                    .settingsFont(.line).foregroundStyle(SettingsTokens.errorRed).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsTokens.Metric.inset)
            }
        }
    }

    /// The mark of a status group: an empty circle, a half circle in the accent, a filled one and a crossed one.
    private static func mark(of group: String) -> some View {
        let symbol: String =
            switch group {
            case "in_progress": "circle.lefthalf.filled"
            case "completed": "circle.inset.filled"
            case "canceled": "xmark.circle"
            default: "circle"
            }
        return Image(systemName: symbol).font(.system(size: 14))
            .foregroundStyle(group == "in_progress" ? SettingsTokens.systemAccent : SettingsTokens.secondaryText)
            .accessibilityHidden(true)
    }

    // MARK: Fields

    @ViewBuilder private var fieldsSection: some View {
        let fields = model.fields(of: type.id)
        if !fields.isEmpty {
            SettingsSection("Fields") {
                SettingsRow(
                    verbatim: String(localized: "\(fields.count) Fields"), line: Self.summary(of: fields),
                    lead: .none
                ) { SettingsLockedValue(text: source) }
            }
        }
    }

    private var source: String {
        switch type.origin {
        case .platform: String(localized: "Built In")
        case .plugin: String(localized: "From \(model.title(ofPlugin: type.plugin?.name ?? ""))")
        case .registered, .unknown: type.parent.map { String(localized: "From \(model.title(of: $0))") } ?? String(localized: "Yours")
        }
    }

    private static func summary(of fields: [TypeFieldRecord]) -> String {
        let names = fields.map { $0.label ?? TypesModel.title(ofWord: $0.key) }
        let shown = names.prefix(4)
        let rest = names.count - shown.count
        let list = shown.formatted(.list(type: .and, width: .narrow))
        return rest > 0 ? String(localized: "\(shown.joined(separator: ", ")) and \(rest) more.") : String(localized: "\(list).")
    }
}

/// The one sheet over a type's page: its icon, a new type, or what a word means.
private struct TypeSheet: View {
    let model: TypesModel
    let host: any MarfaSettingsHost

    var body: some View {
        if model.iconTarget != nil {
            iconSheet
        } else if model.isMakingChild {
            childSheet
        } else if model.meaningWord != nil {
            meaningSheet
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
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.cancelChild() }.disabled(model.isWorking)
            SettingsButton("Add") { Task { await model.makeChild() } }.disabled(!model.canMakeChild)
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
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.cancelMeaning() }.disabled(model.isSavingMeaning)
            SettingsButton("Save") { Task { await model.saveMeaning() } }.disabled(model.isSavingMeaning)
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
        } buttons: {
            SettingsButton("Use Default") { Task { await model.chooseIcon(nil) } }.disabled(model.isChangingIcon)
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.closeIcon() }.disabled(model.isChangingIcon)
        }
    }
}
