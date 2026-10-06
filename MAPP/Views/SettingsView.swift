import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @Bindable var presentation: SettingsPresentation
    @State private var isChoosing = false
    @State private var isEmptying = false
    @FocusState private var isSearchFocused: Bool

    private var folder: NotesFolder { libraries.folder }

    private var deleted: Set<ItemID> {
        library.map { Set($0.items(in: .recentlyDeleted).map(\.id)) } ?? []
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 360, ideal: 640)
        }
        .searchable(text: $presentation.query, placement: .sidebar, prompt: "Search Settings")
        .searchFocused($isSearchFocused)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(presentation.title)
                    .font(.headline)
                    .accessibilityIdentifier("SettingsTitle")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .navigation) {
                Button("Back to MAPP", systemImage: "chevron.left") { presentation.close() }
                    .help("Back to MAPP")
                    .accessibilityIdentifier("SettingsBack")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SettingsWorkspace")
        .task {
            // Keyboard input must leave the retained workspace before it can reach a hidden editor.
            isSearchFocused = true
        }
        .onChange(of: presentation.query) {
            if let pane = presentation.displayedPane { presentation.pane = pane }
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            // Open notes hand over their last edits to the folder they came from before it is changed.
            if case .success(let url) = result { EditorController.flushAll { folder.choose(url) } }
        }
        // A question about changes that wait is put again when Settings is next opened, not answered by leaving.
        .onDisappear { libraries.marfaSettings.cancelDeparture() }
        .sheet(item: Binding { libraries.marfaSettings.departure } set: { if $0 == nil { libraries.marfaSettings.cancelDeparture() } }) { departure in
            DepartureSheet(model: libraries.marfaSettings, departure: departure)
        }
        .confirmationDialog("Disconnect from this server?", isPresented: Bindable(libraries.marfaSettings).isConfirmingDisconnect) {
            Button("Disconnect", role: .destructive) { Task { await libraries.marfaSettings.disconnect() } }
        } message: {
            Text("MAPP removes its copy of your library and the key from this Mac. Nothing on the server changes. Your notes folder is used again.")
        }
        .confirmationDialog(
            "^[Delete \(deleted.count) note](inflect: true) immediately?",
            isPresented: $isEmptying
        ) {
            Button("Delete", role: .destructive) { library?.deletePermanentlyOnConfirm(deleted) }
        } message: {
            Text("You can’t undo this action.")
        }
    }

    private var sidebar: some View {
        List(selection: $presentation.pane) {
            ForEach(presentation.matchingPanes) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
                    .accessibilityIdentifier("SettingsPane-\(pane.rawValue)")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .accessibilityIdentifier("SettingsSidebar")
    }

    @ViewBuilder private var detail: some View {
        if let pane = presentation.displayedPane {
            Form {
                switch pane {
                case .appearance:
                    Section("Notes List") {
                        OrderOptions()
                        ListPreviewOptions()
                    }
                case .editor:
                    Section("Page Layout") {
                        PageWidthOptions()
                        ReadingWidthOptions()
                    }
                    Section("Text") { TextOptions() }
                case .library:
                    librarySettings
                case .marfa:
                    MarfaSettingsView(model: libraries.marfaSettings)
                case .about:
                    Section("MAPP") {
                        LabeledContent("Version", value: Self.version)
                    }
                }
            }
            .labelStyle(.titleOnly)
            .formStyle(.grouped)
            .navigationTitle(pane.title)
            .accessibilityIdentifier("SettingsDetail")
        } else {
            ContentUnavailableView.search(text: presentation.query)
                .navigationTitle("Settings")
        }
    }

    private var librarySettings: some View {
        Group {
            if libraries.mode == .marfa {
                // A server's library needs no folder, which is kept for when the app is disconnected.
                Section("Notes Folder") {
                    Text("MAPP is reading your Marfa library, so it doesn’t need a notes folder. Your notes folder is used again if you disconnect.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Notes Folder") {
                    LabeledContent("Folder") {
                        Text(folder.url.map { FileManager.default.displayName(atPath: $0.path) } ?? String(localized: "None"))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        if let url = folder.url {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        Button("Change…") { isChoosing = true }
                    }
                }
            }
            Section {
                LabeledContent("Recently Deleted") {
                    Button("Empty Now…") { isEmptying = true }
                        .disabled(deleted.isEmpty || library?.capabilities.contains(.purge) != true)
                }
            } footer: {
                if let days = library?.trashDays {
                    Text("Deleted notes stay in Recently Deleted for \(days) days, then they’re deleted for good.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The version and build, as the About window gives them.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }
}

#if DEBUG
private enum SettingsPreview {
    static let defaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: "MAPP.SettingsPreview")!
        defaults.removePersistentDomain(forName: "MAPP.SettingsPreview")
        return defaults
    }()
}

#Preview("Settings") {
    SettingsView(presentation: SettingsPresentation())
        .environment(Libraries(
            folder: NotesFolder(defaults: SettingsPreview.defaults),
            host: MarfaHost(
                defaults: SettingsPreview.defaults, keys: MemoryKeyStore(),
                location: try! MarfaStoreLocation(root: URL.temporaryDirectory.appending(path: "SettingsPreview")))))
        .defaultAppStorage(SettingsPreview.defaults)
        .frame(width: 1100, height: 720)
}
#endif
