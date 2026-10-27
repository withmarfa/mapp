import SwiftUI

/// A main window: the notes of the library the app reads once there is one, and until then a page saying why not.
struct RootView: View {
    @Environment(Libraries.self) private var libraries
    /// The window's browser lives here, above the library, so what the person was writing outlives a change of
    /// library, which starts the rest of the window afresh.
    @State private var browser = Browser()
    let settingsRequest: SettingsRequest

    var body: some View {
        Group {
            if browser.showsSettings && libraries.current == nil {
                SettingsWorkspace(browser: browser)
            } else {
                workspace
            }
        }
        // Settings reads the library too, so it is given to both.
        .environment(\.library, libraries.current)
        .focusedSceneValue(\.browser, browser)
        .onAppear {
            if settingsRequest.isPending {
                settingsRequest.isPending = false
                browser.showSettings(settingsRequest.page)
                settingsRequest.page = nil
            }
        }
        .notices(libraries.host.notices) { browser.showSettings($0) }
    }

    @ViewBuilder private var workspace: some View {
        switch libraries.mode {
        case .unconfigured:
            WelcomeView(browser: browser)
        case .marfa:
            if let library = libraries.current {
                MainView(browser: browser)
                    // A different library is a different set of items, and the window starts afresh with it.
                    .id(ObjectIdentifier(library))
            }
        case .opening:
            ProgressView("Opening Your Library…")
                .frame(minWidth: 480, minHeight: 360)
        case .failed:
            LibraryUnavailableView(browser: browser)
        }
    }
}

/// A server is set, but its library can't be shown, because its key was refused or its copy can't be opened.
struct LibraryUnavailableView: View {
    @Environment(Libraries.self) private var libraries
    let browser: Browser

    var body: some View {
        let status = ConnectionStatus(libraries.host.state)
        // The pane's own line points "below", which here is only this button.
        let detail = libraries.host.state == .keyRefused
            ? String(localized: "The server doesn’t accept your key. Enter a new one in Settings.")
            : status.detail
        ContentUnavailableView {
            Label("Can’t Open Your Marfa Library", systemImage: "exclamationmark.triangle")
        } description: {
            Text(detail ?? String(localized: "MAPP can’t open the copy of your library on this Mac."))
        } actions: {
            Button("Open Settings…") { browser.showSettings(.library) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("LibraryUnavailableSettings")
        }
        .frame(minWidth: 480, minHeight: 360)
        .accessibilityIdentifier("LibraryUnavailable")
    }
}

/// Asks the person to connect to their Marfa, on first launch or after they disconnect.
struct WelcomeView: View {
    let browser: Browser

    var body: some View {
        ContentUnavailableView {
            Label("Connect to Your Marfa", systemImage: "server.rack")
        } description: {
            Text("MAPP reads and writes your library on a Marfa server. Enter its address and your key in Settings.")
        } actions: {
            Button("Connect…") { browser.showSettings(.library) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("WelcomeConnect")
        }
        .frame(minWidth: 480, minHeight: 360)
        .accessibilityIdentifier("Welcome")
    }
}
