import SwiftUI

/// The instance at the foot of the sidebar, below its places, types and views: its name, a dot where the server is
/// not reached, and the buttons for the Console, Recently Deleted and Settings. A click on the name opens the page of
/// Settings that holds the server's connection.
struct SidebarFoot: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(MarfaHost.self) private var host: MarfaHost?
    @Environment(\.openURL) private var openURL
    @StoredOrder private var order
    let browser: Browser

    var body: some View {
        let name = LibraryDescription.name(libraries)
        let address = libraries.host.connection?.address
        if let host, host.source != nil {
            SyncStatusReading(host: host) { status in
                row(name, address, dot: SidebarStatusDot(host.state), status: status)
            }
        } else {
            row(name, address, dot: nil, status: nil)
        }
    }

    private func row(_ name: String, _ address: URL?, dot: SidebarStatusDot?, status: SyncStatus?) -> some View {
        SidebarFootRow(
            name: name, dot: dot, status: status, hasConsole: address != nil,
            openConnection: { browser.showSettings(.library) },
            openConsole: { if let address { openURL(address) } },
            openRecentlyDeleted: { browser.show(.recentlyDeleted, in: library, order: order) },
            openSettings: { browser.showSettings() })
    }
}

/// The foot's row, given what it shows and what its buttons do.
struct SidebarFootRow: View {
    let name: String
    let dot: SidebarStatusDot?
    let status: SyncStatus?
    let hasConsole: Bool
    let openConnection: () -> Void
    let openConsole: () -> Void
    let openRecentlyDeleted: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(action: openConnection) {
                Text(name)
                    .interfaceFont(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .help("Connection Settings")
            .accessibilityIdentifier("SidebarLibrary")
            if let dot { statusDot(dot) }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if hasConsole {
                    iconButton("Console", symbol: "person.crop.circle", id: "SidebarConsole", action: openConsole)
                }
                iconButton("Settings", symbol: "gearshape", id: "SidebarOpenSettings", action: openSettings)
                iconButton("Recently Deleted", symbol: "trash", id: "SidebarRecentlyDeleted", action: openRecentlyDeleted)
            }
        }
        // The buttons' frames are wider than their symbols, so the trailing edge is shorter to line the last
        // symbol up with the rows' counts.
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func statusDot(_ dot: SidebarStatusDot) -> some View {
        let detail = status?.primary?.detail ?? String(localized: "Connecting to the server.")
        return Circle()
            .fill(dot == .trouble ? Color.red : Color.orange)
            .frame(width: 7, height: 7)
            .help(detail)
            .accessibilityLabel(status?.primary?.title ?? String(localized: "Connecting…"))
            .accessibilityHint(detail)
            .accessibilityIdentifier("SyncStatus")
    }

    private func iconButton(_ title: LocalizedStringKey, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // The size of the sidebar rows' symbols, which a sidebar list draws large.
            Image(systemName: symbol)
                .interfaceFont(.body)
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24, alignment: .center)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}
