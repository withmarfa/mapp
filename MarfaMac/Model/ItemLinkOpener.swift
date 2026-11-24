import AppKit
import Foundation
import Observation
import os

/// A main window as the opener sees it: whether it is still open, and a way to bring it in front of the others.
protocol ItemLinkWindow: AnyObject {
    /// False once the window has closed, though its browser may live on.
    var isOpen: Bool { get }
    /// Called once, as the window closes.
    var whenClosed: (() -> Void)? { get set }
    /// Shows the window in front, brought back from the Dock where it was minimized.
    func bringForward()
}

/// Routes external item links against the working copy and hands accepted requests to a main window, the one in front
/// or one it opens, never a window of the item's own. Only the latest link counts: a newer one, whatever it opens,
/// replaces one waiting for the library and one no window has taken yet.
@Observable @MainActor final class ItemLinkOpener {
    /// What the opener reads of the app: what the windows show, and the library they read.
    struct Standing {
        let mode: Libraries.Mode
        let library: (any ItemLibrary)?
    }

    /// An item for a main window to open: the window last in front when the link was decided, or another open main
    /// window where none was, or, where no main window was open, the first to show `library`, the one the link was
    /// checked against. The link's instance id is the one the copy answered then, which delivery asks again.
    struct Request: Equatable {
        let id = UUID()
        let link: ItemAppLink
        weak var target: Browser?
        weak var library: (any ItemLibrary)?

        var item: ItemID { link.item }

        static func == (lhs: Request, rhs: Request) -> Bool { lhs.id == rhs.id }
    }

    /// The item waiting for a window to open it.
    private(set) var request: Request?

    /// Opens a main window, for a link that comes while none is open. A window sets it, as only a view can open one.
    /// The first scene to set it serves an ask made before any scene had appeared.
    @ObservationIgnored var openMainWindow: (() -> Void)? {
        didSet {
            guard mainWindowAsk == .waitingForAScene else { return }
            // After this update, so a main window appearing in it counts itself first and no other is opened.
            Task { @MainActor in
                guard mainWindowAsk == .waitingForAScene, let openMainWindow else { return }
                mainWindowAsk = .sent
                openMainWindow()
            }
        }
    }

    @ObservationIgnored private let standing: @MainActor () -> Standing
    @ObservationIgnored private let notices: Notices
    @ObservationIgnored private let front: @MainActor () -> Browser?
    @ObservationIgnored private let activate: @MainActor () -> Void
    @ObservationIgnored private let limit: Duration
    @ObservationIgnored private var waiting: ItemAppLink?
    @ObservationIgnored private var routing: Task<Void, Never>?
    /// Counts the links received, so a delivery can tell a newer one came while it waited.
    @ObservationIgnored private var received = 0
    /// Ends each current wait, the route's and a delivery's, for a newer link.
    @ObservationIgnored private var interrupts: [UUID: () -> Void] = [:]
    @ObservationIgnored private var windows: [Registered] = []
    /// A main window asked for that has not yet appeared, so a run of links opens only one.
    @ObservationIgnored private var mainWindowAsk: MainWindowAsk?

    private enum MainWindowAsk {
        /// No scene had appeared to open one.
        case waitingForAScene
        case sent
    }

    private struct Registered {
        weak var browser: Browser?
        let window: any ItemLinkWindow
    }

    convenience init(libraries: Libraries) {
        self.init(notices: libraries.host.notices) { Standing(mode: libraries.mode, library: libraries.current) }
    }

    init(
        notices: Notices, limit: Duration = .seconds(30), front: @escaping @MainActor () -> Browser? = { FrontBrowser.shared.last },
        activate: @escaping @MainActor () -> Void = { NSApp.activate() }, standing: @escaping @MainActor () -> Standing
    ) {
        self.notices = notices
        self.limit = limit
        self.front = front
        self.activate = activate
        self.standing = standing
    }

    /// Takes the last `marfa://` link of those the system handed over together. Any other address, such as a
    /// sign-in's answer, is not a link to an item and is left alone.
    func receive(_ urls: [URL]) {
        guard let url = urls.last(where: { $0.scheme?.lowercased() == ItemAppLink.scheme }) else { return }
        request = nil
        received += 1
        waiting = ItemAppLink(url)
        for interrupt in interrupts.values { interrupt() }
        guard waiting != nil else {
            refuse(.malformed)
            return
        }
        if routing == nil { routing = Task { await route() } }
    }

    /// Counts `browser`'s main window among those open, until `window` closes.
    func register(_ browser: Browser, window: any ItemLinkWindow) {
        windows.removeAll { $0.browser == nil || $0.browser === browser }
        windows.append(Registered(browser: browser, window: window))
        window.whenClosed = { [weak self, weak window] in
            guard let self, let window else { return }
            closed(window)
        }
        mainWindowAsk = nil
    }

    /// The item `browser`'s open main window is to open, once, while it shows `library`: nil where the request is
    /// another window's. A request for a library the windows have since left is dropped, as its check was against
    /// that one. The copy is asked again which Marfa it holds, since it can fill from another at the same address
    /// while the request waits; then the link is decided again, so another Marfa, or an item gone or deleted since,
    /// is told. The window that takes it comes forward.
    func take(for browser: Browser, in library: any ItemLibrary) async -> Item? {
        guard let request, library.isLoaded else { return nil }
        guard let checked = request.library, checked === standing().library else {
            self.request = nil
            return nil
        }
        guard checked === library, window(of: browser) != nil else { return nil }
        // A window the link was meant for that has since closed leaves it to any other.
        if let target = request.target, target !== browser, window(of: target) != nil { return nil }
        // Taken now, so no other window takes it while the copy answers.
        self.request = nil
        let link = received
        let asked = await instanceID(of: checked, until: .now + limit)
        guard received == link else { return nil }
        let now = standing()
        guard now.mode == .marfa, now.library === checked, checked.isLoaded else { return nil }
        guard window(of: browser) != nil else {
            offer(request.link, in: checked)
            return nil
        }
        guard case .answered(let instanceID) = asked else {
            refuse(.stillOpening)
            return nil
        }
        let held = checked.item(request.item)
        switch ItemLinkRoute.decide(request.link, mode: now.mode, isLoaded: true, instanceID: instanceID, held: held?.state) {
        case .open:
            window(of: browser)?.bringForward()
            return held
        case .refuse(let refusal):
            refuse(refusal)
            return nil
        case .wait:
            return nil
        }
    }

    private func route() async {
        defer { routing = nil }
        var current: ItemAppLink?
        var deadline = ContinuousClock.now
        while let link = waiting {
            if link != current {
                current = link
                deadline = .now + limit
            }
            guard ContinuousClock.now < deadline else {
                waiting = nil
                refuse(.stillOpening)
                return
            }
            guard let (route, library) = await decide(link, until: deadline), waiting == link else { continue }
            if route == .wait {
                await standingChanges(until: deadline)
                continue
            }
            waiting = nil
            switch route {
            case .open:
                guard let library else { continue }
                Telemetry.logger(.navigation).info("item link opens an item")
                activate()
                offer(link, in: library)
            case .refuse(let refusal):
                refuse(refusal)
            case .wait:
                break
            }
        }
    }

    /// The route for `link` and the library it was decided on; nil where the library changed while its copy was asked
    /// which Marfa it is, where a newer link came meanwhile, or where `deadline` passed first.
    private func decide(_ link: ItemAppLink, until deadline: ContinuousClock.Instant) async -> (ItemLinkRoute, (any ItemLibrary)?)? {
        let before = standing()
        guard before.mode == .marfa, let library = before.library, library.isLoaded else {
            let route = ItemLinkRoute.decide(link, mode: before.mode, isLoaded: false, instanceID: nil, held: nil)
            return (route, nil)
        }
        guard case .answered(let instanceID) = await instanceID(of: library, until: deadline) else { return nil }
        let after = standing()
        guard after.mode == .marfa, let still = after.library, still === library else { return nil }
        let route = ItemLinkRoute.decide(
            link, mode: after.mode, isLoaded: library.isLoaded, instanceID: instanceID, held: library.item(link.item)?.state)
        return (route, library)
    }

    private nonisolated enum Asked: Sendable { case answered(String?), stopped }

    /// Offers `link`'s item to the main window in front, or, with none open, to the one it asks for.
    private func offer(_ link: ItemAppLink, in library: any ItemLibrary) {
        let target = frontWindow()?.browser
        request = Request(link: link, target: target, library: library)
        if target == nil { askForMainWindow() }
    }

    /// Offers again a request left for `window`, which has closed, so another window takes it or one is asked for.
    private func closed(_ window: any ItemLinkWindow) {
        windows.removeAll { $0.window === window }
        guard let request, let library = request.library else { return }
        if let target = request.target, self.window(of: target) != nil { return }
        offer(request.link, in: library)
    }

    /// The copy's instance id, unless `deadline` passes or a newer link comes first. The copy asks again while its
    /// key changes, so its answer can take any time.
    private func instanceID(of library: any ItemLibrary, until deadline: ContinuousClock.Instant) async -> Asked {
        let wait = UUID()
        defer { interrupts[wait] = nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Asked, Never>) in
            let race = Race(continuation)
            interrupts[wait] = { race.finish(.stopped) }
            race.add(Task { @MainActor in race.finish(.answered(await library.instanceID())) })
            race.add(Task { @MainActor in
                try? await Task.sleep(until: deadline)
                race.finish(.stopped)
            })
        }
    }

    /// Returns once what the windows show changes, a newer link comes, or at `deadline`.
    private func standingChanges(until deadline: ContinuousClock.Instant) async {
        let wait = UUID()
        defer { interrupts[wait] = nil }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let race = Race(continuation)
            interrupts[wait] = { race.finish(()) }
            withObservationTracking {
                _ = standing().library?.isLoaded
            } onChange: {
                Task { @MainActor in race.finish(()) }
            }
            race.add(Task { @MainActor in
                try? await Task.sleep(until: deadline)
                race.finish(())
            })
        }
    }

    /// Tells the person, in the main window in front, which comes forward so the alert is seen; with no main window
    /// open, in the one it opens.
    private func refuse(_ refusal: ItemLinkRefusal) {
        Telemetry.logger(.navigation).info("item link refused: \(String(describing: refusal), privacy: .public)")
        activate()
        if let window = frontWindow()?.window { window.bringForward() } else { askForMainWindow() }
        notices.tell(refusal.title, refusal.message, action: refusal.action)
    }

    /// The main windows still open, forgetting those closed.
    private func openWindows() -> [(browser: Browser, window: any ItemLinkWindow)] {
        windows.removeAll { $0.browser == nil || !$0.window.isOpen }
        return windows.compactMap { entry in entry.browser.map { ($0, entry.window) } }
    }

    private func window(of browser: Browser) -> (any ItemLinkWindow)? {
        openWindows().first { $0.browser === browser }?.window
    }

    /// The open main window last in front, or another open one.
    private func frontWindow() -> (browser: Browser, window: any ItemLinkWindow)? {
        let open = openWindows()
        let front = front()
        return open.first { $0.browser === front } ?? open.last
    }

    /// Opens one main window, unless one asked for has yet to appear. With no scene yet to open it, the first scene
    /// to appear does (`openMainWindow`).
    private func askForMainWindow() {
        guard mainWindowAsk == nil else { return }
        guard let openMainWindow else {
            mainWindowAsk = .waitingForAScene
            return
        }
        mainWindowAsk = .sent
        openMainWindow()
    }

    /// Resumes a wait once, with whichever answer comes first, and stops the rest.
    private final class Race<Value: Sendable> {
        private var continuation: CheckedContinuation<Value, Never>?
        private var tasks: [Task<Void, Never>] = []

        init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }

        func add(_ task: Task<Void, Never>) {
            if continuation == nil { task.cancel() } else { tasks.append(task) }
        }

        func finish(_ value: Value) {
            guard let continuation else { return }
            self.continuation = nil
            for task in tasks { task.cancel() }
            tasks = []
            continuation.resume(returning: value)
        }
    }
}
