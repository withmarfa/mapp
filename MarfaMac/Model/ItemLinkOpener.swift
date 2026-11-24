import AppKit
import Foundation
import Observation
import os

/// Takes the `marfa://` links other apps hand the app (`ItemAppLink`) and has the main window in front open each
/// item as opening it from the list does. A link only opens: it never writes, signs in, or changes the connection or
/// a setting, and it opens an item only in the Marfa whose instance id it names (`ItemLinkRoute`). A link that comes
/// while the library opens, as at launch, waits for it at most `limit`; a newer link replaces a waiting one.
@Observable @MainActor final class ItemLinkOpener {
    /// What the opener reads of the app: what the windows show, and the library they read.
    struct Standing {
        let mode: Libraries.Mode
        let library: (any ItemLibrary)?
    }

    /// An item for a main window to open: the window last in front when the link was decided, or another main window
    /// where none was, or, where no main window was open, the first to show the library the link was checked against.
    struct Request: Equatable {
        let id = UUID()
        let item: ItemID
        let target: ObjectIdentifier?
        let library: ObjectIdentifier
    }

    /// The item waiting for a window to open it.
    private(set) var request: Request?

    /// Opens a main window, for a link that comes while none is open. A window sets it, as only a view can open one.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    /// What a window shows over an item in Recently Deleted that a link opened.
    static var inRecentlyDeleted: String { String(localized: "This item is in Recently Deleted.") }

    @ObservationIgnored private let standing: @MainActor () -> Standing
    @ObservationIgnored private let notices: Notices
    @ObservationIgnored private let front: @MainActor () -> Browser?
    @ObservationIgnored private let activate: @MainActor () -> Void
    @ObservationIgnored private let limit: Duration
    @ObservationIgnored private var waiting: ItemAppLink?
    @ObservationIgnored private var routing: Task<Void, Never>?
    @ObservationIgnored private var pause: Once?
    @ObservationIgnored private let windows = NSHashTable<Browser>.weakObjects()

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
        waiting = ItemAppLink(url)
        pause?.resume()
        guard waiting != nil else {
            refuse(.malformed)
            return
        }
        if routing == nil { routing = Task { await route() } }
    }

    /// Counts `browser`'s window among the main windows open, for as long as the browser lives.
    func register(_ browser: Browser) {
        windows.add(browser)
    }

    /// The item `browser`'s window is to open, once, while it shows `library`: nil where the request is another
    /// window's. A request for a library the windows have since left is dropped, as its check was against that one;
    /// an item gone since it was checked is told.
    func take(for browser: Browser, in library: any ItemLibrary) -> Item? {
        guard let request, library.isLoaded else { return nil }
        guard request.library == ObjectIdentifier(library) else {
            self.request = nil
            return nil
        }
        // A window the link was meant for that has since closed leaves it to any other.
        if let target = request.target, target != ObjectIdentifier(browser),
           windows.allObjects.contains(where: { ObjectIdentifier($0) == target }) { return nil }
        self.request = nil
        guard let item = library.item(request.item) else {
            refuse(.notFound)
            return nil
        }
        return item
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
            guard let (route, library) = await decide(link), waiting == link else { continue }
            if route == .wait {
                guard ContinuousClock.now < deadline else {
                    waiting = nil
                    refuse(.stillOpening)
                    return
                }
                await standingChanges(until: deadline)
                continue
            }
            waiting = nil
            switch route {
            case .open(let item):
                guard let library else { continue }
                Telemetry.logger(.navigation).info("item link opens an item")
                activate()
                let target = front() ?? windows.allObjects.first
                request = Request(item: item, target: target.map(ObjectIdentifier.init), library: ObjectIdentifier(library))
                if target == nil { openMainWindow?() }
            case .refuse(let refusal):
                refuse(refusal)
            case .wait:
                break
            }
        }
    }

    /// The route for `link` and the library it was decided on; nil where the library changed while its copy was asked
    /// which Marfa it is, so the link is decided again.
    private func decide(_ link: ItemAppLink) async -> (ItemLinkRoute, (any ItemLibrary)?)? {
        let before = standing()
        guard before.mode == .marfa, let library = before.library, library.isLoaded else {
            let route = ItemLinkRoute.decide(link, mode: before.mode, isLoaded: false, instanceID: nil, holds: false)
            return (route, nil)
        }
        let instanceID = await library.instanceID()
        let after = standing()
        guard after.mode == .marfa, let still = after.library, ObjectIdentifier(still) == ObjectIdentifier(library) else { return nil }
        let route = ItemLinkRoute.decide(
            link, mode: after.mode, isLoaded: library.isLoaded, instanceID: instanceID, holds: library.item(link.item) != nil)
        return (route, library)
    }

    private func refuse(_ refusal: ItemLinkRefusal) {
        Telemetry.logger(.navigation).info("item link refused: \(String(describing: refusal), privacy: .public)")
        activate()
        notices.tell(refusal.title, refusal.message, action: refusal.action)
    }

    /// Returns once what the windows show changes, a newer link comes, or at `deadline`.
    private func standingChanges(until deadline: ContinuousClock.Instant) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = Once(continuation)
            pause = once
            withObservationTracking {
                _ = standing().library?.isLoaded
            } onChange: {
                Task { @MainActor in once.resume() }
            }
            once.sleeper = Task { @MainActor in
                try? await Task.sleep(until: deadline)
                once.resume()
            }
        }
        pause = nil
    }

    /// Resumes a wait once, by whichever comes first, and stops the other.
    private final class Once {
        private var continuation: CheckedContinuation<Void, Never>?
        var sleeper: Task<Void, Never>?

        init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

        func resume() {
            sleeper?.cancel()
            sleeper = nil
            continuation?.resume()
            continuation = nil
        }
    }
}
