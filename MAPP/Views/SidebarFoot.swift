import SwiftUI

/// The instance at the foot of the sidebar, below its places, types and views: its name with a chevron, which opens
/// a menu of the Console, Settings and Recently Deleted; a dot where the server is not reached; and the button that
/// makes a new item.
struct SidebarFoot: View {
    @Environment(Libraries.self) private var libraries
    @Environment(MarfaHost.self) private var host: MarfaHost?
    @CurrentLibrary private var library
    @Environment(\.openURL) private var openURL
    @StoredOrder private var order
    let browser: Browser

    var body: some View {
        let name = LibraryDescription.name(libraries)
        if let host, host.source != nil {
            SyncStatusReading(host: host) { status in
                row(name, dot: SidebarStatusDot(host.state), status: status)
            }
        } else {
            row(name, dot: nil, status: nil)
        }
    }

    private func row(_ name: String, dot: SidebarStatusDot?, status: SyncStatus?) -> some View {
        let address = libraries.host.connection?.address
        return SidebarFootRow(
            name: name, dot: dot, status: status, browser: browser,
            openConsole: address.map { address in { openURL(address) } },
            openSettings: { browser.showSettings() },
            showRecentlyDeleted: { browser.show(.recentlyDeleted, in: library, order: order) })
    }
}

/// The foot's row, given what it shows and what its menu does. The Console is dimmed in the menu while it has no
/// address, which is until a server is set.
struct SidebarFootRow: View {
    let name: String
    let dot: SidebarStatusDot?
    let status: SyncStatus?
    let browser: Browser?
    let openConsole: (() -> Void)?
    let openSettings: () -> Void
    let showRecentlyDeleted: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // The system's menu, with its own indicator hidden for the chevron beside the name.
            Menu {
                Button("Console") { openConsole?() }
                    .disabled(openConsole == nil)
                Button("Settings", action: openSettings)
                Button("Recently Deleted", action: showRecentlyDeleted)
            } label: {
                HStack(spacing: 4) {
                    Text(name)
                        .interfaceFont(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .interfaceFont(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .contentShape(.rect)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help("Instance Menu")
            .accessibilityLabel(Text(name))
            .accessibilityHint(Text("Opens the Console, Settings and Recently Deleted"))
            .accessibilityIdentifier("SidebarLibrary")
            if let dot { statusDot(dot) }
            Spacer(minLength: 0)
            NewItemButton(browser: browser)
                .buttonStyle(.borderless)
                .interfaceFont(.body)
                .imageScale(.large)
                .foregroundStyle(.secondary)
        }
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
}
