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

/// The top of the Library page: the library in use as a hero row, with its symbol, name, address, how it stands
/// (a dot and a few words) and how many items it holds. A server's row ends in the button that disconnects from it.
private struct LibrarySummary: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library

    private var host: MarfaHost { libraries.host }
    private var isServer: Bool { host.configuredConnection != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            symbol
            VStack(alignment: .leading, spacing: 3) {
                Text(LibraryDescription.name(libraries))
                    .interfaceFont(.title3.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                if let address {
                    Text(address)
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                SyncStatusReading(host: host) { status in
                    standing(status)
                }
                .padding(.top, 2)
                .accessibilityIdentifier("LibraryStanding")
            }
            Spacer(minLength: 12)
            if isServer { disconnect }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("LibrarySummary")
    }

    /// A server is its symbol in a rounded square tinted with the accent; a folder is the icon Finder gives it.
    private var symbol: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.accentColor.opacity(isServer ? 0.14 : 0.08))
            if isServer {
                Image(systemName: "server.rack")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            } else if let url = libraries.folder.url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }

    /// The full address of a server, or the path of a folder.
    private var address: String? {
        if let connection = host.configuredConnection { return connection.address.absoluteString }
        return libraries.folder.url?.path(percentEncoded: false)
    }

    private var disconnect: some View {
        HStack(spacing: 8) {
            if libraries.marfaSettings.isWorking { ProgressView().controlSize(.small) }
            Button("Disconnect") { libraries.marfaSettings.requestDisconnect() }
                .buttonStyle(.bordered)
                .disabled(libraries.marfaSettings.isWorking)
                .accessibilityIdentifier("MarfaDisconnect")
        }
    }

    @ViewBuilder private func standing(_ status: SyncStatus) -> some View {
        let words = self.words(status)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(words.color).frame(width: 7, height: 7)
                Text(words.line).foregroundStyle(.secondary)
                if let library {
                    Text("^[\(library.count(in: .allNotes)) item](inflect: true)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.leading, 10)
                }
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
