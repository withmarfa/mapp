import SwiftUI

/// The instance at the foot of the sidebar, below its places, types and views: its name with a chevron, which opens
/// a menu of Refresh, the Console, Settings and Recently Deleted, with a line under the name saying how the library
/// stands with its server; and the button that makes a new item.
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
            SyncFootReading(host: host) { line in
                row(name, line: line, canRefresh: host.canRefresh, refresh: host.refresh)
            }
        } else {
            row(name, line: nil, canRefresh: false, refresh: {})
        }
    }

    private func row(_ name: String, line: SyncFootLine?, canRefresh: Bool, refresh: @escaping () -> Void) -> some View {
        let address = libraries.host.connection?.address
        return SidebarFootRow(
            name: name, line: line, canRefresh: canRefresh, browser: browser,
            refresh: refresh,
            openConsole: address.map { address in { openURL(address) } },
            openSettings: { browser.showSettings() },
            showRecentlyDeleted: { browser.show(.recentlyDeleted, in: library, order: order) })
    }
}

/// The foot's row, given what it shows and what its menu does. Refresh is dimmed in the menu where it has nothing to
/// do, and the Console while it has no address, which is until a server is set.
///
/// Both controls are plain labels that dim with the window, as the sidebar's rows do. A pointer click hands the
/// keyboard back, so no focus ring stays on a control that was clicked; tabbing still reaches both.
struct SidebarFootRow: View {
    @Environment(\.appearsActive) private var appearsActive
    @FocusState private var focus: Control?
    let name: String
    /// Nil where there is no server to sync with, as in the sample library.
    let line: SyncFootLine?
    let canRefresh: Bool
    let browser: Browser?
    let refresh: () -> Void
    let openConsole: (() -> Void)?
    let openSettings: () -> Void
    let showRecentlyDeleted: () -> Void

    private enum Control: Hashable { case menu, newItem }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                // The system's menu, with its own indicator hidden for the chevron beside the name.
                Menu {
                    Button("Refresh", action: refresh)
                        .disabled(!canRefresh)
                    Divider()
                    Button("Console") { openConsole?() }
                        .disabled(openConsole == nil)
                    Button("Settings", action: openSettings)
                    Button("Recently Deleted", action: showRecentlyDeleted)
                } label: {
                    HStack(spacing: 4) {
                        Text(name)
                            .interfaceFont(.body)
                            .foregroundStyle(appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .interfaceFont(.caption.weight(.semibold))
                            .foregroundStyle(appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                            .fixedSize()
                    }
                    .contentShape(.rect)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .focused($focus, equals: .menu)
                .simultaneousGesture(TapGesture().onEnded { focus = nil })
                .help("Instance Menu")
                .accessibilityLabel(Text(name))
                .accessibilityHint(Text("Opens Refresh, the Console, Settings and Recently Deleted"))
                .accessibilityIdentifier("SidebarLibrary")
                if let line { syncLine(line) }
            }
            Spacer(minLength: 0)
            NewItemButton(browser: browser)
                .buttonStyle(.plain)
                .interfaceFont(.body)
                .imageScale(.large)
                .foregroundStyle(appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .focused($focus, equals: .newItem)
                .simultaneousGesture(TapGesture().onEnded { focus = nil })
        }
        .onChange(of: appearsActive) { if !appearsActive { focus = nil } }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    /// One quiet line, a step below the name. Where the person has to act it is as strong as the name.
    private func syncLine(_ line: SyncFootLine) -> some View {
        let asksForAction = line.kind == .failed || line.kind == .needsAttention
        return HStack(spacing: 4) {
            if line.showsSpinner {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            Text(line.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .interfaceFont(.subheadline)
        .foregroundStyle(appearsActive ? AnyShapeStyle(asksForAction ? .secondary : .tertiary) : AnyShapeStyle(.quaternary))
        .help(line.help ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line.text))
        .accessibilityHint(Text(line.help ?? ""))
        .accessibilityIdentifier("SyncStatus")
    }
}
