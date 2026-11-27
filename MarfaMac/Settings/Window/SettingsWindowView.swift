import AppKit
import Marfa
import SwiftUI

/// The Settings window's content: a sidebar with history, the page's title, and the page in
/// its centered column. It is a `Window` scene of its own, not the system's `Settings` scene: that scene is sized to its
/// content and meant for a few tabs, with no toolbar of ours and no remembered, resizable frame, and a `Window` is one
/// instance that `openWindow` brings forward.
struct SettingsWindowView: View {
    let launcher: SettingsLauncher
    let libraries: Libraries
    @State private var host: AppSettingsHost
    @State private var search = ""
    @State private var sheets = SettingsSheetPresenter()
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    init(launcher: SettingsLauncher, libraries: Libraries, mainWindows: ItemLinkOpener? = nil) {
        self.launcher = launcher
        self.libraries = libraries
        _host = State(initialValue: AppSettingsHost(libraries: libraries, launcher: launcher, mainWindows: mainWindows))
    }

    private var navigation: SettingsNavigation { launcher.navigation }
    private var badgeAddress: String? {
        host.connection == .connected && host.grants.contains(.instanceRead) ? host.serverAddress : nil
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selection: Binding { navigation.page } set: { navigation.show($0) }, search: $search,
                badges: { page in
                    guard page == .account, badgeAddress != nil else { return nil }
                    return host.overview.attentionBadge
                }
            )
            .frame(minWidth: SettingsTokens.Metric.sidebarWidth, maxWidth: SettingsTokens.Metric.sidebarWidth)
            .navigationSplitViewColumnWidth(min: SettingsTokens.Metric.sidebarWidth, ideal: SettingsTokens.Metric.sidebarWidth, max: SettingsTokens.Metric.sidebarWidth)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarSpacer(.flexible)
                ToolbarItemGroup {
                    Button("Back", systemImage: "chevron.backward") { navigation.back() }
                        .labelStyle(.iconOnly)
                        .disabled(!navigation.canGoBack)
                        .help("Back")
                        .accessibilityIdentifier("SettingsBack")
                    Button("Forward", systemImage: "chevron.forward") { navigation.forward() }
                        .labelStyle(.iconOnly)
                        .disabled(!navigation.canGoForward)
                        .help("Forward")
                        .accessibilityIdentifier("SettingsForward")
                }
            }
        } detail: {
            SettingsDetail(navigation: navigation, host: host, libraries: libraries)
                .navigationTitle(navigation.title)
        }
        .frame(minWidth: SettingsTokens.Metric.windowMinWidth, minHeight: SettingsTokens.Metric.windowMinHeight)
        .interfaceTextStyle()
        .appAccent()
        .environment(\.settingsTextScale, InterfaceStyle.scale(for: textSize))
        .environment(libraries)
        .environment(libraries.host)
        .environment(\.library, libraries.current)
        .containerBackground(SettingsTokens.page, for: .window)
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
        .environment(\.settingsSheets, sheets)
        .settingsSheet(isPresented: sheets.isPresented, dismiss: { sheets.dismiss() }) {
            if let content = sheets.content { content }
        }
        .background(WindowCloseWatch(frameName: "MarfaMacSettings") { closed() })
        .settingsClickOutsideEndsEditing()
        .task(id: badgeAddress) {
            if badgeAddress != nil { await host.overview.load() }
        }
        .accessibilityIdentifier("SettingsWindow")
    }

    /// Closing Settings hands over what was typed and not saved, stops following an update (the server carries on), and drops
    /// a question about changes that wait, which is put again when Settings is next opened.
    private func closed() {
        host.handOverDrafts()
        host.updates.stop()
        libraries.marfaSettings.cancelDeparture()
    }
}

/// The page the window shows: one of the app's own, or one of the Marfa's behind its gate.
struct SettingsDetail: View {
    let navigation: SettingsNavigation
    let host: AppSettingsHost
    let libraries: Libraries

    var body: some View {
        Group {
            switch navigation.page {
            case .general: GeneralPage(libraries: libraries)
            case .appearance: AppearancePage()
            case .keyboard: KeyboardPage(libraries: libraries)
            case .lists: ListsPage()
            case .editor: EditorPage()
            case .layouts: LayoutsPage()
            case .search: SearchPage()
            case .connection: ConnectionPage(settingsHost: host)
            case .marfa(let page): MarfaSettingsPageView(page: page, host: host)
            }
        }
        .environment(\.settingsSubpage, navigation.current.subpage)
        .environment(\.settingsNavigation, SettingsNavigationActions(navigation: navigation))
        .id(navigation.current)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SettingsDetail")
    }
}

/// The library dialogs, for a window that may have no library: a purge asked for in Trash is confirmed here.
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
