import SwiftUI

@main
struct MAPPApp: App {
    @State private var library = NoteLibrary.sample()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(library)
        }
    }
}
