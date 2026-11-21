import Marfa
import SwiftUI

/// The File Storage page: where the server keeps files, how it reads, fetches and cleans them up. Switches and choices are sent
/// at once, numbers when Return is pressed or the field is left.
struct FileStoragePage: View {
    let host: any MarfaSettingsHost
    @State private var storage: FileStorageModel

    init(host: any MarfaSettingsHost) {
        self.host = host
        _storage = State(initialValue: FileStorageModel(context: OwnerContext(host: host)))
    }

    private var model: InstanceSettingsModel { host.instanceSettings }
    private let all = InstanceSetting.fileSettings

    var body: some View {
        InstanceSettingsGate(page: .fileStorage, host: host) {
            SettingsPageColumn {
                whereFilesAre
                SettingsSection("Reading Files") {
                    InstanceToggleRow(model: model, setting: .enrichmentEnabled, among: all, line: "So search finds words in PDFs and documents.")
                    InstanceToggleRow(model: model, setting: .enrichmentOcrEnabled, among: all, line: "So search finds words in pictures.")
                }
                SettingsSection("Files From the Web") {
                    InstanceToggleRow(
                        model: model, setting: .mcpFetchEnabled, among: all, line: "When a chat asks \(host.serverName) to save a link.")
                    InstanceNumberRow(model: model, setting: .mcpFetchMaxMegabytes, among: all, unit: "MB")
                }
                SettingsSection("Unused Files") {
                    InstanceToggleRow(model: model, setting: .blobCleanupEnabled, among: all)
                    InstanceChoiceRow(model: model, setting: .blobCleanupGraceSeconds, among: all, line: "How long a file is left alone before it is removed.")
                    unused
                }
                InstanceStatusLine(model: model, settings: all)
            }
        }
        .task(id: host.serverAddress) { await storage.load() }
        .accessibilityIdentifier("FileStoragePage")
    }

    // MARK: Where files are

    @ViewBuilder private var whereFilesAre: some View {
        SettingsSection("Where Files Are") {
            if let stores = storage.stores {
                ForEach(stores.stores) { store in storeRow(store, in: stores) }
            } else if let failure = storage.failure {
                OwnerProblemRow(
                    title: "Couldn’t Read Where Files Are", failure: failure, page: .fileStorage, host: host,
                    retry: { Task { await storage.load() } })
            } else {
                SettingsRow("Reading Where Files Are…") { ProgressView().controlSize(.small) }
            }
            InstanceChoiceRow(model: model, setting: .blobMinCopies, among: all)
            InstanceNumberRow(model: model, setting: .diskReserveMegabytes, among: all, unit: "MB", line: "Uploads stop below this.")
        }
    }

    private func storeRow(_ store: FileStoreRow, in stores: FileStores) -> some View {
        let title: String =
            switch store.kind {
            case .disk: String(localized: "\(host.serverName)’s Disk")
            case .folder: String(localized: "Backup Folder")
            case .objectStore: String(localized: "Object Store")
            }
        return SettingsRow(
            title: Text(verbatim: title), line: store.error == nil ? Text(verbatim: store.locator) : nil, error: store.error,
            lead: .symbol(store.kind == .objectStore ? "externaldrive.connected.to.line.below" : "externaldrive")
        ) {
            if store.kind == .disk {
                if let bytes = stores.fileBytes { SettingsValue(verbatim: Int64(bytes).formatted(.byteCount(style: .file))) }
            } else {
                SettingsValue("A copy of each file")
            }
        }
    }

    // MARK: Unused files

    @ViewBuilder private var unused: some View {
        if let stores = storage.stores {
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
