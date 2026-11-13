import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Export Looks and Import Looks, in the File menu and the command palette: every type's look on this server, kept in a
/// file the person names, and back. Looks stay on this Mac and are never written to Marfa.
struct LooksCommands: Commands {
    let libraries: Libraries

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export Looks…") { LooksFiles.export(from: libraries) }
                .disabled(libraries.current == nil)
            Button("Import Looks…") { LooksFiles.importLooks(into: libraries) }
                .disabled(libraries.current == nil)
        }
    }
}

/// The panels and notices of Export Looks and Import Looks. The files are read and written by `TypeLooks`.
@MainActor
enum LooksFiles {
    static func export(from libraries: Libraries) {
        guard let library = libraries.current else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "MAPP Looks") + ".json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try libraries.typeLooks.exportLooks(to: url, in: library.catalogue, library: libraries.libraryKey)
            } catch {
                libraries.host.notices.tell(
                    String(localized: "Couldn’t Export Looks"),
                    String(localized: "The looks could not be written to “\(url.lastPathComponent)”. Choose another place and try again."))
            }
        }
    }

    static func importLooks(into libraries: Libraries) {
        guard libraries.current != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try libraries.typeLooks.importLooks(from: url, into: libraries.libraryKey)
            } catch {
                libraries.host.notices.tell(String(localized: "Couldn’t Import Looks"), message(for: error, file: url.lastPathComponent))
            }
        }
    }

    private static func message(for error: LooksFileError, file: String) -> String {
        switch error {
        case .unreadable:
            String(localized: "“\(file)” could not be read. No looks were changed.")
        case .notALooksFile, .unwritable:
            String(localized: "“\(file)” is not a looks file that MAPP can read. No looks were changed.")
        }
    }
}
