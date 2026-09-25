import SwiftUI

@main
struct MAPPApp: App {
    @State private var library = NoteLibrary.sample()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .environment(library)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            AppCommands(library: library)
        }

        WindowGroup("Note", for: Note.ID.self) { $id in
            NoteWindow(id: id)
                .environment(library)
        }
        .defaultSize(width: 640, height: 720)

        Settings {
            SettingsView()
        }
    }
}
