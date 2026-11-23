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

    private func subpage(for field: TypeFieldRecord, of type: TypeRecord) -> SettingsSubpage {
        SettingsSubpage(id: "field:\(type.id):\(field.key)", title: TypesModel.title(of: field))
    }

    /// The type a sub-page is about, and the field it opens when it is a field's page.
    private var place: (type: String, field: String?)? {
        guard let id = subpage?.id else { return nil }
        if id.hasPrefix("type:") { return (String(id.dropFirst(5)), nil) }
        if id.hasPrefix("field:") {
            let parts = id.dropFirst(6).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        return nil
    }

    private var openID: String? { place?.type }
    private var openFieldKey: String? { place?.field }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .onChange(of: subpage, initial: true) { openPlace() }
            .onChange(of: model.hasLoaded) { openPlace() }
            .onChange(of: model.deleted) {
                guard model.deleted != nil else { return }
                model.acknowledgeDeleted()
                back()
            }
            .onChange(of: model.made) {
                guard let id = model.made, let type = model.record(id) else { return }
                model.acknowledgeMade()
                push(subpage(for: type))
            }
            .settingsSheet(presenting: model.hasSheet, dismiss: { model.closeSheet() }) { TypeSheet(model: model, host: host) }
            .accessibilityIdentifier("TypesPage")
    }

    private func openPlace() {
        guard let id = openID else { return model.close() }
        if let key = openFieldKey { model.openField(key, of: id) } else {
            model.open(id)
            model.closeField()
        }
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .types, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let id = openID {
            if let type = model.record(id) {
                if let key = openFieldKey {
                    if let field = model.ownField(key, of: id) {
                        FieldDetail(model: model, type: type, field: field, host: host)
                    } else {
                        SettingsPageState(
                            symbol: "textformat", title: Text("This Field Is Gone"), line: Text("It was removed, here or somewhere else."),
                            action: ("Back", back))
                    }
                } else {
                    TypeDetail(model: model, type: type, host: host)
                }
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

    @Environment(\.settingsPush) private var push

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
            if isEditable {
                feedSection
                historySection
                deleteSection
            }
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
                SettingsStackRow(title: Text("Description")) { SettingsStackText(text: type.description ?? String(localized: "None"), isLocked: true) }
            }
        }
    }

    private var iconRow: some View {
        let maker = type.origin == .plugin ? String(localized: "the plugin’s") : String(localized: "Marfa’s")
        return SettingsRow(title: Text("Icon"), line: isEditable ? nil : Text("Yours shows in place of \(maker).")) {
            HStack(spacing: SettingsTokens.Metric.dotGap) {
                host.typeMark(for: type.id)
                SettingsButton("Change…") { model.beginIcon(of: type.id) }
            }
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
                ) { SettingsStackText(text: own, isLocked: true, isMarkdown: true) }
            }
            ForEach(ancestors, id: \.type) { above in
                SettingsStackRow(title: Text("From \(model.title(of: above.type))")) { SettingsStackText(text: above.guidance, isLocked: true, isMarkdown: true) }
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
                Text("\(line) \(host.serverName) kept the words as they were.")
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
        return Image(systemName: symbol).font(.system(size: SettingsTokens.Metric.statusMark))
            .foregroundStyle(group == "in_progress" ? SettingsTokens.systemAccent : SettingsTokens.secondaryText)
            .accessibilityHidden(true)
    }

    // MARK: Fields

    @ViewBuilder private var fieldsSection: some View {
        let inherited = model.inheritedFields(of: type.id)
        let own = model.ownFields(of: type.id)
        if !inherited.isEmpty || isEditable {
            SettingsSection("Fields") {
                if !inherited.isEmpty {
                    SettingsRow(
                        verbatim: String(AttributedString(localized: "^[\(inherited.count) Field](inflect: true) From \(parentTitle ?? source)").characters),
                        line: Self.summary(of: inherited), lead: .none
                    ) { SettingsLockedValue(text: source) }
                }
                ForEach(own, id: \.key) { field in
                    SettingsLinkRow(verbatim: TypesModel.title(of: field), line: model.line(of: field)) {
                        push(SettingsSubpage(id: "field:\(type.id):\(field.key)", title: TypesModel.title(of: field)))
                    }
                }
                if isEditable { SettingsAddRow("Add a Field…") { model.beginField() } }
            }
        }
    }

    // MARK: Rules

    private var parentTitle: String? { type.parent.flatMap { model.record($0) }.map { model.title(of: $0) } }

    private var feedSection: some View {
        SettingsSection("Feed") {
            SettingsRow(
                "Move Feed Items to Recently Deleted After", error: model.fieldErrors[.feed]
            ) {
                SettingsPopUp(
                    title: "Move Feed Items to Recently Deleted After",
                    selection: Binding<FeedWindow?> { model.feedSelection(of: type.id) } set: { window in
                        Task { await model.setFeedWindow(window, of: type.id) }
                    }, isError: model.fieldErrors[.feed] != nil
                ) {
                    if let parentTitle { Text("As \(parentTitle)").tag(FeedWindow?.none) }
                    ForEach(model.feedWindows(for: type.id), id: \.self) { window in
                        Text(verbatim: Self.title(of: window)).tag(Optional(window))
                    }
                }
            }
        }
    }

    private static func title(of window: FeedWindow) -> String {
        switch window {
        case .never: String(localized: "Never")
        case .days(let days): String(localized: "\(days) Days")
        }
    }

    private var historySection: some View {
        SettingsSection("History") {
            SettingsRow("When Two Edits Meet", error: model.fieldErrors[.merge]) {
                SettingsPopUp(
                    title: "When Two Edits Meet",
                    selection: Binding<String?> { model.mergeSelection(of: type.id) } set: { name in
                        Task { await model.setMergeStrategy(name, of: type.id) }
                    }, isError: model.fieldErrors[.merge] != nil
                ) {
                    if let parentTitle { Text("As \(parentTitle)").tag(String?.none) }
                    Text("Later Edit Wins").tag(Optional("last_writer_wins"))
                    Text("Keep Both Copies").tag(Optional("keep_both_copies"))
                }
            }
        }
    }

    // MARK: Delete

    private var deleteLine: String {
        let name = model.title(of: type)
        let below = model.children(of: type.id)
        if !below.isEmpty { return String(localized: "Types are based on \(name). Change or delete those first.") }
        let items = model.ownItemCount(of: type.id)
        if items > 0 { return String(AttributedString(localized: "It holds ^[\(items) item](inflect: true). Move them to another type first.").characters) }
        return String(localized: "No item in your library holds it.")
    }

    private var deleteSection: some View {
        SettingsSection("Delete") {
            SettingsRow(
                title: Text("Delete \(model.title(of: type))"), line: model.deleteFailure == nil ? Text(verbatim: deleteLine) : nil,
                error: model.deleteFailure, lines: nil
            ) {
                SettingsButton("Delete Type…", role: .destructive) { askToDelete() }.disabled(model.isDeleting)
            }
        }
    }

    private func askToDelete() {
        let name = model.title(of: type)
        SettingsAlert.confirm(
            title: String(localized: "Delete \(name)?"),
            message: String(localized: "\(host.serverName) deletes a type only while no item holds it and no type is based on it. Deleting can’t be undone."),
            confirm: String(localized: "Delete Type"), window: NSApp.keyWindow
        ) { confirmed, _ in
            guard confirmed else { return }
            Task { await model.deleteType() }
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

/// One field's page: what it means, its kind, the rules an owner sets and removing it. A field a type above gives has no
/// page of its own: it is that type's to change.
private struct FieldDetail: View {
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

/// The one sheet over a type's page: its icon, a new type, or what a word means.
private struct TypeSheet: View {
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
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.cancelField() }.disabled(model.isWorking)
            SettingsButton("Add") { Task { await model.makeField() } }.disabled(!model.canMakeField)
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
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.cancelRename() }.disabled(model.isWorking)
            SettingsButton("Save") { Task { await model.commitRename() } }.disabled(model.isWorking)
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
