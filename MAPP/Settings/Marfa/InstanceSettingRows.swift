import SwiftUI

/// The choices a pop-up offers for a number the server holds: sensible steps, then the value held where it is none of them,
/// and Default, which removes the setting so the server's own default applies.
nonisolated enum InstanceChoices {
    struct Option: Hashable {
        /// Nil is Default.
        let value: Int?
        let title: String
    }

    static func options(for setting: InstanceSetting, holding current: Int?) -> [Option] {
        var steps = steps(for: setting)
        if let current, !steps.contains(current) { steps.append(current) }
        steps.sort()
        let standard = setting.documentedDefault.map { String(localized: "Default (\(title(setting, $0)))") } ?? String(localized: "Default")
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
        case .blobMinCopies: return String(value)
        case .blobCleanupGraceSeconds:
            if value == 0 { return String(localized: "Right Away") }
            if value % 86_400 == 0 { return dayTitle(value / 86_400) }
            if value % 3_600 == 0 { return value == 3_600 ? String(localized: "1 Hour") : String(localized: "\(value / 3_600) Hours") }
            return String(localized: "\(value) Seconds")
        default: return dayTitle(value)
        }
    }

    private static func dayTitle(_ days: Int) -> String {
        if days == 1 { return String(localized: "1 Day") }
        if days % 365 == 0 { return days == 365 ? String(localized: "1 Year") : String(localized: "\(days / 365) Years") }
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
/// (`instanceSettingsQuestion`), and a refusal keeps the choice with the red ring and one line.
struct InstanceChoiceRow: View {
    let model: InstanceSettingsModel
    let setting: InstanceSetting
    let among: [InstanceSetting]
    var line: LocalizedStringKey?

    private var held: Int? {
        if case .value(.number(let number)) = setting.entry(from: model.draft[setting] ?? "") { number } else { nil }
    }

    var body: some View {
        let errors = InstanceRowErrors(model: model, settings: among)
        SettingsRow(title: Text(verbatim: setting.title), line: line.map { Text($0) }, error: errors.message(for: setting)) {
            SettingsPopUp(
                title: LocalizedStringKey(setting.title),
                selection: Binding { held } set: { choice in
                    model.draft[setting] = choice.map { String($0) } ?? ""
                    Task { await model.save([setting]) }
                }
            ) {
                ForEach(InstanceChoices.options(for: setting, holding: held), id: \.self) { option in
                    Text(verbatim: option.title).tag(option.value)
                }
            }
            .disabled(model.isSaving)
            .settingsErrorRing(errors.isError(setting))
            .accessibilityIdentifier("Instance" + setting.rawValue)
        }
    }
}

/// A switch the server holds, sent at once. Where the server holds none, it shows what the server documents as its default.
struct InstanceToggleRow: View {
    let model: InstanceSettingsModel
    let setting: InstanceSetting
    let among: [InstanceSetting]
    var line: LocalizedStringKey?

    var body: some View {
        let errors = InstanceRowErrors(model: model, settings: among)
        SettingsRow(title: Text(verbatim: setting.title), line: line.map { Text($0) }, error: errors.message(for: setting)) {
            SettingsToggle(
                title: LocalizedStringKey(setting.title),
                isOn: Binding {
                    if case .value(.flag(let flag)) = setting.entry(from: model.draft[setting] ?? "") { flag } else { setting.documentedFlag }
                } set: { isOn in
                    model.draft[setting] = isOn ? "true" : "false"
                    Task { await model.save([setting]) }
                }
            )
            .disabled(model.isSaving)
            .accessibilityIdentifier("Instance" + setting.rawValue)
        }
    }
}

/// A number typed in a field with its unit inside, sent when the person presses Return or leaves the field.
struct InstanceNumberRow: View {
    let model: InstanceSettingsModel
    let setting: InstanceSetting
    let among: [InstanceSetting]
    let unit: LocalizedStringKey
    var line: LocalizedStringKey?

    var body: some View {
        let errors = InstanceRowErrors(model: model, settings: among)
        SettingsRow(title: Text(verbatim: setting.title), line: line.map { Text($0) }, error: errors.message(for: setting)) {
            SettingsNumberField(
                title: LocalizedStringKey(setting.title), text: Binding { model.draft[setting] ?? "" } set: { model.draft[setting] = $0 },
                unit: unit, prompt: setting.documentedDefault.map { String($0) }, isError: errors.isError(setting),
                onSubmit: { Task { await model.save([setting]) } }, onEndEditing: { Task { await model.save([setting]) } }
            )
            .disabled(model.isSaving)
            .accessibilityIdentifier("Instance" + setting.rawValue)
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
    /// The question before a shorter retention is sent: what it may remove, which can't be recovered. Keeping things as they
    /// were puts the fields back.
    func instanceSettingsQuestion(_ model: InstanceSettingsModel) -> some View {
        confirmationDialog(
            "Keep things for less time?", isPresented: Binding { model.pending != nil } set: { if !$0 { model.cancelPending() } },
            presenting: model.pending
        ) { pending in
            Button("Shorten and Save", role: .destructive) { model.agree(pending) }
        } message: { pending in
            Text(pending.shortenings.map(InstanceWording.consequence).joined(separator: "\n\n"))
        }
    }
}

/// A page of the server's own settings: loads them, and where they can't be shown says why instead of showing fields that
/// would not save.
struct InstanceSettingsGate<Content: View>: View {
    let host: any MarfaSettingsHost
    @ViewBuilder let content: Content

    private var model: InstanceSettingsModel { host.instanceSettings }

    var body: some View {
        Group {
            if let failure = model.failure, !model.isAvailable {
                SettingsPageState(
                    symbol: Self.symbol(for: failure), title: Text(Self.title(for: failure)), line: Text(verbatim: failure.message),
                    action: failure == .unsupported || failure == .notPermitted ? nil : ("Try Again", { Task { await model.load() } }))
            } else if !model.isAvailable {
                OwnerLoading()
            } else {
                content
            }
        }
        .task(id: host.serverAddress) { await model.load() }
        .instanceSettingsQuestion(model)
    }

    static func title(for failure: InstanceConfigFailure) -> String {
        switch failure {
        case .unsupported: String(localized: "No Server Settings")
        case .notPermitted: String(localized: "Needs a Permission")
        case .unreachable: String(localized: "Can’t Reach the Server")
        case .keyRefused: String(localized: "Signed Out")
        case .instanceChanged: String(localized: "Another Marfa Answers")
        case .refused, .failed: String(localized: "Couldn’t Read the Settings")
        }
    }

    static func symbol(for failure: InstanceConfigFailure) -> String {
        switch failure {
        case .unsupported: "gearshape"
        case .notPermitted: "lock"
        case .unreachable: "wifi.exclamationmark"
        case .keyRefused: "person.crop.circle.badge.exclamationmark"
        case .instanceChanged, .refused, .failed: "exclamationmark.triangle"
        }
    }
}
