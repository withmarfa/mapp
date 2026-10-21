import SwiftUI
import UniformTypeIdentifiers

/// A main window: the notes of the library the app reads once there is one, and until then a page saying why not.
struct RootView: View {
    @Environment(Libraries.self) private var libraries
    @State private var settings = SettingsPresentation()
    /// The window's browser lives here, above the library, so what the person was writing outlives a change of
    /// library, which starts the rest of the window afresh.
    @State private var browser = Browser()
    let settingsRequest: SettingsRequest

    var body: some View {
        Group {
            if settings.isPresented && libraries.current == nil {
                SettingsView(presentation: settings)
            } else {
                workspace
            }
        }
        // Settings reads the library too, so it is given to both.
        .environment(\.library, libraries.current)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .focusedSceneValue(\.settingsPresentation, settings)
        .onAppear {
            if settingsRequest.isPending {
                settingsRequest.isPending = false
                settings.show()
            }
        }
    }

    @ViewBuilder private var workspace: some View {
        switch libraries.mode {
        case .files, .marfa:
            if let library = libraries.current {
                MainView(browser: browser, settings: settings)
                    // A different library is a different set of items, and the window starts afresh with it.
                    .id(ObjectIdentifier(library))
            } else {
                WelcomeView()
            }
        case .opening:
            ProgressView("Opening Your Library…")
                .frame(minWidth: 480, minHeight: 360)
        case .failed:
            LibraryUnavailableView(settings: settings)
        }
    }
}

/// A server is set, but its library can't be shown, because MAPP is signed out of it or its copy can't be opened.
/// The notes folder is not shown in its place, which is not what the app was set to read.
struct LibraryUnavailableView: View {
    @Environment(Libraries.self) private var libraries
    let settings: SettingsPresentation

    var body: some View {
        let status = ConnectionStatus(libraries.host.state)
        // The pane's own line points "below", which here is only this button.
        let detail = libraries.host.state == .signedOut
            ? String(localized: "MAPP is signed out of your Marfa server. Sign in again in Settings.")
            : status.detail
        ContentUnavailableView {
            Label("Can’t Open Your Marfa Library", systemImage: "exclamationmark.triangle")
        } description: {
            Text(detail ?? String(localized: "MAPP can’t open the copy of your library on this Mac."))
        } actions: {
            Button("Open Settings…") { settings.show(.marfa) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("LibraryUnavailableSettings")
        }
        .frame(minWidth: 480, minHeight: 360)
        .accessibilityIdentifier("LibraryUnavailable")
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
