import AppKit

/// One open value editor: the panel under a value. The presenter keeps at most one, whoever asks.
@MainActor
protocol ValueEditSession: AnyObject {
    var request: ValueEditRequest { get }
    var model: ValueEditModel { get }
    /// The window the editor draws in, which clicks inside are not "outside".
    var window: NSWindow? { get }
    var anchor: NSView { get }
    /// Shows the editor.
    func open()
    /// Puts it away. `restoringFocus` gives the keyboard back to where it was in the window the editor came from.
    func close(restoringFocus: Bool)
    /// The anchor's window moved: follow it.
    func anchorMoved()
}

/// Opens a value in an editor under it, for the inspector's rows and the page's property rows alike: each gives what is
/// edited, a view and a rectangle in it. Nothing differs by caller.
@MainActor
final class ValueEditPresenter {
    static let shared = ValueEditPresenter()

    typealias Factory = @MainActor (ValueEditRequest, NSView, NSRect?) -> any ValueEditSession

    private(set) var session: (any ValueEditSession)?
    private let makeSession: Factory
    /// A click on the value while its editor is open closes it as an outside click; the click then asks to open it
    /// again, which would put it straight back. The value toggles instead.
    private var closedByClick: (target: String, at: Date)?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    init(makeSession: @escaping Factory = ValueEditPresenter.system) {
        self.makeSession = makeSession
    }

    var isOpen: Bool { session != nil }

    /// Opens the editor for `request` under `rect` of `anchor` (its bounds where nil), or closes it where it is the
    /// editor already open. Nothing opens for a value the item cannot take.
    func present(_ request: ValueEditRequest, anchor: NSView, rect: NSRect? = nil, now: Date = .now) {
        let target = request.target
        if let session {
            let same = session.request.target == target
            dismiss()
            if same { return }
        }
        if let closed = closedByClick {
            closedByClick = nil
            if closed.target == target, now.timeIntervalSince(closed.at) < 0.4 { return }
        }
        guard anchor.window != nil else { return }
        let new = makeSession(request, anchor, rect)
        guard new.model.isEditable else { return }
        new.model.close = { [weak self, weak new] in
            guard let self, let new, session === new else { return }
            dismiss()
        }
        session = new
        new.open()
        watch(new)
    }

    /// Closes the editor open, if any.
    func dismiss(restoringFocus: Bool = true) {
        guard let closing = session else { return }
        session = nil
        unwatch()
        closing.close(restoringFocus: restoringFocus)
    }

    /// The item on show changed: an editor for another item is for a value that is no longer there.
    func itemChanged(to id: ItemID?) {
        guard let item = session?.request.item, item != id else { return }
        dismiss(restoringFocus: false)
    }

    /// A view that anchored an editor has left its window.
    func anchorLeft(_ view: NSView) {
        if session?.anchor === view { dismiss(restoringFocus: false) }
    }

    // MARK: Watching

    private func watch(_ session: any ValueEditSession) {
        let center = NotificationCenter.default
        if let parent = session.anchor.window {
            observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.session?.anchorMoved() }
            })
            for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification, NSWindow.didEndLiveResizeNotification] {
                observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
                })
            }
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
        })
        let outside: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: outside.union([.scrollWheel, .keyDown]), handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: outside, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
        }) { monitors.append(monitor) }
    }

    private func unwatch() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Whether the editor took the event, which then goes no further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let session else { return false }
        let inside = session.window != nil && event.window === session.window
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !inside {
                closedByClick = (session.request.target, .now)
                dismiss(restoringFocus: false)
            }
        case .scrollWheel:
            // The list in the panel scrolls itself; the page or sidebar under it takes the editor away.
            if !inside, event.window === session.anchor.window { dismiss(restoringFocus: true) }
        case .keyDown where inside:
            return handleKey(event, in: session)
        default:
            break
        }
        return false
    }

    private func handleKey(_ event: NSEvent, in session: any ValueEditSession) -> Bool {
        let model = session.model
        if event.keyCode == 53 {
            dismiss()
            return true
        }
        // A date's calendar takes the arrows and Return itself.
        if case .date = model.kind { return false }
        if let text = session.window?.firstResponder as? NSTextView, text.hasMarkedText() { return false }
        switch event.keyCode {
        case 125:
            model.move(by: 1)
            return true
        case 126:
            model.move(by: -1)
            return true
        case 36, 76:
            model.submitTyped()
            return true
        default:
            break
        }
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if plain, !model.hasSearch, let characters = event.charactersIgnoringModifiers, characters.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace && $0.value >= 0x21 && $0.value < 0xF700 }) {
            model.typeAhead(characters)
            return true
        }
        return false
    }

    /// The editor a value opens in: the panel under it.
    static func system(_ request: ValueEditRequest, anchor: NSView, rect: NSRect?) -> any ValueEditSession {
        ValueEditPanelSession(request, anchor: anchor, rect: rect)
    }
}
