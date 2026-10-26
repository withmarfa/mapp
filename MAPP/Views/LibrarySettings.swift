import SwiftUI

/// The Library page of Settings: the library in use and how it stands, the server's web console and Recently
/// Deleted, then the connection to a Marfa server, then each change that needs the person.
struct LibrarySettings: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @Environment(\.openURL) private var openURL
    @StoredOrder private var order
    let browser: Browser

    private var host: MarfaHost { libraries.host }

    var body: some View {
        Form {
            Section { LibrarySummary() }
            places
            MarfaSettingsView(model: libraries.marfaSettings)
            if let library, let files = library.downloadedFiles {
                LibraryDownloads(files: files)
                    .id(ObjectIdentifier(library))
            }
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

extension LibrarySettings {
    /// What the library holds beyond the window: the server's own console in the browser, and the items deleted
    /// from it.
    @ViewBuilder private var places: some View {
        let address = host.connection?.address
        if address != nil || library != nil {
            Section {
                if let address {
                    LabeledContent {
                        Button("Open Console") { openURL(address) }
                            .accessibilityIdentifier("LibraryOpenConsole")
                    } label: {
                        Text("Console")
                        Text("Manage this server in your browser.")
                    }
                }
                if let library {
                    LabeledContent {
                        Button("Show") { browser.show(.recentlyDeleted, in: library, order: order) }
                            .accessibilityIdentifier("LibraryShowRecentlyDeleted")
                    } label: {
                        Text("Recently Deleted")
                        Text("Restore deleted items, or delete them permanently.")
                    }
                }
            }
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

    /// A server is its symbol in a rounded square tinted with the accent, fainter while none is set.
    private var symbol: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.accentColor.opacity(isServer ? 0.14 : 0.08))
            Image(systemName: "server.rack")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }

    /// The full address of the server.
    private var address: String? {
        host.configuredConnection?.address.absoluteString
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
            if let fill = library?.syncReport.fill, fill.state != .complete {
                Text(fill.state == .updating ? "Updating library…" : "Downloading library…")
                    .foregroundStyle(.secondary)
                Text(FillWording.line(fill))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("LibraryFillProgress")
            }
        }
    }

    private func words(_ status: SyncStatus) -> (line: String, detail: String?, color: Color) {
        guard isServer else { return (String(localized: "Not connected"), nil, .secondary) }
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
