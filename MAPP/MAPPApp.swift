import SwiftUI

@main
struct MAPPApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private var folder: NotesFolder { delegate.folder }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(folder)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            AppCommands(library: folder.library)
            FindCommands()
            FormatCommands()
            ToolbarCommands()
        }

        WindowGroup("Note", for: String.self) { $path in
            if let library = folder.library {
                NoteWindow(path: $path)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    let folder = NotesFolder()

    /// Nothing typed is lost to quitting: each page hands over its last edit, new notes with something in them
    /// get their files, and the store finishes writing, before the app goes.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        EditorController.flushAll { [folder] in
            folder.library?.finish()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
