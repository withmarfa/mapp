import MarfaBrandIcons
import SwiftUI

@main
enum Launch {
    static func main() {
        LaunchTrace.shared.mark(.appInit)
        // Made first, so it is the shared application whatever asks for one next.
        _ = MarfaMacApplication.shared
        #if DEBUG
        // `-MarfaMacAppearance dark|light` fixes the app's appearance for a screenshot, whatever the Mac is set to.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-MarfaMacAppearance"), arguments.indices.contains(flag + 1) {
            NSApp.appearance = NSAppearance(named: arguments[flag + 1] == "dark" ? .darkAqua : .aqua)
        }
        #endif
        // Before any icon draws, so a `simple-icons:` type icon draws its mark and not the fallback.
        MarfaBrandIcons.register()
        #if DEBUG
        if TestHost.isRequested {
            TestHost.run()
            return
        }
        #endif
        Reporting.shared.start(isTestHost: false)
        MarfaMacApp.main()
    }
}

#if DEBUG
/// The app as the unit tests' host: a running `NSApplication` for the tests to use, with no scene, no library and
/// no delegate. The scheme tests the Debug Tests configuration, whose app is background-only (`LSBackgroundOnly`),
/// so a test run shows no Dock icon and never takes the keyboard from the person.
enum TestHost {
    /// Whether the unit test bundle has been loaded into this process, which is so only for the app that hosts the
    /// unit tests. The UI tests' app never has one: its tests run in the separate runner process, which drives the app
    /// from outside, so no test bundle loads into it. The environment cannot tell the two apart, since Xcode may pass
    /// XCTest variables to either (`XCUIApplication.launchEnvironment`).
    nonisolated static var isRequested: Bool {
        Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
    }

    static func run() {
        NSApp.run()
    }
}
#endif

struct MarfaMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var settingsLauncher = SettingsLauncher()
    @AppStorage(InterfaceKey.toolbarLabelStyle) private var toolbarLabelStyle: ToolbarLabelStyle = .iconOnly
    private var libraries: Libraries { delegate.libraries }
    static let mainWindowID = "main"

    // No scene takes a URL the system hands the app (`handlesExternalEvents(matching: [])`), so none opens a window
    // for one and each reaches `AppDelegate.application(_:open:)`.
    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            RootView(settingsLauncher: settingsLauncher, libraries: libraries)
                .interfaceTextStyle()
                // The page's web view is backed by this color, which, unlike the window's default background, is
                // not tinted by the desktop. Making it the window's background gives the list, Settings and the
                // page one color, reaching up under the toolbar, which then draws no band of its own, even while
                // the window is inactive. The sidebar's material stays above it.
                .containerBackground(Color(nsColor: .windowBackgroundColor), for: .window)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .appAccent()
                .environment(libraries)
                .environment(libraries.host)
                .environment(libraries.shortcuts)
                .environment(delegate.itemLinks)
                .opensItemLinks(delegate.itemLinks)
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 1100, height: 720)
        .windowToolbarLabelStyle($toolbarLabelStyle)
        .commands {
            AppCommands(library: libraries.current, host: libraries.host, shortcuts: libraries.shortcuts)
            PlaceCommands(library: libraries.current, libraries: libraries)
            FindCommands(shortcuts: libraries.shortcuts)
            ImportFromDevicesCommands()
            LooksCommands(libraries: libraries)
            FormatCommands(shortcuts: libraries.shortcuts)
            ToolbarCommands()
            SettingsCommands(launcher: settingsLauncher, shortcuts: libraries.shortcuts)
            AboutCommands(updater: delegate.updater)
            HelpCommands(launcher: settingsLauncher)
            #if DEBUG
            TuningCommands()
            #endif
        }

        Window("Settings", id: SettingsLauncher.windowID) {
            SettingsWindowView(launcher: settingsLauncher, libraries: libraries, mainWindows: delegate.itemLinks)
                .environment(\.appUpdater, delegate.updater)
                .opensItemLinks(delegate.itemLinks)
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(width: SettingsTokens.Metric.windowWidth, height: SettingsTokens.Metric.windowHeight)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()

        #if DEBUG
        UtilityWindow(LocalizedStringKey(TuningPanel.title), id: TuningPanel.windowID) {
            TuningPanel()
                .appAccent()
        }
        .handlesExternalEvents(matching: [])
        .commandsRemoved()
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Item", for: ItemID.self) { $id in
            Group {
                if let library = libraries.current {
                    ItemWindow(id: $id)
                        .environment(\.library, library)
                } else if libraries.mode == .opening {
                    // A window restored while the server's copy opens waits for it rather than closing.
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // An item's window has nothing to show without a library, as when one is restored before a
                    // server is set, or after the server's copy could not be opened.
                    ClosingView()
                }
            }
            .interfaceTextStyle()
            .appAccent()
            .environment(libraries.shortcuts)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .modifier(ItemWindowNotices(notices: libraries.host.notices, launcher: settingsLauncher))
            .opensItemLinks(delegate.itemLinks)
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 640, height: 720)
        .windowToolbarLabelStyle($toolbarLabelStyle)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let libraries = Libraries.standard()
    /// Nil unless this build carries a feed and a key, so a build from the source never offers to replace itself.
    let updater = AppUpdater.standard()
    /// Opens the items of the `marfa://` links other apps hand over (`application(_:open:)`).
    private(set) lazy var itemLinks = ItemLinkOpener(libraries: libraries)
    private let separators = MenuSeparatorTidy()
    private var metrics: MetricsListener?
    private var themeObservation: (any NSObjectProtocol)?

    override init() {
        #if DEBUG
        // The sample library starts as a person's first launch does, whatever an earlier run chose, so no UI test
        // inherits another's settings, a hidden sidebar or a dragged column among them, which the window keeps.
        if SampleLibrary.isRequested,
           !ProcessInfo.processInfo.arguments.contains("-MarfaMacKeepSampleSettings") {
            let defaults = UserDefaults.standard
            let kept = defaults.dictionaryRepresentation().keys.filter {
                $0.hasPrefix("NSSplitView Subview Frames") || $0.hasPrefix("NSToolbar Configuration")
                    || $0.hasPrefix("\(InterfaceKey.inspectorAppOpen).")
            }
            SampleLibrary.forgetStoredChoices(in: defaults)
            for key in kept { defaults.removeObject(forKey: key) }
        }
        #endif
        super.init()
        DateFormat.setAsideUnreadable()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Select All in a long list is routed by `MarfaMacApplication`; under another application object it would build
        // every selected row's view again, with every test still passing.
        assert(NSApp is MarfaMacApplication, "The app runs under MarfaMacApplication")
        QuickLookFile.removeLeftovers()
        separators.start()
        AppTheme.apply(.stored())
        // A choice in Settings reaches every window at once, and a Reset puts the system's back.
        themeObservation = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppTheme.apply(.stored()) }
        }
        #if DEBUG
        let sampled = SampleLibrary.isRequested
        #else
        let sampled = false
        #endif
        // The sample library and the tests have no use of the system's reports of this app's real use.
        if !sampled { metrics = MetricsListener() }
        // The saved server's archive is written to the chosen folder when one is due; the sample and the tests never export.
        if !sampled { libraries.automaticExport.start() }
        // The shortcuts that work in any app are registered once the app can act on them, and only the ones set.
        libraries.anyAppShortcuts.perform = { [libraries] command in FrontBrowser.shared.perform(command, in: libraries) }
        libraries.anyAppShortcuts.start()
        // The saved server's copy opens and paints before the network is asked anything.
        Task { await libraries.launch() }
    }

    /// The URLs the system hands the app, as when a `marfa://` item link is opened in another app. The sign-in's
    /// answer never comes this way: `ASWebAuthenticationSession` takes it.
    func application(_ application: NSApplication, open urls: [URL]) {
        itemLinks.receive(urls)
    }

    /// Nothing typed is lost to quitting: each page hands over its last edit and each library keeps its writes on
    /// this Mac, in its copy's queue, before the app goes. The server is not
    /// waited for, so quitting offline is not held up; a library that cannot finish holds it up only so long. A change
    /// not kept that no window has told, as when no window is open, is told here, so its text reaches the clipboard.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { [libraries] in
            // A property typed in an inspector is written, or handed back, before the library finishes its writes.
            DetailsPresentation.handOffAllProperties(in: libraries.current)
            let kept = await libraries.flushEditors(within: .seconds(5))
            // A draft in quick add, or a view's title not yet saved, has no other home once its window goes, so it
            // is told with the rest.
            if kept {
                QuickAdd.handOffAll(to: libraries.host.notices, in: libraries.current)
                ViewPanel.handOffAll()
                libraries.handOffDraftsAtQuit()
            }
            let told = kept && libraries.host.notices.tellBeforeQuitting(copying: Notices.copyToClipboard) { notice in
                let alert = NSAlert()
                alert.messageText = notice.title
                alert.informativeText = notice.message
                alert.runModal()
            }
            // Reports queued for this run go out within the SDK's short deadline, after the editors' flush and only
            // once the quit is going ahead.
            if told { await Reporting.shared.flush() }
            // The pages are still up and may have reported while the reports went out: that text joins the queue too.
            if told { await libraries.current?.finish() }
            // An automatic export still running is stopped and leaves no half file.
            if told { await libraries.automaticExport.stop(within: .seconds(2)) }
            NSApp.reply(toApplicationShouldTerminate: told)
        }
        return .terminateLater
    }
}
