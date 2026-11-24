import SwiftUI

/// A main window: the items of the library the app reads once there is one, and until then a page saying why not.
struct RootView: View {
    @Environment(Libraries.self) private var libraries
    /// The window's browser lives here, above the library, so what the person was writing outlives a change of
    /// library, which starts the rest of the window afresh.
    @State private var browser: Browser
    let settingsLauncher: SettingsLauncher
    @Environment(\.openWindow) private var openWindow

    /// The browser starts holding the looks the person chose, so the first draw of a gallery, a board or a table builds
    /// once and not again when the choices arrive.
    init(settingsLauncher: SettingsLauncher, libraries: Libraries) {
        self.settingsLauncher = settingsLauncher
        let browser = Browser()
        browser.openSettings = { [settingsLauncher] in settingsLauncher.show($0, subpage: $1) }
        ValueEditPresenter.shared.editType = { [settingsLauncher, libraries] type in
            let title = libraries.current?.catalogue.plural(for: type) ?? type.rawValue
            settingsLauncher.show(.types, subpage: SettingsSubpage(id: "type:" + type.rawValue, title: title))
        }
        browser.lookChoices = libraries.typeLooks.choices(for: libraries.libraryKey)
        _browser = State(initialValue: browser)
    }

    var body: some View {
        workspace
        .focusedSceneValue(\.browser, browser)
        // The table, gallery and board draw each type's chosen look, which the browser holds for them to read, seeded in `init`.
        .onChange(of: libraries.typeLooks.choices(for: libraries.libraryKey)) { _, choices in
            browser.lookChoices = choices
        }
        .onAppear {
            LaunchTrace.shared.mark(.windowShown)
            settingsLauncher.open = { openWindow(id: SettingsLauncher.windowID) }
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
                    // The library is given to the branch that shows it, as the item window does, and not to the whole
                    // window: a view built for it keeps it until SwiftUI removes the view, and the window never has a
                    // main view with none.
                    .environment(\.library, library)
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

/// A server is set, but its library can't be shown, because its sign-in ended or its copy can't be opened.
struct LibraryUnavailableView: View {
    @Environment(Libraries.self) private var libraries
    let browser: Browser

    var body: some View {
        let status = ConnectionStatus(libraries.host.state)
        // The pane's own line points "below", which here is only this button.
        let detail = libraries.host.state == .keyRefused
            ? String(localized: "The app isn’t signed in to this server. Sign in again in Settings.")
            : status.detail
        ContentUnavailableView {
            Label("Can’t Open Your Marfa Library", systemImage: "exclamationmark.triangle")
        } description: {
            Text(detail ?? String(localized: "The app can’t open the copy of your library on this Mac."))
        } actions: {
            Button("Open Settings…") { browser.showSettings(.connection) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("LibraryUnavailableSettings")
        }
        .frame(minWidth: 480, minHeight: 360)
        .accessibilityIdentifier("LibraryUnavailable")
    }
}

/// Asks the person to connect to their Marfa, on first launch or after they disconnect.
struct WelcomeView: View {
    @Environment(Libraries.self) private var libraries
    let browser: Browser

    var body: some View {
        ContentUnavailableView {
            if libraries.host.unusableAddress == nil {
                Label("Connect to Your Marfa", systemImage: "server.rack")
            } else {
                Label("Change Your Server Address", systemImage: "exclamationmark.triangle")
            }
        } description: {
            if let address = libraries.host.unusableAddress {
                Text(verbatim: Words.savedAddressHasMore(address))
            } else {
                Text("The app reads and writes your library on a Marfa server. Enter its address and sign in from Settings.")
            }
        } actions: {
            Button("Connect…") { browser.showSettings(.connection) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("WelcomeConnect")
        }
        .frame(minWidth: 480, minHeight: 360)
        .accessibilityIdentifier("Welcome")
    }
}
