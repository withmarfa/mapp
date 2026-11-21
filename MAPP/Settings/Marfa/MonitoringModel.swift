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

    var sheet: MonitoringSecretSheet?
    /// One line under a switch or secret after a change that was not made.
    private(set) var lines: [String: String] = [:]
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

    // MARK: Switches

    /// Turns a switch on or off. The server turns the heartbeat and the error reports on only where something receives them,
    /// so that is said here, in one line, before anything is sent.
    func setSwitch(_ key: String, _ on: Bool) async {
        guard !isWriting, isOn(key) != on else { return }
        lines[key] = nil
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
        let together = secret.partner.map { !isSet($0) } ?? false
        sheet = MonitoringSecretSheet(secret: secret, fields: together ? [.postHogHost, .postHogToken] : [secret])
    }

    func close() {
        guard !isWriting else { return }
        sheet = nil
    }

    /// Whether Remove is offered: the secret is set.
    func canRemove(_ sheet: MonitoringSecretSheet) -> Bool { sheet.fields.contains(where: isSet) || isSet(sheet.secret) }

    /// What removing the secret also removes, said in the sheet: the server keeps the PostHog pair together.
    func removalNote(_ sheet: MonitoringSecretSheet) -> String? {
        sheet.secret.partner != nil && isSet(sheet.secret) && isSet(sheet.secret.partner!)
            ? String(localized: "The PostHog host and the project token are removed together.") : nil
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
        sheet = open
        await write(changes, in: open)
    }

    /// Removes the secret, and with it the one the server keeps beside it.
    func remove() async {
        guard let open = sheet, !isWriting else { return }
        var keys = [open.secret]
        if let partner = open.secret.partner, isSet(partner) { keys.append(partner) }
        await write(Dictionary(uniqueKeysWithValues: keys.filter(isSet).map { ($0.key, StoredSettingChange.clear) }), in: open)
    }

    private func write(_ changes: [String: StoredSettingChange], in open: MonitoringSecretSheet) async {
        guard !changes.isEmpty else { return }
        isWriting = true
        defer { isWriting = false }
        notice = nil
        switch await store.write(changes) {
        case .saved:
            sheet = nil
        case .elsewhere:
            sheet = nil
            notice = StoredSettingWording.elsewhere
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
        case .elsewhere: notice = StoredSettingWording.elsewhere
        case .failed(let failure): lines[key] = StoredSettingWording.line(failure)
        }
    }
}
