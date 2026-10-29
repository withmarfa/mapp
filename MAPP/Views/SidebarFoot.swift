import SwiftUI

/// The instance at the foot of the sidebar, below its places, types and views: its name with a line under it saying
/// how the library stands with its server, a Refresh that shows while the pointer is over them, and a cog that opens
/// a menu of the Console, Settings and Recently Deleted.
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
            name: name, line: line, canRefresh: canRefresh,
            refresh: refresh,
            openConsole: address.map { address in { openURL(address) } },
            openSettings: { browser.showSettings() },
            showRecentlyDeleted: { browser.show(.recentlyDeleted, in: library, order: order) })
    }
}

/// The foot's row, given what it shows and what its menu does. Refresh is disabled where it has nothing to do, and
/// the Console while it has no address, which is until a server is set.
///
/// The controls are plain labels that dim with the window, as the sidebar's rows do. A pointer click hands the
/// keyboard back, so no focus ring stays on a control that was clicked; tabbing still reaches both. Refresh is only
/// drawn while the pointer is over the name or the keyboard is on it, but it stays in the accessibility tree.
struct SidebarFootRow: View {
    @Environment(\.appearsActive) private var appearsActive
    @FocusState private var focus: Control?
    @State private var isHovering = false
    let name: String
    /// Nil where there is no server to sync with, as in the sample library.
    let line: SyncFootLine?
    let canRefresh: Bool
    let refresh: () -> Void
    let openConsole: (() -> Void)?
    let openSettings: () -> Void
    let showRecentlyDeleted: () -> Void

    private enum Control: Hashable { case refresh, settings }

    private var tint: AnyShapeStyle { appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary) }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .interfaceFont(.body)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("SidebarLibrary")
                if let line { syncRow(line) }
            }
            .contentShape(.rect)
            .onHover { isHovering = $0 }
            Spacer(minLength: 0)
            Menu {
                Button("Console") { openConsole?() }
                    .disabled(openConsole == nil)
                Button("Settings", action: openSettings)
                Button("Recently Deleted", action: showRecentlyDeleted)
            } label: {
                Image(systemName: "gearshape")
                    .interfaceFont(.body)
                    .imageScale(.large)
                    .foregroundStyle(tint)
                    .contentShape(.rect)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .focused($focus, equals: .settings)
            .simultaneousGesture(TapGesture().onEnded { focus = nil })
            .help("Console, Settings and Recently Deleted")
            .accessibilityLabel(Text("Settings Menu"))
            .accessibilityIdentifier("SidebarSettingsMenu")
        }
        .onChange(of: appearsActive) { if !appearsActive { focus = nil } }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    /// One quiet line, a step below the name, and the small Refresh after it. Where the person has to act the line is
    /// as strong as the name.
    private func syncRow(_ line: SyncFootLine) -> some View {
        HStack(spacing: 4) {
            syncLine(line)
            if line.showsSpinner {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .interfaceFont(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canRefresh)
            .focused($focus, equals: .refresh)
            .simultaneousGesture(TapGesture().onEnded { focus = nil })
            .opacity(isHovering || focus == .refresh ? 1 : 0)
            .help("Refresh")
            .accessibilityLabel(Text("Refresh"))
            .accessibilityIdentifier("SidebarRefresh")
        }
    }

    private func syncLine(_ line: SyncFootLine) -> some View {
        let asksForAction = line.kind == .failed || line.kind == .needsAttention
        return Text(line.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .interfaceFont(.subheadline)
            .foregroundStyle(appearsActive ? AnyShapeStyle(asksForAction ? .secondary : .tertiary) : AnyShapeStyle(.quaternary))
            .help(line.help ?? "")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(line.text))
            .accessibilityHint(Text(line.help ?? ""))
            .accessibilityIdentifier("SyncStatus")
    }
}
