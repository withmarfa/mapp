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

    private var address: URL? { libraries.host.connection?.address }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                browser.showSettings(.library)
            } label: {
                Text(LibraryDescription.name(libraries))
                    .interfaceFont(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .help("Connection Settings")
            .accessibilityIdentifier("SidebarLibrary")
            if let host, host.source != nil {
                SyncStatusReading(host: host) { status in dot(for: host.state, status: status) }
            }
            Spacer(minLength: 0)
            if let address {
                iconButton("Console", symbol: "arrow.up.right.square", id: "SidebarConsole") { openURL(address) }
            }
            iconButton("Recently Deleted", symbol: "trash", id: "SidebarRecentlyDeleted") {
                browser.show(.recentlyDeleted, in: library, order: order)
            }
            iconButton("Settings", symbol: "gearshape", id: "SidebarOpenSettings") { browser.showSettings() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func dot(for state: MarfaHost.State, status: SyncStatus) -> some View {
        if let dot = SidebarStatusDot(state) {
            let detail = status.primary?.detail ?? String(localized: "Connecting to the server.")
            Circle()
                .fill(dot == .trouble ? Color.red : Color.orange)
                .frame(width: 7, height: 7)
                .help(detail)
                .accessibilityLabel(status.primary?.title ?? String(localized: "Connecting…"))
                .accessibilityHint(detail)
                .accessibilityIdentifier("SyncStatus")
        }
    }

    private func iconButton(_ title: LocalizedStringKey, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}
