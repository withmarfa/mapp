import SwiftUI
import UniformTypeIdentifiers

/// A main window: the notes once a folder is chosen, and until then a page asking for one.
struct RootView: View {
    @Environment(NotesFolder.self) private var folder
    @State private var settings = SettingsPresentation()
    let settingsRequest: SettingsRequest

    var body: some View {
        ZStack {
            workspace
                .opacity(settings.isPresented ? 0 : 1)
                .allowsHitTesting(!settings.isPresented)
                .disabled(settings.isPresented)
                .accessibilityHidden(settings.isPresented)
            if settings.isPresented {
                SettingsView(presentation: settings)
            }
        }
        .focusedSceneValue(\.settingsPresentation, settings)
        .toolbarVisibility(settings.isPresented ? .hidden : .automatic)
        .onAppear {
            if settingsRequest.isPending {
                settingsRequest.isPending = false
                settings.show()
            }
        }
    }

    @ViewBuilder private var workspace: some View {
        if let library = folder.library {
            MainView(library: library, settings: settings)
                .environment(library)
                // A different folder is a different library, and the window starts afresh with it.
                .id(ObjectIdentifier(library))
        } else {
            WelcomeView()
        }
    }
}

/// Asks for the folder that holds the notes, on first launch or when the one chosen before has gone.
struct WelcomeView: View {
    @Environment(NotesFolder.self) private var folder
    @State private var isChoosing = false

    var body: some View {
        ContentUnavailableView {
            Label("Choose a Folder for Your Notes", systemImage: "folder")
        } description: {
            Text("MAPP keeps each note as a markdown file in the folder you choose. Folders inside it become folders in MAPP.")
        } actions: {
            Button("Choose Folder…") { isChoosing = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(minWidth: 480, minHeight: 360)
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder.choose(url) }
        }
    }
}
