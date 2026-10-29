import SwiftUI

/// The Library page of Settings, as plain grouped rows: the server in use and how it stands, each change that needs
/// the person, the key and the other server, the downloaded files.
struct LibrarySettings: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    private var host: MarfaHost { libraries.host }

    var body: some View {
        Form {
            if host.configuredConnection != nil { LibraryServer() }
            if library != nil, !host.report.problems.isEmpty {
                Section {
                    ForEach(host.report.problems) { problem in
                        SyncProblemRow(problem: problem, isOnline: host.state == .online)
                    }
                } header: {
                    Text("Problems")
                } footer: {
                    Text("Until you decide, these changes stay on this Mac.")
                }
            }
            MarfaSettingsView(model: libraries.marfaSettings)
            if let library, let files = library.downloadedFiles {
                LibraryDownloads(files: files)
                    .id(ObjectIdentifier(library))
            }
        }
        .settingsForm()
        .accessibilityIdentifier("LibrarySettings")
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
            Text("MAPP removes its copy of your library and the key from this Mac. Nothing on the server changes.")
        }
    }
}

/// The server in use as rows: its name, address, how it stands (a dot and a few words), how many items the library
/// holds and what waits to be sent, then the button that disconnects from it.
private struct LibraryServer: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library

    private var host: MarfaHost { libraries.host }

    var body: some View {
        Section("Server") {
            LabeledContent("Name") { Text(LibraryDescription.name(libraries)).textSelection(.enabled) }
            if let address = host.configuredConnection?.address.absoluteString {
                LabeledContent("Address") {
                    Text(address)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            SyncStatusReading(host: host) { status in
                standing(status)
            }
            if let library {
                LabeledContent("Items") {
                    Text(library.count(in: .allNotes), format: .number).monospacedDigit()
                }
            }
            if let waiting = host.waitingChanges, waiting > 0 {
                LabeledContent("Unsent changes") { Text(Words.changes(waiting)) }
            }
            disconnect
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("LibrarySummary")
    }

    private var disconnect: some View {
        HStack(spacing: 8) {
            Button("Disconnect…") { libraries.marfaSettings.requestDisconnect() }
                .disabled(libraries.marfaSettings.isWorking)
                .accessibilityIdentifier("MarfaDisconnect")
            if libraries.marfaSettings.isWorking { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder private func standing(_ status: SyncStatus) -> some View {
        let words = self.words(status)
        LabeledContent("Status") {
            HStack(spacing: 6) {
                Circle().fill(words.color).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(words.line)
            }
        }
        .accessibilityIdentifier("LibraryStanding")
        if let detail = words.detail {
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let fill = library?.syncReport.fill, fill.state != .complete {
            LabeledContent(fill.state == .updating ? "Updating library…" : "Downloading library…") {
                Text(FillWording.line(fill))
                    .monospacedDigit()
                    .accessibilityIdentifier("LibraryFillProgress")
            }
        }
    }

    private func words(_ status: SyncStatus) -> (line: String, detail: String?, color: Color) {
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
