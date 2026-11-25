import SwiftUI

/// The Marfa at the foot of the sidebar, below its places, types and views: its name with a line under it saying how
/// the library stands with its server, a Refresh that shows while the pointer is over the row, and a cog that opens
/// Settings. The row opens the Marfa's panel (`MarfaPanel`); a line that asks the person to act opens Problems in
/// Settings instead.
struct SidebarFoot: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(MarfaHost.self) private var host: MarfaHost?
    @State private var showsPanel = false
    let browser: Browser
    let order: ItemOrder

    var body: some View {
        let name = LibraryDescription.name(libraries)
        if let host, host.source != nil {
            SyncFootReading(host: host) { line in
                row(name, line: line, canRefresh: host.canRefresh, refresh: host.refresh, host: host)
            }
        } else {
            row(name, line: nil, canRefresh: false, refresh: {}, host: nil)
        }
    }

    private func row(_ name: String, line: SyncFootLine?, canRefresh: Bool, refresh: @escaping () -> Void, host: MarfaHost?) -> some View {
        SidebarFootRow(
            name: name, line: line, canRefresh: canRefresh, isPanelOpen: showsPanel,
            refresh: refresh,
            openPanel: host == nil ? nil : { showsPanel.toggle() },
            openProblems: { browser.showSettings(.connection) },
            openSettings: { browser.showSettings() })
        .popover(isPresented: $showsPanel, arrowEdge: .top) {
            if let host { panel(name, host: host) }
        }
    }

    private func panel(_ name: String, host: MarfaHost) -> some View {
        let address = host.configuredConnection.map { SettingsWording.hostName(of: $0.address) } ?? ""
        return MarfaPanel(
            content: MarfaPanelContent(library: library, name: name, address: address),
            lastSynced: host.hasServer ? host.lastSynced : nil,
            open: { place in
                showsPanel = false
                browser.show(PlaceView(place), in: library, order: order)
            },
            addMarfa: {
                showsPanel = false
                browser.showSettings(.connection)
            })
    }
}

/// The foot's row, given what it shows and what its controls do. Refresh is disabled where it has nothing to do.
///
/// The whole row is a button that opens the Marfa's panel, with a soft fill under the pointer. The name and the line sit
/// over it and let a click through; Refresh, the cog and a line that asks for action are buttons of their own. They are
/// plain labels that dim with the window, as the sidebar's rows do. A pointer click hands the keyboard back, so no focus
/// ring stays on a control that was clicked; tabbing still reaches each. Refresh is only drawn while the pointer is over
/// the row or the keyboard is on it, but it stays in the accessibility tree.
struct SidebarFootRow: View {
    @Environment(\.appearsActive) private var appearsActive
    @FocusState private var focus: Control?
    @State private var isHovering = false
    let name: String
    /// Nil where the Marfa has nothing to say of itself.
    let line: SyncFootLine?
    let canRefresh: Bool
    /// The panel is open, so the row keeps its fill.
    let isPanelOpen: Bool
    let refresh: () -> Void
    /// Nil where there is no panel to open.
    let openPanel: (() -> Void)?
    let openProblems: () -> Void
    let openSettings: () -> Void

    private enum Control: Hashable { case row, refresh, problems, settings }

    /// The name in the primary label color and the quieter parts in the secondary one; all step back with the window.
    private var nameStyle: AnyShapeStyle { appearsActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary) }
    private var tint: AnyShapeStyle { appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary) }

    var body: some View {
        ZStack {
            Button(action: { openPanel?() }) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.primary.opacity(isHovering || isPanelOpen ? 0.055 : 0))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(openPanel == nil)
            .focused($focus, equals: .row)
            .simultaneousGesture(TapGesture().onEnded { focus = nil })
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityHint(Text("Shows the Marfa’s latest updates."))
            .accessibilityIdentifier("SidebarMarfa")
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name)
                        .interfaceFont(.body.weight(.medium))
                        .foregroundStyle(nameStyle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    if let line { syncRow(line) }
                }
                Spacer(minLength: 0)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .interfaceFont(.body)
                        .imageScale(.large)
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focused($focus, equals: .settings)
                .simultaneousGesture(TapGesture().onEnded { focus = nil })
                .help(Self.settingsHelp(Bundle.main.infoDictionary))
                .accessibilityLabel(Text("Settings"))
                .accessibilityIdentifier("SidebarSettings")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
        }
        .frame(height: 48)
        .onHover { isHovering = $0 }
        .onChange(of: appearsActive) { if !appearsActive { focus = nil } }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    /// Names the build as well, so a person can quote it in feedback from where they are.
    static func settingsHelp(_ info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return String(localized: "Settings (\(version), build \(build))")
    }

    /// One quiet line, a step below the name, and the small Refresh after it. Where the person has to act the line is
    /// as strong as the name, after a warning mark, and opens Problems in Settings.
    private func syncRow(_ line: SyncFootLine) -> some View {
        HStack(spacing: 4) {
            if line.asksForAction {
                Button(action: openProblems) { syncLine(line) }
                    .buttonStyle(.plain)
                    .focused($focus, equals: .problems)
                    .simultaneousGesture(TapGesture().onEnded { focus = nil })
                    .help(line.help ?? "")
            } else {
                syncLine(line).allowsHitTesting(false)
            }
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
            .accessibilityHidden(false)
            .help("Refresh")
            .accessibilityLabel(Text("Refresh"))
            .accessibilityIdentifier("SidebarRefresh")
        }
    }

    private func syncLine(_ line: SyncFootLine) -> some View {
        HStack(spacing: 4) {
            if line.asksForAction {
                Image(systemName: "exclamationmark.triangle")
                    .interfaceFont(.callout)
                    .accessibilityHidden(true)
            }
            Text(line.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .interfaceFont(.callout)
        .foregroundStyle(line.asksForAction ? nameStyle : tint)
        .help(line.help ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line.text))
        .accessibilityHint(Text(line.help ?? ""))
        .accessibilityIdentifier(line.showsFill ? "LibraryFillProgress" : "SyncStatus")
    }
}
