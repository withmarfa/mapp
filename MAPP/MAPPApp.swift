import SwiftUI

@main
struct MAPPApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var settingsRequest = SettingsRequest()
    private var folder: NotesFolder { delegate.folder }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(settingsRequest: settingsRequest)
                .environment(folder)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            AppCommands(library: folder.library)
            FindCommands()
            FormatCommands()
            ToolbarCommands()
            SettingsCommands(request: settingsRequest)
        }

        WindowGroup("Item", for: ItemID.self) { $id in
            if let library = folder.library {
                NoteWindow(library: library, id: $id)
                    .environment(\.library, library)
            } else {
                // An item's window has nothing to show without a notes folder, as when one is restored before
                // any is chosen.
                ClosingView()
            }
        }
        .defaultSize(width: 640, height: 720)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let folder = NotesFolder()

    override init() {
        #if DEBUG
        // The sample folder starts as a person's first launch does, whatever an earlier run chose, so no UI test
        // inherits another's settings, a hidden sidebar or a dragged column among them, which the window keeps.
        if ProcessInfo.processInfo.arguments.contains("-MAPPSampleFolder") {
            let defaults = UserDefaults.standard
            let columns = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("NSSplitView Subview Frames") }
            for key in OrderKey.all + PageKey.all + ListKey.all + columns { defaults.removeObject(forKey: key) }
        }
        #endif
        super.init()
    }

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
