import Marfa
import SwiftUI

/// The Overview page: the Marfa's head card, what needs the owner's attention, its name and release, and how it stands. A part
/// the sign-in may not read is left out, and MAPP says so in the first row of Needs Attention, with Allow More….
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
            OwnerFailureState(failure: failure, host: host) { Task { await model.load() } }
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
            else if let version = model.reading?.version { String(localized: "Marfa \(version).") }
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
                    SettingsProblemRow(title: Text(verbatim: concern.title), line: Text(verbatim: concern.description), actions: actions(for: concern))
                }
            }
        }
    }

    private var permissionsRow: some View {
        SettingsProblemRow(
            title: Text("MAPP can look after part of \(host.serverName)"),
            line: Text("It holds \(host.grants.count) of the owner’s \(InstancePermission.allCases.count) permissions."), tone: .orange,
            actions: [
                SettingsProblemAction("Allow More…", isPrimary: true) {
                    let host = host
                    Task { _ = await host.allowMore(Set(InstancePermission.allCases)) }
                }
            ])
            .disabled(host.isAllowingMore)
    }

    /// Only the actions that exist: a key opens the Keys page where the sign-in may manage keys. The pages for the other
    /// kinds of concern are not here yet, so those rows say what is wrong and offer nothing.
    private func actions(for concern: AttentionConcern) -> [SettingsProblemAction] {
        switch concern.kind {
        case .key where host.grants.contains(.keysManage):
            [SettingsProblemAction("Show Keys") { host.show(.keys) }]
        default:
            []
        }
    }

    // MARK: This Marfa

    @ViewBuilder private var thisMarfa: some View {
        if settings.isAvailable || settings.isLoading {
            SettingsSection("This Marfa") {
                nameRow
                if let version = model.reading?.version { versionRow(version) }
            }
        } else if let failure = settings.failure {
            SettingsSection("This Marfa") {
                SettingsProblemRow(
                    title: Text("Couldn’t Read This Marfa’s Settings"), line: Text(verbatim: failure.message),
                    actions: failure == .unsupported || failure == .notPermitted ? [] : [SettingsProblemAction("Try Again") { Task { await settings.load() } }])
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

    private func versionRow(_ version: String) -> some View {
        SettingsRow(
            title: Text("Marfa \(version)"),
            line: model.reading?.updateReady.map { Text("\($0) is ready.") })
    }

    // MARK: Health

    private var health: some View {
        SettingsSection("Health") {
            let database = model.health(of: .database)
            SettingsRow(title: Text("Database"), line: database.note.map { Text(verbatim: $0) }, lines: nil) {
                SettingsValue(verbatim: bytes(model.reading?.databaseBytes) ?? Self.word(database.condition), dot: Self.dot(database.condition))
            }
            let disk = model.health(of: .disk)
            SettingsRow(title: Text("Disk"), line: disk.note.map { Text(verbatim: $0) }, lines: nil) {
                SettingsValue(verbatim: Self.word(disk.condition), dot: Self.dot(disk.condition))
            }
            filesRow(model.health(of: .files))
            let backups = model.backups
            SettingsRow(title: Text("Backups"), line: backups.reason.map { Text(verbatim: $0) }, lines: nil) {
                SettingsValue(verbatim: Self.backupsWord(backups), dot: Self.dot(backups))
            }
        }
    }

    @ViewBuilder private func filesRow(_ files: HealthPart) -> some View {
        let value = bytes(model.reading?.fileBytes).map { String(localized: "\($0) in files") } ?? Self.word(files.condition)
        if host.grants.contains(.configManage) {
            SettingsLinkRow(
                verbatim: String(localized: "Files"), line: files.note, value: value, dot: Self.dot(files.condition)
            ) { host.show(.fileStorage) }
        } else {
            SettingsRow(title: Text("Files"), line: files.note.map { Text(verbatim: $0) }, lines: nil) {
                SettingsValue(verbatim: value, dot: Self.dot(files.condition))
            }
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
        }
    }

    static func dot(_ condition: Condition) -> Color {
        switch condition {
        case .ok: SettingsTokens.ok
        case .degraded: SettingsTokens.warning
        case .down: SettingsTokens.errorRed
        }
    }

    static func dot(_ backups: BackupsHealth) -> Color {
        switch backups.state {
        case .ok: SettingsTokens.ok
        case .incomplete, .off: SettingsTokens.warning
        case .failing: SettingsTokens.errorRed
        }
    }

    static func backupsWord(_ backups: BackupsHealth, now: Date = .now, calendar: Calendar = .current) -> String {
        switch backups.state {
        case .off: return String(localized: "Off")
        case .failing: return String(localized: "Failing")
        case .incomplete: return String(localized: "Incomplete")
        case .ok:
            guard let last = backups.lastBackup else { return String(localized: "Working") }
            let time = last.formatted(date: .omitted, time: .shortened)
            return calendar.isDate(last, inSameDayAs: now) ? String(localized: "Last at \(time)") : String(localized: "Last \(OwnerWording.day(last, now: now, calendar: calendar))")
        }
    }
}
