import Marfa
import SwiftUI

/// One type's page.
struct TypeDetail: View {
    let model: TypesModel
    let type: TypeRecord
    let host: any MarfaSettingsHost

    @Environment(\.settingsNavigation) private var navigation

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
        @Bindable var model = model
        let reading = model.reading(of: type.id)
        let failure = model.readingFailure(of: type.id)
        let own = (reading?.guidance ?? type.guidance) ?? ""
        let ancestors = reading?.ancestors ?? []
        return SettingsSection("Guidance", line: "What an agent or an app builder reads to use the type.") {
            if let failure {
                OwnerProblemRow(title: "Couldn’t Read This Type’s Guidance", failure: failure, page: .types, host: host) {
                    Task { await model.loadReading(of: type.id) }
                }
            }
            if isEditable {
                SettingsStackRow(
                    title: Text("Guidance"),
                    line: Text("\(TypesModel.length(of: model.guidanceText)) of \(TypesModel.guidanceLimit) characters. Markdown works."),
                    error: model.guidanceNeedsCommand ? String(localized: "This Marfa takes guidance only from the command line for now. Your text is kept here.") : model.fieldErrors[.guidance]
                ) {
                    SettingsTextArea(
                        title: "Guidance", text: $model.guidanceText,
                        isError: model.guidanceNeedsCommand || model.fieldErrors[.guidance] != nil,
                        onEndEditing: { Task { await model.commit(.guidance) } })
                }
                if model.guidanceNeedsCommand {
                    let command = TypesModel.guidanceCommand(for: type.id)
                    SettingsRow(verbatim: command, line: String(localized: "Save the text as \(type.id).md beside \(type.id).json."), lines: nil) {
                        SettingsButton(model.copiedCommand == command ? "Copied" : "Copy") { model.copyGuidanceCommand(command) }
                    }
                }
            } else if own.isEmpty && ancestors.isEmpty {
                if failure == nil { SettingsRow("No Guidance", look: .off) }
            } else if !own.isEmpty {
                SettingsStackRow(title: Text(type.origin == .plugin ? "From the Plugin" : "Guidance")) {
                    SettingsStackText(text: own, isLocked: true, isMarkdown: true)
                }
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
                        navigation?.push(SettingsSubpage(id: "field:\(type.id):\(field.key)", title: TypesModel.title(of: field)))
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
