import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Export Layouts and Import Layouts (the code's Looks), in the File menu and in Settings > Layouts and the command palette: every type's layout on this server, kept in a
/// file the person names, and back, so they can be copied between two Marfas. The file itself is written to no Marfa.
struct LooksCommands: Commands {
    let libraries: Libraries

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export Layouts…") { LooksFiles.export(from: libraries) }
                .disabled(libraries.current == nil)
            Button("Import Layouts…") { LooksFiles.importLooks(into: libraries) }
                .disabled(libraries.current == nil)
        }
    }
}

/// The panels and notices of Export Layouts and Import Layouts. The files are read and written by `TypeLooks`.
@MainActor
enum LooksFiles {
    static func export(from libraries: Libraries) {
        guard let library = libraries.current else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "MAPP Layouts") + ".json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try libraries.typeLooks.exportLooks(to: url, in: library.catalogue, library: libraries.libraryKey)
            } catch {
                libraries.host.notices.tell(
                    String(localized: "Couldn’t Export Layouts"),
                    String(localized: "The layouts could not be written to “\(url.lastPathComponent)”. Choose another place and try again."))
            }
        }
    }

    static func importLooks(into libraries: Libraries) {
        guard let current = libraries.current else { return }
        guard !current.catalogue.itemTypes.isEmpty else {
            libraries.host.notices.tell(String(localized: "Couldn’t Import Layouts"), notLoadedMessage)
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let library = libraries.current else { return }
            do throws(LooksFileError) {
                try libraries.typeLooks.importLooks(from: url, into: libraries.libraryKey, in: library.catalogue)
            } catch {
                libraries.host.notices.tell(String(localized: "Couldn’t Import Layouts"), message(for: error, file: url.lastPathComponent))
            }
        }
    }

    private static var notLoadedMessage: String { String(localized: "Layouts can be imported once the library has loaded.") }

    private static func message(for error: LooksFileError, file: String) -> String {
        switch error {
        case .unreadable:
            String(localized: "“\(file)” could not be read. No layouts were changed.")
        case .notLoaded:
            notLoadedMessage
        case .notALooksFile, .unwritable:
            String(localized: "“\(file)” is not a layouts file that MAPP can read. No layouts were changed.")
        }
    }
}
