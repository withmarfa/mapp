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
                headButton
            }
            if let failure = model.pageFailure { OwnerProblem(title: "Not Changed", failure: failure, page: .types, host: host) }
            typeSection
            guidanceSection
            if model.hasStatus(type.id) { statusSection }
            fieldsSection
            if isEditable {
                if model.strictTypes != nil { rulesSection }
                feedSection
                historySection
                deleteSection
            }
        }
    }

    /// The owner's type opens its items in the app where the app can and it has any; Marfa's and a plugin's make a type based
    /// on them.
    @ViewBuilder private var headButton: some View {
        switch type.origin {
        case .registered, .unknown:
            if let openInApp = host.openInApp, model.count(of: type.id) > 0 {
                SettingsButton(verbatim: String(localized: "Show \(model.count(of: type.id).formatted()) \(model.title(of: type))")) { openInApp(type.id) }
            }
        case .platform:
            SettingsButton(verbatim: String(localized: "New Type Based on \(model.title(of: type))…")) { model.beginChild(of: type.id) }
        case .plugin:
            SettingsButton("New Child Type…") { model.beginChild(of: type.id) }
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
                guidanceRows
            } else {
                iconRow
                let description = type.description ?? String(localized: "None")
                if description.count <= 48 {
                    SettingsRow("Description") { SettingsLockedValue(text: description) }
                } else {
                    SettingsStackRow(title: Text("Description")) { SettingsStackText(text: description, isLocked: true) }
                }
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

    /// The owner's own guidance, in the Type section: what an agent or an app builder reads to use the type.
    @ViewBuilder private var guidanceRows: some View {
        @Bindable var model = model
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
    }

    /// The guidance a plugin's or Marfa's type gives, and the guidance of the types above, read only. Shown only where there
    /// is some, or where it couldn't be read.
    @ViewBuilder private var guidanceSection: some View {
        let reading = model.reading(of: type.id)
        let failure = model.readingFailure(of: type.id)
        let own = isEditable ? "" : (reading?.guidance ?? type.guidance) ?? ""
        let ancestors = reading?.ancestors ?? []
        if failure != nil || !own.isEmpty || !ancestors.isEmpty {
            SettingsSection("Guidance", line: "What an agent or an app builder reads to use the type.") {
                if let failure {
                    OwnerProblemRow(title: "Couldn’t Read This Type’s Guidance", failure: failure, page: .types, host: host) {
                        Task { await model.loadReading(of: type.id) }
                    }
                }
                if !own.isEmpty {
                    SettingsStackRow(title: Text(type.origin == .plugin ? "From the Plugin" : "Guidance")) {
                        SettingsStackText(text: own, isLocked: true, isMarkdown: true)
                    }
                }
                ForEach(ancestors, id: \.type) { above in
                    SettingsStackRow(title: Text("From \(model.title(of: above.type))")) { SettingsStackText(text: above.guidance, isLocked: true, isMarkdown: true) }
                }
            }
        }
    }

    // MARK: Statuses

    private var statusLine: Text? {
        if model.fieldErrors[.word] != nil { return nil }
        if let group = model.addingGroup, case let value = TypesModel.value(ofTyped: model.wordDraft), !value.isEmpty {
            let title = TypesModel.groups.first { $0.id == group }?.title ?? ""
            return Text("Return adds “\(TypesModel.title(ofWord: value))” as \(title).")
        }
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
                        verbatim: isEditable && parentTitle != nil
                            ? String(AttributedString(localized: "^[\(inherited.count) Field](inflect: true) From \(parentTitle ?? "")").characters)
                            : String(AttributedString(localized: "^[\(inherited.count) Field](inflect: true)").characters),
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

    /// Strict mode holds for the type named and not for the types based on it (`types/strict-mode`).
    private var rulesSection: some View {
        SettingsSection("Rules") {
            SettingsRow(
                title: Text("Strict"), line: Text("Reject fields this type doesn’t declare or inherit."), error: model.fieldErrors[.strict]
            ) {
                SettingsToggle(
                    title: "Strict", isOn: Binding { model.isStrict(type.id) } set: { isOn in Task { await model.setStrict(isOn, of: type.id) } })
            }
        }
    }

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

    /// Sends the choice. The model reads again how long versions stay just before sending, and a change that can delete
    /// versions, which can't be recovered, asks first, naming how long they stay now and after.
    private func setVersions(_ window: VersionWindow?) {
        let id = type.id
        let items = model.title(of: type).localizedLowercase
        let server = host.serverName
        Task { await model.setVersionWindow(window, of: id) { await Self.confirm($0, items: items, server: server) } }
    }

    private static func confirm(_ change: TypesModel.VersionChange, items: String, server: String) async -> Bool {
        let title: String
        if let days = change.new.uniformDays {
            title = String(localized: "Keep Versions for \(Self.title(of: VersionWindow.days(days)))?")
        } else {
            title = String(localized: "Change How Long Versions Are Kept?")
        }
        let now = describe(change.now)
        let new = describe(change.new)
        let message = String(localized: "Versions of \(items) are kept \(now) now, and would be kept \(new). The next time \(server) thins versions, it can permanently delete the ones this no longer keeps. Each item keeps its newest saved version. Items with two or fewer saved versions keep them all. Types based on \(items) may also lose versions.")
        return await withCheckedContinuation { continuation in
            SettingsAlert.confirm(title: title, message: message, confirm: String(localized: "Change"), window: NSApp.keyWindow) { confirmed, _ in
                continuation.resume(returning: confirmed)
            }
        }
    }

    /// How long versions stay, as a phrase after "kept".
    private static func describe(_ keeping: VersionKeeping) -> String {
        guard let recent = keeping.recent, let daily = keeping.daily, let weekly = keeping.weekly else {
            return String(localized: "as This Marfa’s History settings say")
        }
        let length = { (days: Int) in Self.title(of: VersionWindow.days(days)).localizedLowercase }
        if let days = keeping.uniformDays { return String(localized: "for \(length(days))") }
        let weeks = weekly == 0 ? String(localized: "one a week after that") : String(localized: "one a week for \(length(weekly))")
        return String(localized: "every version for \(length(recent)), one a day for \(length(daily)) and \(weeks)")
    }

    private static func title(of window: VersionWindow) -> String {
        switch window {
        case .days(let days):
            if days % 365 == 0 { days == 365 ? String(localized: "1 Year") : String(localized: "\(days / 365) Years") }
            else { days == 1 ? String(localized: "1 Day") : String(localized: "\(days) Days") }
        case .custom: String(localized: "Custom")
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
            SettingsRow("Keep Versions", error: model.fieldErrors[.versions]) {
                SettingsPopUp(
                    title: "Keep Versions",
                    selection: Binding<VersionWindow?> { model.versionSelection(of: type.id) } set: { setVersions($0) },
                    isError: model.fieldErrors[.versions] != nil
                ) {
                    if model.versionsComeFromAbove(type.id), let parentTitle {
                        Text("As \(parentTitle)").tag(VersionWindow?.none)
                    } else {
                        Text("As in History").tag(VersionWindow?.none)
                    }
                    ForEach(model.versionDays(for: type.id), id: \.self) { days in
                        Text(verbatim: Self.title(of: VersionWindow.days(days))).tag(Optional(VersionWindow.days(days)))
                    }
                    if model.versionSelection(of: type.id) == .custom { Text("Custom").tag(Optional(VersionWindow.custom)) }
                }
            }
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
        if items == 1 { return String(localized: "Its 1 item moves to another type first.") }
        if items > 1 { return String(localized: "Its \(items.formatted()) items move to another type first.") }
        return String(localized: "No item in your library holds it.")
    }

    private var deleteSection: some View {
        SettingsSection("Delete") {
            SettingsRow(
                title: Text("Delete \(model.title(of: type))"), line: model.deleteFailure == nil ? Text(verbatim: deleteLine) : nil,
                error: model.deleteFailure, lines: nil
            ) {
                SettingsButton("Delete Type…", role: .destructive) {
                    if model.ownItemCount(of: type.id) > 0 { model.beginDelete() } else { askToDelete() }
                }.disabled(model.isDeleting)
            }
        }
    }

    private func askToDelete() {
        let name = model.title(of: type)
        SettingsAlert.confirm(
            title: String(localized: "Delete \(name)?"),
            message: String(localized: "\(host.serverName) checks whether any items, settings, or other types still use \(name). If nothing uses it, deleting it can’t be undone."),
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
