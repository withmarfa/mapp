import AppKit
import SwiftUI

/// The Settings window's content: a sidebar of pages, a toolbar with Back, Forward and the page's name, and the page in
/// its centered column. It is a `Window` scene of its own, not the system's `Settings` scene: that scene is sized to its
/// content and meant for a few tabs, with no toolbar of ours and no remembered, resizable frame, and a `Window` is one
/// instance that `openWindow` brings forward.
struct SettingsWindowView: View {
    let launcher: SettingsLauncher
    let libraries: Libraries
    @State private var host: MAPPMarfaSettingsHost
    @State private var search = ""
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    init(launcher: SettingsLauncher, libraries: Libraries) {
        self.launcher = launcher
        self.libraries = libraries
        _host = State(initialValue: MAPPMarfaSettingsHost(libraries: libraries, launcher: launcher))
    }

    private var navigation: SettingsNavigation { launcher.navigation }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selection: Binding { navigation.page } set: { navigation.show($0) }, search: $search
            )
            .navigationSplitViewColumnWidth(SettingsTokens.Metric.sidebarWidth)
        } detail: {
            SettingsDetail(navigation: navigation, host: host)
                .navigationTitle(navigation.title)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button("Back", systemImage: "chevron.left") { navigation.back() }
                            .disabled(!navigation.canGoBack)
                            .help("Back")
                            .accessibilityIdentifier("SettingsBack")
                        Button("Forward", systemImage: "chevron.right") { navigation.forward() }
                            .disabled(!navigation.canGoForward)
                            .help("Forward")
                            .accessibilityIdentifier("SettingsForward")
                    }
                }
        }
        .frame(minWidth: SettingsTokens.Metric.windowMinWidth, minHeight: SettingsTokens.Metric.windowMinHeight)
        .interfaceTextStyle()
        .environment(\.settingsTextScale, InterfaceStyle.scale(for: textSize))
        .environment(libraries)
        .environment(libraries.host)
        .environment(\.library, libraries.current)
        .containerBackground(SettingsTokens.page, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .focusedSceneValue(\.settingsNavigation, navigation)
        .notices(libraries.host.notices) { launcher.show($0) }
        .modifier(OptionalLibraryDialogs())
        .settingsSheet(
            isPresented: libraries.marfaSettings.departure != nil,
            dismiss: { if !libraries.marfaSettings.isWorking { libraries.marfaSettings.cancelDeparture() } }
        ) {
            if let departure = libraries.marfaSettings.departure {
                DepartureSheet(model: libraries.marfaSettings, departure: departure)
            }
        }
        .background(WindowCloseWatch(frameName: "MAPPSettings") { closed() })
        .accessibilityIdentifier("SettingsWindow")
    }

    /// Closing Settings hands over what was typed and not saved, and drops a question about changes that wait, which is
    /// put again when Settings is next opened.
    private func closed() {
        host.handOverDrafts()
        libraries.marfaSettings.cancelDeparture()
    }
}

/// The page the window shows: one of MAPP's own, or one of the Marfa's behind its gate.
struct SettingsDetail: View {
    let navigation: SettingsNavigation
    let host: MAPPMarfaSettingsHost

    var body: some View {
        Group {
            switch navigation.page {
            case .appearance: AppearancePage()
            case .lists: ListsPage()
            case .editor: EditorPage()
            case .connection: ConnectionPage()
            case .marfa(let page): MarfaSettingsPageView(page: page, host: host)
            }
        }
        .environment(\.settingsSubpage, navigation.current.subpage)
        .environment(\.settingsPush, { navigation.push($0) })
        .id(navigation.current)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SettingsDetail")
    }
}

/// The library dialogs, for a window that may have no library: a purge asked for in Recently Deleted is confirmed here.
private struct OptionalLibraryDialogs: ViewModifier {
    @Environment(\.library) private var library

    func body(content: Content) -> some View {
        if library != nil { content.libraryDialogs() } else { content }
    }
}

/// Tells when the window its view is in closes, and has the window keep its frame under `frameName`, so Settings opens at
/// the size it was left.
private struct WindowCloseWatch: NSViewRepresentable {
    let frameName: String
    let closed: () -> Void

    func makeNSView(context: Context) -> Probe { Probe(frameName: frameName, closed: closed) }
    func updateNSView(_ probe: Probe, context: Context) { probe.closed = closed }

    final class Probe: NSView {
        let frameName: String
        var closed: () -> Void
        private var observer: (any NSObjectProtocol)?

        init(frameName: String, closed: @escaping () -> Void) {
            self.frameName = frameName
            self.closed = closed
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.setFrameAutosaveName(frameName)
            observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closed() }
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
