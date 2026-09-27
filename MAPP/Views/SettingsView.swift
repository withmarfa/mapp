import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(NotesFolder.self) private var folder
    @State private var isChoosing = false
    @State private var isEmptying = false

    var body: some View {
        let deleted = folder.library.map { Set($0.notes(in: .recentlyDeleted).map(\.id)) } ?? []
        Form {
            Section {
                LabeledContent("Notes Folder") {
                    HStack {
                        Text(folder.url.map { FileManager.default.displayName(atPath: $0.path) } ?? String(localized: "None"))
                            .foregroundStyle(.secondary)
                        if let url = folder.url {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        Button("Change…") { isChoosing = true }
                    }
                }
            }
            Section {
                OrderOptions()
                ListPreviewOptions()
            }
            Section {
                PageWidthOptions()
                TextOptions()
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
            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
        // The menus show these with icons; Settings rows, as in the system's own panes, do not.
        .labelStyle(.titleOnly)
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
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

    /// The version and build, as the About window gives them.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }
}
