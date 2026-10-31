import MarfaBrandIcons
import SwiftUI

@main
enum Launch {
    static func main() {
        LaunchTrace.shared.mark(.appInit)
        // Made first, so it is the shared application whatever asks for one next.
        _ = MAPPApplication.shared
        // Before any icon draws, so a `simple-icons:` type icon draws its mark and not the fallback.
        MarfaBrandIcons.register()
        #if DEBUG
        if TestHost.isRequested {
            TestHost.run()
            return
        }
        #endif
        Reporting.shared.start(isTestHost: false)
        MAPPApp.main()
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

struct MAPPApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var settingsRequest = SettingsRequest()
    private var libraries: Libraries { delegate.libraries }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(settingsRequest: settingsRequest)
                .interfaceTextStyle()
                // The page's web view is backed by this color, which, unlike the window's default background, is
                // not tinted by the desktop. Making it the window's background gives the list, Settings and the
                // page one color, reaching up under the toolbar, which then draws no band of its own, even while
                // the window is inactive. The sidebar's material stays above it.
                .containerBackground(Color(nsColor: .windowBackgroundColor), for: .window)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .environment(libraries)
                .environment(libraries.host)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            AppCommands(library: libraries.current, host: libraries.host)
            PlaceCommands(library: libraries.current)
            FindCommands()
            ImportFromDevicesCommands()
            FormatCommands()
            ToolbarCommands()
            SettingsCommands(request: settingsRequest)
            #if DEBUG
            TuningCommands()
            #endif
        }

        #if DEBUG
        UtilityWindow(LocalizedStringKey(TuningPanel.title), id: TuningPanel.windowID) {
            TuningPanel()
        }
        .commandsRemoved()
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Item", for: ItemID.self) { $id in
            Group {
                if let library = libraries.current {
                    NoteWindow(id: $id)
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
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .modifier(ItemWindowNotices(notices: libraries.host.notices, settingsRequest: settingsRequest))
        }
        .defaultSize(width: 640, height: 720)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let libraries = Libraries.standard()
    private let separators = MenuSeparatorTidy()
    private var metrics: MetricsListener?

    override init() {
        #if DEBUG
        // The sample library starts as a person's first launch does, whatever an earlier run chose, so no UI test
        // inherits another's settings, a hidden sidebar or a dragged column among them, which the window keeps.
        if SampleLibrary.isRequested,
           !ProcessInfo.processInfo.arguments.contains("-MAPPKeepSampleSettings") {
            let defaults = UserDefaults.standard
            let kept = defaults.dictionaryRepresentation().keys.filter {
                $0.hasPrefix("NSSplitView Subview Frames") || $0.hasPrefix("NSToolbar Configuration")
            }
            for key in OrderKey.all + PageKey.all + ListKey.all + InterfaceKey.all + kept { defaults.removeObject(forKey: key) }
        }
        #endif
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Select All in a long list is routed by `MAPPApplication`; under another application object it would build
        // every selected row's view again, with every test still passing.
        assert(NSApp is MAPPApplication, "MAPP runs under MAPPApplication")
        separators.start()
        #if DEBUG
        let sampled = SampleLibrary.isRequested
        #else
        let sampled = false
        #endif
        // The sample library and the tests have no use of the system's reports of this app's real use.
        if !sampled { metrics = MetricsListener() }
        // The saved server's copy opens and paints before the network is asked anything.
        Task { await libraries.launch() }
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
                ViewTitleForm.handOffAll()
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
            NSApp.reply(toApplicationShouldTerminate: told)
        }
        return .terminateLater
    }
}
