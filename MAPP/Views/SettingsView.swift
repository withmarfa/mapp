import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(NotesFolder.self) private var folder
    @Environment(\.library) private var library
    @Bindable var presentation: SettingsPresentation
    @State private var isChoosing = false
    @State private var isEmptying = false
    @FocusState private var isSearchFocused: Bool

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
        .environment(NotesFolder(defaults: SettingsPreview.defaults))
        .defaultAppStorage(SettingsPreview.defaults)
        .frame(width: 1100, height: 720)
}
#endif
