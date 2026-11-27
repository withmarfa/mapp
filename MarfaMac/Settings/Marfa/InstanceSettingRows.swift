import Marfa
import SwiftUI

/// The choices a pop-up offers for a number the server holds: sensible steps, then the value held where it is none of them,
/// and Default, which removes the setting so the server's own default applies.
nonisolated enum InstanceChoices {
    struct Option: Hashable {
        /// Nil is Default.
        let value: Int?
        let title: String
    }

    static func options(for setting: InstanceSetting, holding current: Int?, defaultValue: Int?) -> [Option] {
        var steps = steps(for: setting)
        if setting.isNumber {
            steps = Array(Set(steps + [setting.range.lowerBound, setting.range.upperBound]))
        }
        if let current, !steps.contains(current) { steps.append(current) }
        steps.sort()
        let standard = defaultValue.map { String(localized: "Default (\(title(setting, $0)))") } ?? String(localized: "Default")
        return [Option(value: nil, title: standard)] + steps.map { Option(value: $0, title: title(setting, $0)) }
    }

    private static func steps(for setting: InstanceSetting) -> [Int] {
        switch setting {
        case .versionMaxVersions: return [50, 100, 250, 500, 1000]
        case .blobMinCopies: return [1, 2, 3]
        case .blobCleanupGraceSeconds: return [0, 3_600, 86_400, 259_200, 604_800, 2_592_000]
        default:
            let days = [7, 14, 30, 60, 90, 180, 365, 730]
            return setting.zeroMeansNoLimit ? [0] + days : days
        }
    }

    /// A step as a pop-up says it: "30 Days", "1 Year", "500 Versions", "No Limit".
    static func title(_ setting: InstanceSetting, _ value: Int) -> String {
        if setting.zeroMeansNoLimit && value == 0 { return String(localized: "No Limit") }
        switch setting {
        case .versionMaxVersions: return value == 1 ? String(localized: "1 Version") : String(localized: "\(value) Versions")
        case .blobMinCopies: return value == 1 ? String(localized: "1 Copy") : String(localized: "\(value) Copies")
        case .blobCleanupGraceSeconds:
            if value == 0 { return String(localized: "Next Sweep") }
            if value % 86_400 == 0 { return dayTitle(value / 86_400) }
            if value % 3_600 == 0 { return value == 3_600 ? String(localized: "1 Hour") : String(localized: "\(value / 3_600) Hours") }
            return String(localized: "\(value) Seconds")
        default: return dayTitle(value)
        }
    }

    private static func dayTitle(_ days: Int) -> String {
        if days == 1 { return String(localized: "1 Day") }
        if days > 0 && days % 365 == 0 { return days == 365 ? String(localized: "1 Year") : String(localized: "\(days / 365) Years") }
        return String(localized: "\(days) Days")
    }
}

/// What a row says is wrong with one of a page's settings: what was typed that can't be sent, or the server's refusal, when
/// only that setting was changed. With several changed the refusal is told once under the page's rows.
@MainActor struct InstanceRowErrors {
    let model: InstanceSettingsModel
    let settings: [InstanceSetting]

    var refusal: String? {
        if case .refused(let reason)? = model.failure { reason } else { nil }
    }

    private var refusedSetting: InstanceSetting? {
        let edited = settings.filter(model.isEdited)
        return refusal != nil && edited.count == 1 ? edited.first : nil
    }

    func message(for setting: InstanceSetting) -> String? {
        model.problems[setting]?.message ?? (setting == refusedSetting ? refusal : nil)
    }

    func isError(_ setting: InstanceSetting) -> Bool {
        model.problems[setting] != nil || (refusal != nil && model.isEdited(setting))
    }
}

/// A number the server holds, chosen from a pop-up and sent at once. A shorter retention asks first
/// through the confirmation shared by the retention settings.
struct InstanceChoiceRow: View {
    let model: InstanceSettingsModel
    let setting: InstanceSetting
    let among: [InstanceSetting]
    let catalog: LimitsModel
    var line: LocalizedStringKey?

    private var standard: Int? { catalog.setting(setting.serverKey)?.defaultValue?.int }
    private var shown: Int? { model.loaded?.number(setting) ?? standard }

    var body: some View {
        let errors = InstanceRowErrors(model: model, settings: among)
        if catalog.setting(setting.serverKey)?.value != nil {
            SettingsRow(title: Text(verbatim: setting.title), line: line.map { Text($0) }, error: errors.message(for: setting)) {
                SettingsPopUp(
                    title: LocalizedStringKey(setting.title),
                    selection: Binding { shown } set: { choice in
                        Task { await model.choose(choice, for: setting, defaultValue: standard) }
                    }
                ) {
                    ForEach(InstanceChoices.options(for: setting, holding: shown, defaultValue: standard), id: \.self) { option in
                        Text(verbatim: option.title).tag(option.value)
                    }
                }
                .disabled(model.isSaving || model.pending != nil)
                .settingsErrorRing(errors.isError(setting))
                .accessibilityIdentifier("Instance" + setting.rawValue)
            }
        }
    }
}

/// A stored switch, with the default reported by the connected server.
struct InstanceToggleRow: View {
    let model: InstanceSettingsModel
    let setting: InstanceSetting
    let among: [InstanceSetting]
    let catalog: LimitsModel
    var line: LocalizedStringKey?

    var body: some View {
        let errors = InstanceRowErrors(model: model, settings: among)
        if catalog.setting(setting.serverKey)?.value != nil {
            SettingsRow(title: Text(verbatim: setting.title), line: line.map { Text($0) }, error: errors.message(for: setting)) {
                SettingsToggle(
                    title: LocalizedStringKey(setting.title),
                    isOn: Binding {
                        if case .value(.flag(let flag)) = setting.entry(from: model.draft[setting] ?? "") { flag } else { catalog.setting(setting.serverKey)?.defaultValue?.bool == true }
                    } set: { isOn in
                        model.draft[setting] = isOn ? "true" : "false"
                        Task { await model.save([setting], revertsOnFailure: true) }
                    }
                )
                .disabled(model.isSaving)
                .accessibilityIdentifier("Instance" + setting.rawValue)
            }
        }
    }
}

/// A number sent when the person presses Return or leaves the field.
struct InstanceNumberRow: View {
    let model: InstanceSettingsModel
    let setting: InstanceSetting
    let among: [InstanceSetting]
    let catalog: LimitsModel
    let unit: LocalizedStringKey
    var line: LocalizedStringKey?

    var body: some View {
        let errors = InstanceRowErrors(model: model, settings: among)
        if catalog.setting(setting.serverKey)?.value != nil {
            SettingsRow(title: Text(verbatim: setting.title), line: line.map { Text($0) }, error: errors.message(for: setting)) {
                SettingsNumberField(
                    title: LocalizedStringKey(setting.title), text: Binding { model.draft[setting] ?? "" } set: { model.draft[setting] = $0 },
                    unit: unit, prompt: catalog.setting(setting.serverKey)?.defaultValue?.int.map { String($0 / InstanceSetting.bytesPerMegabyte) }, isError: errors.isError(setting),
                    onSubmit: { Task { await model.save([setting], revertsOnFailure: true) } }, onEndEditing: { Task { await model.save([setting], revertsOnFailure: true) } }
                )
                .disabled(model.isSaving)
                .accessibilityIdentifier("Instance" + setting.rawValue)
            }
        }
    }
}

/// What the last save did, or what is wrong now, in one line under a page's rows. Nothing where all is well.
struct InstanceStatusLine: View {
    let model: InstanceSettingsModel
    let settings: [InstanceSetting]

    var body: some View {
        if let message = text {
            Text(verbatim: message.text)
                .settingsFont(.line)
                .foregroundStyle(message.isError ? SettingsTokens.errorRed : SettingsTokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, SettingsTokens.Metric.inset)
                .accessibilityIdentifier("InstanceStatus")
        }
    }

    private var text: (text: String, isError: Bool)? {
        if let elsewhere = model.elsewhereMessage { return (elsewhere, false) }
        if model.serverChanged { return (InstanceConfigFailure.instanceChanged.message, false) }
        guard let failure = model.failure else { return nil }
        if case .refused = failure, settings.filter(model.isEdited).count == 1 { return nil }
        return (failure.message, true)
    }
}

extension View {
    /// The question before a shorter retention or a smaller reserve of free disk is sent: what it may remove or leave the server
    /// without, which can't be recovered. Keeping things as they were puts the fields back.
    func instanceSettingsQuestion(_ model: InstanceSettingsModel) -> some View {
        confirmationDialog(
            model.pending.map(InstanceSettingsQuestion.title) ?? "", isPresented: Binding { model.pending != nil } set: { if !$0 { model.cancelPending() } },
            presenting: model.pending
        ) { pending in
            Button(InstanceSettingsQuestion.button(pending), role: .destructive) { model.agree(pending) }
        } message: { pending in
            Text(pending.shortenings.map(InstanceWording.consequence).joined(separator: "\n\n"))
        }
    }
}

/// The words of the question, which say what is being lowered.
enum InstanceSettingsQuestion {
    private static func onlyReserve(_ pending: InstanceSettingsModel.Pending) -> Bool {
        pending.shortenings.allSatisfy { $0.setting == .diskReserveMegabytes }
    }

    static func title(_ pending: InstanceSettingsModel.Pending) -> String {
        onlyReserve(pending) ? String(localized: "Keep less free on disk?") : String(localized: "Keep things for less time?")
    }

    static func button(_ pending: InstanceSettingsModel.Pending) -> String {
        onlyReserve(pending) ? String(localized: "Lower and Save") : String(localized: "Shorten and Save")
    }
}

/// A page of the server's own settings: loads them, and where they can't be shown says why instead of showing fields that
/// would not save.
struct InstanceSettingsGate<Content: View>: View {
    /// The page the gate stands in, which words what the app isn't allowed to do there.
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost
    let content: (LimitsModel) -> Content
    @State private var catalog: LimitsModel

    init(page: MarfaSettingsPage, host: any MarfaSettingsHost, @ViewBuilder content: @escaping (LimitsModel) -> Content) {
        self.page = page
        self.host = host
        self.content = content
        _catalog = State(initialValue: LimitsModel(context: OwnerContext(host: host), calls: host.instanceCalls))
    }

    private var model: InstanceSettingsModel { host.instanceSettings }

    var body: some View {
        Group {
            if let failure = model.failure, !model.isAvailable {
                OwnerFailureState(page: page, failure: OwnerFailure(failure), host: host) { Task { await model.load() } }
            } else if let failure = catalog.failure {
                OwnerFailureState(page: page, failure: failure, host: host) { Task { await catalog.load() } }
            } else if !model.isAvailable || !catalog.isLoaded {
                OwnerLoading()
            } else {
                content(catalog)
            }
        }
        .task(id: host.serverAddress) {
            async let settings: Void = model.load()
            await catalog.load()
            await settings
        }
        .onAppear { host.ownerDrafts.register(catalog) }
        .onDisappear { host.ownerDrafts.pageLeft(catalog) }
        .onChange(of: model.failure) { _, failure in
            if failure == .notPermitted { Task { await host.refreshGrants() } }
        }
        .instanceSettingsQuestion(model)
    }
}

struct LockedInstanceRow: View {
    let title: String
    let permission: InstancePermission
    let host: any MarfaSettingsHost

    var body: some View {
        SettingsLinkRow(verbatim: title, lock: String(localized: "Not allowed")) {
            host.askForMore(naming: permission.rawValue)
        }
        .disabled(host.isAllowingMore)
    }
}
