import SwiftUI

@main
struct MAPPApp: App {
    @State private var folder = NotesFolder()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(folder)
                // New notes with something in them get their files before the app goes.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    folder.library?.finish()
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            AppCommands(library: folder.library)
            FormatCommands()
        }

        WindowGroup("Note", for: Note.ID.self) { $id in
            if let library = folder.library {
                NoteWindow(id: id)
                    .environment(library)
            }
        }
        .defaultSize(width: 640, height: 720)

        Settings {
            SettingsView()
                .environment(folder)
        }
    }
}
