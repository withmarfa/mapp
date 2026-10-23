import SwiftUI

/// The foot of the sidebar, pinned below its list: a line about the server when there is something to say, and
/// the row that opens Settings. The row is a one-row sidebar list, so it looks, hovers and selects as the rows
/// above it do.
struct SidebarFoot: View {
    @Environment(MarfaHost.self) private var host: MarfaHost?
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser

    private enum Row: Hashable { case settings }

    var body: some View {
        VStack(spacing: 0) {
            if let host, host.source != nil {
                SyncStatusReading(host: host) { status in
                    if let note = status.primary { syncLine(note) }
                }
            }
            settingsRow
        }
        .padding(.top, 6)
    }

    private func syncLine(_ note: SyncStatus.Note) -> some View {
        Button {
            browser.showSettings(.library)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(note.dotColor)
                    .frame(width: 7, height: 7)
                    .frame(width: 20)
                Text(note.line)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(note.detail)
        .accessibilityLabel(note.line)
        .accessibilityHint(note.detail)
        .accessibilityIdentifier("SyncStatus")
    }

    private var settingsRow: some View {
        List(selection: Binding<Row?> {
            browser.showsSettings ? .settings : nil
        } set: { row in
            if row == .settings { browser.showSettings() }
        }) {
            Label {
                Text("Settings").interfaceFont(.body)
            } icon: {
                // Grey, as a place of its own rather than one of the library's.
                Image(systemName: "gearshape").interfaceFont(.body).foregroundStyle(.secondary)
            }
            .tag(Row.settings)
            .accessibilityIdentifier("SidebarSettingsRow")
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .frame(height: 20 * InterfaceStyle.scale(for: textSize) + 24)
        .accessibilityIdentifier("SidebarFoot")
    }
}
