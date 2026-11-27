import SwiftUI

/// The Marfa at the foot of the sidebar, below its places, types and views: its name with a line under it saying how
/// the library stands with its server, a Refresh and a cog that opens Settings, the same size. The row opens the Marfa's panel (`MarfaPanel`); a line that asks the person to act opens Settings'
/// Connection page instead, where the problems are listed.
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
            name: name, line: line, refresh: host == nil ? nil : (canRefresh: canRefresh, run: refresh), isPanelOpen: showsPanel,
            openPanel: host == nil ? nil : { showsPanel.toggle() },
            openProblems: { browser.showSettings(.connection) },
            openSettings: { browser.showSettings() })
        .popover(isPresented: $showsPanel, arrowEdge: .top) {
            if let host { panel(name, host: host) }
        }
    }

    private func panel(_ name: String, host: MarfaHost) -> some View {
        let address = host.configuredConnection.map { SettingsWording.hostName(of: $0.address) } ?? ""
        let standing = FootStanding(host: host)
        return MarfaPanel(
            library: library, name: name, address: address,
            lastSynced: standing.hasServer ? standing.lastSynced : nil,
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

/// The foot's row, given what it shows and what its controls do. Refresh is disabled where it has nothing to do, and
/// absent where there is no server to refresh from.
///
/// The whole row is a button that opens the Marfa's panel, with a soft fill only while the panel is open. The name lets
/// a click through and the line passes it on, so the line keeps its tooltip; Refresh, the cog and a line that asks for
/// action are buttons of their own. They are plain labels that dim with the window, as the sidebar's rows do. A pointer
/// click hands the keyboard back, so no focus ring stays on a control that was clicked; tabbing still reaches each.
struct SidebarFootRow: View {
    @Environment(\.appearsActive) private var appearsActive
    @FocusState private var focus: Control?
    let name: String
    /// Nil where the Marfa has nothing to say of itself.
    let line: SyncFootLine?
    /// Nil where there is no server to refresh from.
    let refresh: (canRefresh: Bool, run: () -> Void)?
    /// The panel is open, so the row keeps its fill.
    let isPanelOpen: Bool
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
                    .fill(.primary.opacity(isPanelOpen ? 0.055 : 0))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(openPanel == nil)
            .focused($focus, equals: .row)
            .simultaneousGesture(TapGesture().onEnded { focus = nil })
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityHint(Text("Shows the Marfa’s latest updates."))
            .accessibilityIdentifier("SidebarMarfa")
            // The controls' own frames leave the room between them and the line.
            HStack(alignment: .center, spacing: 0) {
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
                if let refresh { refreshButton(refresh) }
                footButton("gearshape", action: openSettings)
                .focused($focus, equals: .settings)
                .help(Self.settingsHelp(Bundle.main.infoDictionary))
                .accessibilityLabel(Text("Settings"))
                .accessibilityIdentifier("SidebarSettings")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
        }
        .frame(height: 48)
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

    /// A control at the row's trailing end: a symbol in a square as large as the cog's.
    private func footButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .interfaceFont(.body)
                .imageScale(.large)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { focus = nil })
    }

    private func refreshButton(_ refresh: (canRefresh: Bool, run: () -> Void)) -> some View {
        footButton("arrow.clockwise", action: refresh.run)
            .disabled(!refresh.canRefresh)
            .focused($focus, equals: .refresh)
            .help("Refresh")
            .accessibilityLabel(Text("Refresh"))
            .accessibilityIdentifier("SidebarRefresh")
    }

    /// One quiet line, a step below the name. Where the person has to act the line is as strong as the name, after a
    /// warning mark, and opens Settings' Connection page.
    private func syncRow(_ line: SyncFootLine) -> some View {
        HStack(spacing: 0) {
            if line.asksForAction {
                Button(action: openProblems) { syncLine(line) }
                    .buttonStyle(.plain)
                    .focused($focus, equals: .problems)
                    .simultaneousGesture(TapGesture().onEnded { focus = nil })
                    .help(line.help ?? "")
            } else {
                syncLine(line).onTapGesture {
                    focus = nil
                    openPanel?()
                }
            }
            if line.showsSpinner {
                ProgressView()
                    .controlSize(.mini)
                    .padding(.leading, 4)
                    .accessibilityHidden(true)
            }
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
