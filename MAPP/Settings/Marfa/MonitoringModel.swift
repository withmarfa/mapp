import Foundation
import Observation

/// A secret the server holds and never shows: an address or a token a report is sent with. It is shown as set or not set, and
/// written only by typing the whole of it again.
nonisolated enum MonitoringSecret: String, CaseIterable, Hashable, Sendable, Identifiable {
    case heartbeatAddress, postHogHost, postHogToken, telemetryAddress, telemetryHeaders

    var id: String { rawValue }

    var key: String {
        switch self {
        case .heartbeatAddress: "heartbeat_url"
        case .postHogHost: "posthog_host"
        case .postHogToken: "posthog_project_token"
        case .telemetryAddress: "otel_exporter_otlp_endpoint"
        case .telemetryHeaders: "otel_exporter_otlp_headers"
        }
    }

    var title: String {
        switch self {
        case .heartbeatAddress, .telemetryAddress: String(localized: "Address")
        case .postHogHost: String(localized: "PostHog Host")
        case .postHogToken: String(localized: "Project Token")
        case .telemetryHeaders: String(localized: "Headers")
        }
    }

    /// What the secret is called in a sentence about removing it.
    var removalName: String {
        switch self {
        case .heartbeatAddress: String(localized: "heartbeat address")
        case .postHogHost: String(localized: "PostHog host")
        case .postHogToken: String(localized: "project token")
        case .telemetryAddress: String(localized: "telemetry address")
        case .telemetryHeaders: String(localized: "telemetry headers")
        }
    }

    /// What stops, or changes, when it is removed.
    var removalLine: String {
        switch self {
        case .heartbeatAddress: String(localized: "The server stops sending its heartbeat.")
        case .postHogHost, .postHogToken: String(localized: "The PostHog host and the project token are removed together, and error reports stop.")
        case .telemetryAddress: String(localized: "The server stops sending telemetry.")
        case .telemetryHeaders: String(localized: "Telemetry is sent without these headers.")
        }
    }

    /// What a field says that its label does not.
    var prompt: String? {
        switch self {
        case .heartbeatAddress, .postHogHost, .telemetryAddress: "https://"
        case .telemetryHeaders: "name=value"
        case .postHogToken: nil
        }
    }

    /// The secrets the server needs set together with this one.
    var partner: MonitoringSecret? {
        switch self {
        case .postHogHost: .postHogToken
        case .postHogToken: .postHogHost
        default: nil
        }
    }
}

/// The sheet that sets, changes or removes one secret. What is typed lives here only until the sheet closes or the write
/// is made: it is never handed over, kept or shown again.
struct MonitoringSecretSheet: Identifiable, Equatable {
    let secret: MonitoringSecret
    /// The secrets typed in this sheet: the one asked about, and its partner where the server needs both set together.
    let fields: [MonitoringSecret]
    var inputs: [String: String] = [:]
    var error: String?
    var id: String { secret.rawValue }

    /// Whether anything was typed.
    var hasInput: Bool { inputs.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

/// The Monitoring page: what the server sends about itself, and where. The heartbeat, the error reports and the telemetry
/// are each a switch and the addresses and tokens they use, which the server never shows, so the page says only whether each
/// is set. A change is sent at once, after a fresh read finds the setting still as it was shown.
@Observable @MainActor final class MonitoringModel {
    private let store: StoredSettings

    /// A removal waiting on the owner's answer.
    struct Question: Identifiable, Equatable {
        let id = UUID()
        let secret: MonitoringSecret
        var title: String { String(localized: "Remove the \(secret.removalName)?") }
        var message: String { secret.removalLine }
    }

    var sheet: MonitoringSecretSheet?
    var question: Question?
    /// One line under a switch or secret after a change that was not made.
    private(set) var lines: [String: String] = [:]
    /// What was told after a change found changed elsewhere; it closes when the person next edits, or is closed.
    private(set) var notice: String?
    private(set) var isWriting = false

    init(store: StoredSettings) {
        self.store = store
    }

    convenience init(context: OwnerContext, calls: any InstanceCalls) {
        self.init(store: StoredSettings(context: context, calls: calls))
    }

    var failure: OwnerFailure? { store.failure }
    var isLoaded: Bool { store.snapshot != nil }

    func load() async { await store.load() }

    // MARK: Reading

    func isOn(_ key: String) -> Bool { store.setting(key)?.value?.bool ?? false }
    func isSet(_ secret: MonitoringSecret) -> Bool { store.setting(secret.key)?.isSet ?? false }

    /// Whether the server has what it sends reports with, so a switch that is on does something.
    var heartbeatHasReceiver: Bool { isSet(.heartbeatAddress) }
    var errorReportsHaveReceiver: Bool { isSet(.postHogHost) && isSet(.postHogToken) }
    var telemetryHasReceiver: Bool { isSet(.telemetryAddress) }

    func line(_ key: String) -> String? { lines[key] }

    /// Whether the server holds the secret as one: a field that takes it is secure and never shows it again. A setting the
    /// server lists without that is typed in plain view.
    func isSecure(_ secret: MonitoringSecret) -> Bool { store.setting(secret.key)?.isSecret ?? true }

    func dismissNotice() { notice = nil }

    // MARK: Switches

    /// Turns a switch on or off. The server turns the heartbeat and the error reports on only where something receives them,
    /// so that is said here, in one line, before anything is sent.
    func setSwitch(_ key: String, _ on: Bool) async {
        guard !isWriting, isOn(key) != on else { return }
        lines[key] = nil
        notice = nil
        if on {
            if key == "heartbeat_enabled", !heartbeatHasReceiver {
                lines[key] = String(localized: "Set the address first.")
                return
            }
            if key == "error_reporting_enabled", !errorReportsHaveReceiver {
                lines[key] = String(localized: "Set the PostHog host and the project token first.")
                return
            }
        }
        await send([key: .set(.bool(on))], line: key)
    }

    // MARK: Secrets

    func begin(_ secret: MonitoringSecret) {
        notice = nil
        lines[secret.key] = nil
        let together = secret.partner.map { !isSet($0) } ?? false
        var open = MonitoringSecretSheet(secret: secret, fields: together ? [.postHogHost, .postHogToken] : [secret])
        // A setting the server does not keep secret can be read, so it is there to change.
        for field in open.fields where !isSecure(field) {
            if case .text(let text)? = store.setting(field.key)?.value { open.inputs[field.key] = text }
        }
        sheet = open
    }

    func close() {
        guard !isWriting else { return }
        sheet = nil
    }

    /// Writes what was typed. A refusal keeps the sheet and what was typed, with one line.
    func save() async {
        guard var open = sheet, open.hasInput, !isWriting else { return }
        var changes: [String: StoredSettingChange] = [:]
        for field in open.fields {
            let text = (open.inputs[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { changes[field.key] = .set(.text(text)) }
        }
        open.error = nil
        // The server takes the PostHog host and token only together, so one typed alone is told here, before anything is sent.
        if open.fields.count == 2, changes.count == 1 {
            open.error = String(localized: "Type both the host and the project token.")
            sheet = open
            return
        }
        sheet = open
        await write(changes, in: open)
    }

    // MARK: Removing

    /// Asks before a secret is removed, since it can't be read back to put it back.
    func askToRemove(_ secret: MonitoringSecret) {
        guard !isWriting else { return }
        notice = nil
        lines[secret.key] = nil
        question = Question(secret: secret)
    }

    func cancelQuestion() { question = nil }

    /// Removes the secret, and with it the one the server keeps beside it.
    func confirm(_ asked: Question) async {
        question = nil
        guard !isWriting else { return }
        var keys = [asked.secret]
        if let partner = asked.secret.partner, isSet(partner) { keys.append(partner) }
        let changes = Dictionary(uniqueKeysWithValues: keys.filter(isSet).map { ($0.key, StoredSettingChange.clear) })
        guard !changes.isEmpty else { return }
        await send(changes, line: asked.secret.key)
    }

    private func write(_ changes: [String: StoredSettingChange], in open: MonitoringSecretSheet) async {
        guard !changes.isEmpty else { return }
        isWriting = true
        defer { isWriting = false }
        notice = nil
        switch await store.write(changes) {
        case .saved:
            sheet = nil
        case .elsewhere(let moved):
            sheet = nil
            notice = StoredSettingWording.elsewhere(moved.map(Self.name))
        case .failed(let failure):
            var kept = open
            kept.error = StoredSettingWording.line(failure)
            sheet = kept
        }
    }

    private func send(_ changes: [String: StoredSettingChange], line key: String) async {
        isWriting = true
        defer { isWriting = false }
        notice = nil
        switch await store.write(changes) {
        case .saved: break
        case .elsewhere(let moved): notice = StoredSettingWording.elsewhere(moved.map(Self.name))
        case .failed(let failure): lines[key] = StoredSettingWording.line(failure)
        }
    }

    /// What the page calls a setting.
    private static func name(_ key: String) -> String {
        if let secret = MonitoringSecret.allCases.first(where: { $0.key == key }) { return secret.title }
        switch key {
        case "heartbeat_enabled": return String(localized: "Send a Heartbeat")
        case "error_reporting_enabled": return String(localized: "Report Errors")
        case "telemetry_enabled": return String(localized: "Send Telemetry")
        default: return key
        }
    }
}
