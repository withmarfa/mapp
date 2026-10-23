import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Library page of Settings: where the notes are kept and how that stands, then the connection to a Marfa
/// server, then each change that needs the person.
struct LibrarySettings: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @State private var isChoosing = false

    private var host: MarfaHost { libraries.host }
    private var folder: NotesFolder { libraries.folder }

    var body: some View {
        Form {
            Section { LibrarySummary() }
            if libraries.mode == .files { folderSection }
            MarfaSettingsView(model: libraries.marfaSettings)
            if library != nil, !host.report.problems.isEmpty {
                Section {
                    ForEach(host.report.problems) { problem in
                        SyncProblemRow(problem: problem, isOnline: host.state == .online)
                    }
                } header: {
                    Text("Problems")
                } footer: {
                    Text("These changes need you. Until you decide, they stay on this Mac.")
                }
            }
        }
        .settingsForm()
        .accessibilityIdentifier("LibrarySettings")
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            // Open notes hand over their last edits to the folder they came from before it is changed.
            if case .success(let url) = result { EditorController.flushAll { kept in if kept { folder.choose(url) } } }
        }
        // A question about changes that wait is put again when Settings is next opened, not answered by leaving.
        .onDisappear { libraries.marfaSettings.cancelDeparture() }
        .sheet(item: Binding { libraries.marfaSettings.departure } set: { if $0 == nil, !libraries.marfaSettings.isWorking { libraries.marfaSettings.cancelDeparture() } }) { departure in
            DepartureSheet(model: libraries.marfaSettings, departure: departure)
                // A step already under way cannot be called off by closing the sheet.
                .interactiveDismissDisabled(libraries.marfaSettings.isWorking)
        }
        .confirmationDialog("Disconnect from this server?", isPresented: Bindable(libraries.marfaSettings).isConfirmingDisconnect) {
            Button("Disconnect", role: .destructive) { Task { await libraries.marfaSettings.disconnect() } }
        } message: {
            Text("MAPP removes its copy of your library and the key from this Mac. Nothing on the server changes. Your notes folder is used again.")
        }
    }

    private var folderSection: some View {
        Section {
            if let url = folder.url {
                LabeledContent("Folder") {
                    Text(url.path(percentEncoded: false))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Choose Another Folder…") { isChoosing = true }
                }
            } else {
                Button("Choose Folder…") { isChoosing = true }
            }
        } header: {
            Text("Notes Folder")
        } footer: {
            Text("Connecting to a Marfa server below reads its library instead. This folder is used again if you disconnect.")
        }
    }
}

/// The top of the Library page: the library in use, with a dot and a few words for how it stands.
private struct LibrarySummary: View {
    @Environment(Libraries.self) private var libraries

    private var host: MarfaHost { libraries.host }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isServer ? "server.rack" : "folder")
                .interfaceFont(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LibraryDescription.name(libraries))
                    .interfaceFont(.headline)
                    .textSelection(.enabled)
                SyncStatusReading(host: host) { status in
                    standing(status)
                }
                .accessibilityIdentifier("LibraryStanding")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("LibrarySummary")
    }

    private var isServer: Bool { libraries.host.configuredConnection != nil }

    @ViewBuilder private func standing(_ status: SyncStatus) -> some View {
        let words = self.words(status)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(words.color).frame(width: 7, height: 7)
                Text(words.line).foregroundStyle(.secondary)
            }
            if let detail = words.detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func words(_ status: SyncStatus) -> (line: String, detail: String?, color: Color) {
        guard isServer else {
            return libraries.folder.url == nil
                ? (String(localized: "No folder chosen"), nil, .secondary)
                : (String(localized: "Reading notes from this folder"), nil, .green)
        }
        let connection = ConnectionStatus(host.state)
        if let note = status.primary {
            return (note.line, connection.detail ?? note.detail, note.dotColor)
        }
        switch host.state {
        case .online: return (String(localized: "Connected, up to date"), nil, .green)
        default: return (connection.title, connection.detail, connection.isProblem ? .red : .secondary)
        }
    }
}
