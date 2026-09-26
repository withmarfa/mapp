import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(NotesFolder.self) private var folder
    @State private var isChoosing = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Notes Folder") {
                    HStack {
                        Text(folder.url.map { FileManager.default.displayName(atPath: $0.path) } ?? String(localized: "None"))
                            .foregroundStyle(.secondary)
                        Button("Change…") { isChoosing = true }
                    }
                }
            }
            Section {
                OrderOptions()
            }
        }
        // The menus show these with icons; Settings rows, as in the system's own panes, do not.
        .labelStyle(.titleOnly)
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder.choose(url) }
        }
    }
}
