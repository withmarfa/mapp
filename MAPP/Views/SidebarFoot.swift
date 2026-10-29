import SwiftUI

/// The instance at the foot of the sidebar, below its places, types and views: its name with a line under it saying
/// how the library stands with its server, a Refresh that shows while the pointer is over them, and a cog that opens
/// Settings.
struct SidebarFoot: View {
    @Environment(Libraries.self) private var libraries
    @Environment(MarfaHost.self) private var host: MarfaHost?
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
        SidebarFootRow(
            name: name, line: line, canRefresh: canRefresh,
            refresh: refresh,
            openSettings: { browser.showSettings() })
    }
}

/// The foot's row, given what it shows and what its controls do. Refresh is disabled where it has nothing to do.
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
    let openSettings: () -> Void

    private enum Control: Hashable { case refresh, settings }

    /// The name in the primary label color and the quieter parts in the secondary one; all step back with the window.
    private var nameStyle: AnyShapeStyle { appearsActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary) }
    private var tint: AnyShapeStyle { appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary) }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .interfaceFont(.body)
                    .foregroundStyle(nameStyle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("SidebarLibrary")
                if let line { syncRow(line) }
            }
            .contentShape(.rect)
            .onHover { isHovering = $0 }
            Spacer(minLength: 0)
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .interfaceFont(.body)
                    .imageScale(.large)
                    .foregroundStyle(tint)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .focused($focus, equals: .settings)
            .simultaneousGesture(TapGesture().onEnded { focus = nil })
            .help("Settings")
            .accessibilityLabel(Text("Settings"))
            .accessibilityIdentifier("SidebarSettings")
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
            .foregroundStyle(asksForAction ? nameStyle : tint)
            .help(line.help ?? "")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(line.text))
            .accessibilityHint(Text(line.help ?? ""))
            .accessibilityIdentifier("SyncStatus")
    }
}
