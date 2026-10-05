import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(NotesFolder.self) private var folder
    @Bindable var presentation: SettingsPresentation
    @State private var isChoosing = false
    @State private var isEmptying = false

    private var panes: [SettingsPane] {
        SettingsPane.allCases.filter { $0.matches(presentation.query) }
    }

    private var selectedPane: SettingsPane? {
        guard let pane = presentation.pane, panes.contains(pane) else { return panes.first }
        return pane
    }

    private var deleted: Set<Note.ID> {
        folder.library.map { Set($0.notes(in: .recentlyDeleted).map(\.id)) } ?? []
    }

    var body: some View {
        // The notes split view stays mounted underneath. Changing its columns crashed AppKit's toolbar layout.
        HSplitView {
            sidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320, maxHeight: .infinity)
            detail
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .navigationTitle("Settings")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SettingsWorkspace")
        .onChange(of: presentation.query) {
            if let selectedPane { presentation.pane = selectedPane }
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            // Open notes hand over their last edits to the folder they came from before it is changed.
            if case .success(let url) = result { EditorController.flushAll { folder.choose(url) } }
        }
        .confirmationDialog(
            "^[Delete \(deleted.count) note](inflect: true) immediately?",
            isPresented: $isEmptying
        ) {
            Button("Delete", role: .destructive) { folder.library?.deletePermanently(deleted) }
        } message: {
            Text("You can’t undo this action.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Button("Back to MAPP", systemImage: "chevron.left") { presentation.close() }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .accessibilityIdentifier("SettingsBack")
            SettingsSearchField(text: $presentation.query)
                .frame(height: 24)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            List(selection: $presentation.pane) {
                ForEach(panes) { pane in
                    Label(pane.title, systemImage: pane.symbol)
                        .tag(pane)
                        .accessibilityIdentifier("SettingsPane-\(pane.rawValue)")
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("SettingsSidebar")
        }
        .background(.regularMaterial)
    }

    @ViewBuilder private var detail: some View {
        if let pane = selectedPane {
            VStack(alignment: .leading, spacing: 0) {
                Text(pane.title)
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
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
                .accessibilityIdentifier("SettingsDetail")
            }
        } else {
            ContentUnavailableView.search(text: presentation.query)
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
                        .disabled(deleted.isEmpty)
                }
            } footer: {
                Text("Deleted notes stay in Recently Deleted for \(NoteLibrary.trashDays) days, then they’re deleted for good.")
                    .foregroundStyle(.secondary)
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

/// SwiftUI's searchable puts the field in the window toolbar; settings keeps it in its sidebar.
private struct SettingsSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> SettingsNativeSearchField {
        let field = SettingsNativeSearchField()
        field.placeholderString = String(localized: "Search Settings")
        field.setAccessibilityLabel(String(localized: "Search Settings"))
        field.setAccessibilityIdentifier("SettingsSearch")
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: SettingsNativeSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private final class SettingsNativeSearchField: NSSearchField {
    private var hasAppeared = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !hasAppeared else { return }
        hasAppeared = true
        // Move keyboard input out of the retained editor before it can reach the hidden note.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
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
