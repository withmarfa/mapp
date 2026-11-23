import Marfa
import SwiftUI

/// The Overview page: the Marfa's head card, what needs the owner's attention, its name and release, and how it stands. A part
/// the sign-in may not read is left out, and the app says so in the first row of Needs Attention, with Allow More….
struct OverviewPage: View {
    let host: any MarfaSettingsHost

    private var model: OverviewModel { host.overview }
    private var settings: InstanceSettingsModel { host.instanceSettings }
    private var canChangeSettings: Bool { host.grants.contains(.configManage) }

    var body: some View {
        content
            .task(id: host.serverAddress) {
                async let overview: Void = model.load()
                if canChangeSettings { await settings.load() }
                await overview
            }
            .accessibilityIdentifier("OverviewPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .overview, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else {
            SettingsPageColumn {
                SettingsHead(
                    symbol: MarfaSettingsPage.overview.symbol, tone: MarfaSettingsPage.overview.tone, title: Text(verbatim: host.serverName),
                    line: Text(verbatim: headLine))
                attention
                if canChangeSettings { thisMarfa }
                health
            }
        }
    }

    // MARK: Head

    private var headLine: String {
        let address = host.serverAddress.map { URL(string: $0).map(SettingsWording.hostName(of:)) ?? $0 }
        let tail: String? =
            if let owner = model.reading?.owner { String(localized: "Owned by \(owner).") }
            else if let version = model.releaseVersion { String(localized: "Marfa \(version).") }
            else { nil }
        return [address.map { $0 + "." }, tail].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: Needs attention

    private var holdsAll: Bool { host.grants.count >= InstancePermission.allCases.count }

    @ViewBuilder private var attention: some View {
        if !model.concerns.isEmpty || !holdsAll {
            SettingsSection("Needs Attention") {
                if !holdsAll { permissionsRow }
                ForEach(model.concerns) { concern in
                    SettingsProblemRow(title: Text(verbatim: concern.shownTitle), line: concern.shownLine.map { Text(verbatim: $0) }, actions: actions(for: concern))
                }
            }
        }
    }

    private var permissionsRow: some View {
        SettingsProblemRow(
            title: Text("This App Can Look After Part of \(host.serverName)"),
            line: Text("It holds \(host.grants.count) of the owner’s \(InstancePermission.allCases.count) permissions."),
            actions: [
                SettingsProblemAction("Allow More…", isPrimary: true) {
                    let host = host
                    Task { _ = await host.allowMore(Set(InstancePermission.allCases)) }
                }
            ])
            .disabled(host.isAllowingMore)
    }

    /// Only the actions that exist: a concern opens the page that looks after it, where the sign-in may open that page. A kind
    /// with no page of its own says what is wrong and offers nothing.
    private func actions(for concern: AttentionConcern) -> [SettingsProblemAction] {
        switch concern.kind {
        case .key where host.grants.contains(.keysManage):
            [SettingsProblemAction("Show Keys") { host.show(.keys) }]
        case .backup where host.grants.contains(.backupsManage):
            [SettingsProblemAction("Show Backups") { host.show(.backups) }]
        case .job, .clock:
            [SettingsProblemAction("Show Housekeeping") { host.show(.housekeeping) }]
        case .folder:
            [SettingsProblemAction("Show Folders") { host.show(.folders) }]
        case .setting where host.grants.contains(.configManage) && MonitoringSecret.named(key: concern.reference) != nil:
            [SettingsProblemAction("Show Monitoring") { host.show(.monitoring) }]
        default:
            []
        }
    }

    // MARK: This Marfa

    @ViewBuilder private var thisMarfa: some View {
        if settings.isAvailable || settings.isLoading {
            SettingsSection("This Marfa") {
                nameRow
                versionRow
            }
        } else if let failure = settings.failure {
            SettingsSection("This Marfa") {
                if failure == .notPermitted {
                    OwnerProblemRow(
                        title: "Couldn’t Read \(host.serverName)’s Settings", failure: .notPermitted(InstancePermission.configManage.rawValue),
                        page: .overview, host: host)
                } else {
                    SettingsProblemRow(
                        title: Text("Couldn’t Read \(host.serverName)’s Settings"), line: Text(verbatim: failure.message),
                        actions: failure == .unsupported ? [] : [SettingsProblemAction("Try Again") { Task { await settings.load() } }])
                }
            }
        }
    }

    private var nameRow: some View {
        let errors = InstanceRowErrors(model: settings, settings: [.name])
        let text = Binding { settings.draft[.name] ?? "" } set: { settings.draft[.name] = $0 }
        return VStack(alignment: .leading, spacing: 0) {
            SettingsRow("Name", line: "What apps and the sign-in page show.", error: errors.message(for: .name)) {
                SettingsField(
                    title: "Name", text: text, prompt: String(localized: "Marfa"), isError: errors.isError(.name),
                    onSubmit: { Task { await settings.save([.name]) } }, onEndEditing: { Task { await settings.save([.name]) } }
                )
                .disabled(settings.isSaving)
                .accessibilityIdentifier("ThisMarfaName")
            }
            InstanceStatusLine(model: settings, settings: [.name])
        }
    }

    /// The release and, where one is ready, the update; a development build has no release, so only the update line shows.
    @ViewBuilder private var versionRow: some View {
        if let version = model.releaseVersion {
            SettingsRow(title: Text("Marfa \(version)"), line: model.reading?.updateReady.map { Text("Marfa \($0) is ready.") }) { showUpdates }
        } else if let ready = model.reading?.updateReady {
            SettingsRow(title: Text("Marfa \(ready) is ready")) { showUpdates }
        }
    }

    // MARK: Health

    private var health: some View {
        SettingsSection("Health") {
            let database = model.health(of: .database)
            SettingsRow("Database") {
                SettingsValue(verbatim: bytes(model.reading?.databaseBytes) ?? Self.word(database.condition), dot: Self.dot(database.condition))
            }
            let disk = model.health(of: .disk)
            SettingsRow("Disk") {
                SettingsValue(verbatim: Self.word(disk.condition), dot: Self.dot(disk.condition))
            }
            filesRow(model.health(of: .files))
            let backups = model.backups
            if host.grants.contains(.backupsManage) {
                SettingsLinkRow(
                    verbatim: String(localized: "Backups"), value: Self.backupsWord(backups), dot: Self.dot(backups)
                ) { host.show(.backups) }
            } else {
                SettingsRow("Backups") {
                    SettingsValue(verbatim: Self.backupsWord(backups), dot: Self.dot(backups))
                }
            }
        }
    }

    @ViewBuilder private func filesRow(_ files: HealthPart) -> some View {
        let value = bytes(model.reading?.fileBytes).map { String(localized: "\($0) on its disk") } ?? Self.word(files.condition)
        if host.grants.contains(.configManage) {
            SettingsLinkRow(
                verbatim: String(localized: "Files"), value: value, dot: Self.dot(files.condition)
            ) { host.show(.fileStorage) }
        } else {
            SettingsRow("Files") {
                SettingsValue(verbatim: value, dot: Self.dot(files.condition))
            }
        }
    }

    /// Update beside the release, where one is ready: it opens Updates, where the update is started and followed.
    @ViewBuilder private var showUpdates: some View {
        if model.reading?.updateReady != nil {
            SettingsButton("Show Updates") { host.show(.updates) }
        }
    }

    private func bytes(_ count: Int?) -> String? {
        count.map { Int64($0).formatted(.byteCount(style: .file)) }
    }

    static func word(_ condition: Condition) -> String {
        switch condition {
        case .ok: String(localized: "Working")
        case .degraded: String(localized: "Needs Attention")
        case .down: String(localized: "Not Working")
        case .unknown: String(localized: "Couldn’t Check")
        }
    }

    static func dot(_ condition: Condition) -> Color {
        switch condition {
        case .ok: SettingsTokens.ok
        case .degraded, .unknown: SettingsTokens.warning
        case .down: SettingsTokens.errorRed
        }
    }

    static func dot(_ backups: BackupsHealth) -> Color {
        switch backups.state {
        case .ok: SettingsTokens.ok
        case .incomplete, .off, .unknown: SettingsTokens.warning
        case .failing: SettingsTokens.errorRed
        }
    }

    static func backupsWord(_ backups: BackupsHealth, now: Date = .now, calendar: Calendar = .current) -> String {
        switch backups.state {
        case .off: return String(localized: "Off")
        case .unknown: return String(localized: "Couldn’t Check")
        case .failing: return String(localized: "Failing")
        case .incomplete: return String(localized: "Incomplete")
        case .ok:
            guard let last = backups.lastBackup else { return String(localized: "Working") }
            let time = last.formatted(date: .omitted, time: .shortened)
            return calendar.isDate(last, inSameDayAs: now) ? String(localized: "Last at \(time)") : String(localized: "Last \(OwnerWording.day(last, now: now, calendar: calendar))")
        }
    }
}
