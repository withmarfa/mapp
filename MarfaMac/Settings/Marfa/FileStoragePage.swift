import Marfa
import SwiftUI

/// The Storage page: where the server keeps files, how it reads, fetches and cleans them up. Switches and choices are sent
/// at once, numbers when Return is pressed or the field is left.
struct FileStoragePage: View {
    let host: any MarfaSettingsHost
    @State private var storage: FileStorageModel

    init(host: any MarfaSettingsHost) {
        self.host = host
        _storage = State(initialValue: FileStorageModel(context: OwnerContext(host: host)))
    }

    private var model: InstanceSettingsModel { host.instanceSettings }
    private let all = InstanceSetting.fileSettings + InstanceSetting.versionSettings + [.trashRetentionDays]

    var body: some View {
        Group {
            if host.grants.contains(.configManage) {
                InstanceSettingsGate(page: .fileStorage, host: host) { catalog in content(catalog) }
            } else {
                content(nil)
            }
        }
        .task(id: host.grants) { if host.grants.contains(.instanceRead) { await storage.load() } }
        .accessibilityIdentifier("FileStoragePage")
    }

    private func content(_ catalog: LimitsModel?) -> some View {
        SettingsPageColumn {
            if let catalog, let notice = catalog.notice { OwnerNotice(title: "Changed Elsewhere", line: notice, close: { catalog.dismissNotice() }) }
            files(catalog)
            SettingsSection("Versions", footer: "A type can keep its own.") {
                ForEach(InstanceSetting.versionSettings, id: \.self) { setting in
                    choice(setting, catalog)
                }
            }
            SettingsSection("Trash") {
                choice(.trashRetentionDays, catalog)
            }
            SettingsSection("Reading Files") {
                toggle(.enrichmentEnabled, catalog, line: "So search finds words in PDFs and documents.")
                toggle(.enrichmentOcrEnabled, catalog)
                field(.largestFileRead, catalog)
                field(.mostTextKept, catalog)
                field(.tries, catalog)
            }
            SettingsSection("Files from the Web") {
                if let catalog, catalog.setting(LimitSetting.fetchSwitch)?.value?.bool != nil {
                    SettingsRow("Let agents fetch files", line: "From a web address, or a file attached in a chat.", error: catalog.lines[LimitSetting.fetchSwitch]) {
                        SettingsToggle(title: "Let agents fetch files", isOn: Binding { catalog.isOn(LimitSetting.fetchSwitch) } set: { on in
                            Task { await catalog.setSwitch(LimitSetting.fetchSwitch, on) }
                        })
                        .disabled(catalog.saving.contains(LimitSetting.fetchSwitch))
                    }
                } else if catalog == nil {
                    locked(InstanceSetting.mcpFetchEnabled.title)
                }
                field(.largestFetch, catalog)
                field(.fetchTime, catalog)
            }
            if catalog != nil { InstanceStatusLine(model: model, settings: all) }
        }
    }

    private func locked(_ title: String) -> some View {
        LockedInstanceRow(title: title, permission: .configManage, host: host)
    }

    @ViewBuilder private func choice(_ setting: InstanceSetting, _ catalog: LimitsModel?) -> some View {
        if let catalog { InstanceChoiceRow(model: model, setting: setting, among: all, catalog: catalog) }
        else { locked(setting.title) }
    }

    @ViewBuilder private func toggle(_ setting: InstanceSetting, _ catalog: LimitsModel?, line: LocalizedStringKey? = nil) -> some View {
        if let catalog { InstanceToggleRow(model: model, setting: setting, among: all, catalog: catalog, line: line) }
        else { locked(setting.title) }
    }

    @ViewBuilder private func field(_ limit: LimitSetting, _ catalog: LimitsModel?) -> some View {
        if let catalog { LimitField(model: catalog, limit: limit) }
        else { locked(limit.title) }
    }

    // MARK: Where files are

    private func files(_ catalog: LimitsModel?) -> some View {
        SettingsSection("Files") {
            if !host.grants.contains(.instanceRead) {
                LockedInstanceRow(title: String(localized: "File storage details"), permission: .instanceRead, host: host)
            } else if let failure = storage.failure {
                OwnerProblemRow(
                    title: "Couldn’t read where files are", failure: failure, page: .fileStorage, host: host,
                    retry: { Task { await storage.load() } })
            } else if let stores = storage.stores {
                ForEach(stores.stores) { store in storeRow(store) }
                if let bytes = storage.metrics?.databaseBytes, storage.fileBytesFailure == nil {
                    SettingsRow("Database") { SettingsValue(verbatim: Int64(bytes).formatted(.byteCount(style: .file))) }
                }
                if let failure = storage.fileBytesFailure {
                    OwnerProblemRow(
                        title: "Couldn’t read the total file size", failure: failure, page: .fileStorage, host: host,
                        retry: { Task { await storage.load() } })
                }
            } else {
                SettingsRow("Reading where files are…") { ProgressView().controlSize(.small) }
            }
            choice(.blobMinCopies, catalog)
            if let catalog {
                InstanceNumberRow(model: model, setting: .diskReserveMegabytes, among: all, catalog: catalog, unit: "MB", line: "Uploads stop below this.")
            } else { locked(InstanceSetting.diskReserveMegabytes.title) }
            toggle(.blobCleanupEnabled, catalog)
            choice(.blobCleanupGraceSeconds, catalog)
            if host.grants.contains(.instanceRead) { unused }
        }
    }

    private func storeRow(_ store: FileStoreRow) -> some View {
        let title: String =
            switch store.kind {
            case .disk: String(localized: "This Marfa’s disk")
            case .folder: String(localized: "Backup folder")
            case .objectStore: String(localized: "Object store")
            }
        return SettingsRow(
            title: Text(verbatim: title), line: store.error == nil ? Text(verbatim: store.locator) : nil,
            lineGlyph: store.kind == .objectStore ? .link : .folder, error: store.error
        ) {
            if store.kind == .disk {
                if let bytes = storage.fileBytes, storage.fileBytesFailure == nil { SettingsValue(verbatim: Int64(bytes).formatted(.byteCount(style: .file))) }
            } else {
                SettingsValue("A copy of each file")
            }
        }
    }

    // MARK: Unused files

    @ViewBuilder private var unused: some View {
        if storage.failure == nil, let stores = storage.stores {
            if stores.orphanCount == 0 {
                SettingsRow("No unused files", line: "Nothing is waiting to be removed.")
            } else {
                let size = Int64(stores.orphanBytes).formatted(.byteCount(style: .file))
                let more = stores.orphansComplete ? "" : "+"
                SettingsRow(
                    title: Text("\(stores.orphanCount.formatted())\(more) files nothing uses"),
                    line: Text(verbatim: [size, Self.found(stores.firstFound)].compactMap { $0 }.joined(separator: ". ") + "."))
            }
        }
    }

    static func found(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String? {
        date.map { String(localized: "Found \(OwnerWording.day($0, now: now, calendar: calendar))") }
    }
}
