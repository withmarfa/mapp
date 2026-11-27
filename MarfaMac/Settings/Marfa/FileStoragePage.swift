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
        InstanceSettingsGate(page: .fileStorage, host: host) { catalog in
            SettingsPageColumn {
                if let notice = catalog.notice { OwnerNotice(title: "Changed Elsewhere", line: notice, close: { catalog.dismissNotice() }) }
                files(catalog)
                SettingsSection("Versions", footer: "A type can keep its own.") {
                    ForEach(InstanceSetting.versionSettings, id: \.self) { setting in
                        InstanceChoiceRow(model: model, setting: setting, among: all, catalog: catalog)
                    }
                }
                SettingsSection("Trash") {
                    InstanceChoiceRow(model: model, setting: .trashRetentionDays, among: all, catalog: catalog)
                }
                SettingsSection("Reading Files") {
                    InstanceToggleRow(model: model, setting: .enrichmentEnabled, among: all, catalog: catalog, line: "So search finds words in PDFs and documents.")
                    InstanceToggleRow(model: model, setting: .enrichmentOcrEnabled, among: all, catalog: catalog)
                    LimitField(model: catalog, limit: .largestFileRead)
                    LimitField(model: catalog, limit: .mostTextKept)
                    LimitField(model: catalog, limit: .tries)
                }
                SettingsSection("Files from the Web") {
                    if catalog.setting(LimitSetting.fetchSwitch)?.value?.bool != nil {
                        SettingsRow("Let Agents Fetch Files", line: "From a web address, or a file attached in a chat.", error: catalog.lines[LimitSetting.fetchSwitch]) {
                            SettingsToggle(title: "Let Agents Fetch Files", isOn: Binding { catalog.isOn(LimitSetting.fetchSwitch) } set: { on in
                                Task { await catalog.setSwitch(LimitSetting.fetchSwitch, on) }
                            })
                            .disabled(catalog.saving.contains(LimitSetting.fetchSwitch))
                        }
                    }
                    LimitField(model: catalog, limit: .largestFetch)
                    LimitField(model: catalog, limit: .fetchTime)
                }
                InstanceStatusLine(model: model, settings: all)
            }
        }
        .task(id: host.grants) { if host.grants.contains(.instanceRead) { await storage.load() } }
        .accessibilityIdentifier("FileStoragePage")
    }

    // MARK: Where files are

    private func files(_ catalog: LimitsModel) -> some View {
        SettingsSection("Files") {
            if !host.grants.contains(.instanceRead) {
                OwnerProblemRow(title: "File Storage Details", failure: .notPermitted(InstancePermission.instanceRead.rawValue), page: .fileStorage, host: host)
            } else if let failure = storage.failure {
                OwnerProblemRow(
                    title: "Couldn’t Read Where Files Are", failure: failure, page: .fileStorage, host: host,
                    retry: { Task { await storage.load() } })
            } else if let stores = storage.stores {
                ForEach(stores.stores) { store in storeRow(store) }
                if let bytes = storage.metrics?.databaseBytes, storage.fileBytesFailure == nil {
                    SettingsRow("Database") { SettingsValue(verbatim: Int64(bytes).formatted(.byteCount(style: .file))) }
                }
                if let failure = storage.fileBytesFailure {
                    OwnerProblemRow(
                        title: "Couldn’t Read the Total File Size", failure: failure, page: .fileStorage, host: host,
                        retry: { Task { await storage.load() } })
                }
            } else {
                SettingsRow("Reading Where Files Are…") { ProgressView().controlSize(.small) }
            }
            InstanceChoiceRow(model: model, setting: .blobMinCopies, among: all, catalog: catalog)
            InstanceNumberRow(model: model, setting: .diskReserveMegabytes, among: all, catalog: catalog, unit: "MB", line: "Uploads stop below this.")
            InstanceToggleRow(model: model, setting: .blobCleanupEnabled, among: all, catalog: catalog)
            InstanceChoiceRow(model: model, setting: .blobCleanupGraceSeconds, among: all, catalog: catalog)
            if host.grants.contains(.instanceRead) { unused }
        }
    }

    private func storeRow(_ store: FileStoreRow) -> some View {
        let title: String =
            switch store.kind {
            case .disk: String(localized: "This Marfa’s Disk")
            case .folder: String(localized: "Backup Folder")
            case .objectStore: String(localized: "Object Store")
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
                SettingsRow("No Unused Files", line: "Nothing is waiting to be removed.")
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
