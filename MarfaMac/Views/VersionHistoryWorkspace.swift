import SwiftUI

/// Version History in place of a window's page: the thread of versions beside the version chosen, with its facts in
/// the right sidebar. It mounts a split view of its own, as every other workspace does, so the window's sidebar and
/// list come back as they were when it ends. Cancel and Restore Version sit at the top right of the page.
struct VersionHistoryWorkspace: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let mode: VersionHistoryMode
    let details: DetailsPresentation
    /// What the weeks and months of the thread are counted from; it moves on at midnight and when the zone changes.
    @State private var now = Date.now

    var body: some View {
        let list = mode.list(in: library)
        NavigationSplitView(columnVisibility: .constant(.all)) {
            VersionThreadColumn(mode: mode, list: list, now: now)
                // The thread is the mode's whole left side, so there is nothing to hide it for. Removed in the column,
                // where the split view adds the toggle.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 260, ideal: 288, max: 360)
        } detail: {
            VersionPageColumn(mode: mode, list: list)
                .inspector(isPresented: Binding { details.isPresented } set: { details.isPresented = $0 }) {
                    VersionFactsPanel(mode: mode, list: list)
                        .inspectorColumnWidth(min: 260, ideal: 310, max: 440)
                }
                // The thread's header already says it. The window keeps the title for Mission Control and VoiceOver.
                .toolbar(removing: .title)
                // Plain, not `toolbar(id:)`: the mode has nothing to arrange, so the window's toolbar is not customizable
                // while it is on, and it names no saved layout to change or lose. The window's own layout comes back as it was.
                .toolbar { toolbar }
        }
        .navigationTitle("Version History")
        .onExitCommand { details.leaveHistory() }
        .onChange(of: list == nil, initial: true) {
            // The item went while its history was open, so there is nothing left to read the versions against.
            if list == nil { details.leaveHistory() }
        }
        .onChange(of: list?.entries.count, initial: true) {
            if let list { mode.chooseDefault(in: list) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in now = .now }
        .onDisappear { mode.stop() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        let check = mode.restoreCheck(in: library)
        // With the title gone nothing else pushes the buttons to the right of the page.
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) {
            Button { details.leaveHistory() } label: { Text("Cancel").padding(.horizontal, 6) }
                .keyboardShortcut(.cancelAction)
                .help("Go back to the item")
                .accessibilityIdentifier("VersionHistoryExit")
        }
        ToolbarItem(placement: .primaryAction) {
            let canRestore = mode.canRestore(in: library)
            let restore = Button("Restore Version") { details.restoreFromHistory(in: library, undoManager: undoManager) }
                .disabled(!canRestore)
                .help(VersionHistoryMode.reason(for: check) ?? String(localized: "Make this version the item’s text and title"))
                .accessibilityIdentifier("VersionHistoryRestore")
            // A prominent button that cannot be pressed keeps its blue and loses its text, so only one that can is blue.
            if canRestore { restore.buttonStyle(.glassProminent) } else { restore }
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button(details.isPresented ? "Hide Details" : "Show Details", systemImage: "sidebar.right") {
                details.isPresented.toggle()
            }
        }
    }
}
