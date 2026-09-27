import AppKit
import Observation
import OSLog
import WebKit

private let log = Logger(subsystem: "com.withmarfa.mapp", category: "editor")

/// One window's editor: a web page running the formatted markdown editor, loaded when the window opens so
/// the first note shows without a wait, and reused for every note the window shows.
@Observable
final class EditorController: NSObject {
    private(set) var caret = CaretState()
    private(set) var isReady = false
    /// Whether the page has the keyboard, so the Format menu applies.
    var isFocused = false
    /// Whether the note on the page can be changed; a deleted note cannot.
    private(set) var isEditable = true
    /// Whether the page is scrolled from its top, so text runs beneath the toolbar.
    private(set) var isScrolled = false
    /// Whether the window is asking which images to attach to the note, from the toolbar or the menu bar.
    var isChoosingImages = false

    /// An edit to a note, with the markdown the note now holds.
    @ObservationIgnored var onChange: (Note.ID, String) -> Void = { _, _ in }
    /// A note the page has moved on from, once any edit to it has been handed over.
    @ObservationIgnored var onLeave: (Note.ID) -> Void = { _ in }
    /// The library the notes come from, for the files a note points at.
    @ObservationIgnored weak var library: NoteLibrary?
    @ObservationIgnored private let files = NoteFiles()
    /// Escape in the page, which hands the keyboard back to the list.
    @ObservationIgnored var onEscape: () -> Void = {}

    @ObservationIgnored let webView: EditorWebView
    /// The page with the system find bar above it, which is what the window shows.
    @ObservationIgnored let container: EditorContainer
    @ObservationIgnored private var pageFinder: PageFinder!

    /// The note on the page, and the markdown the page holds for it as far as the app knows.
    @ObservationIgnored private(set) var noteID: Note.ID?
    @ObservationIgnored private var markdown = ""
    /// Each load gets a generation, and an edit reports the one it belongs to, so a late edit to the previous
    /// note still reaches that note rather than the one now showing.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var notesByGeneration: [Int: Note.ID] = [:]
    @ObservationIgnored private var wantsFocus = false
    @ObservationIgnored private var pageURL: URL?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    /// Every editor open, so their edits can be handed over before the app quits or changes folder.
    @ObservationIgnored private static let open = NSHashTable<EditorController>.weakObjects()

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        webView = EditorWebView(frame: .zero, configuration: configuration)
        container = EditorContainer(webView: webView)
        super.init()
        pageFinder = PageFinder(controller: self)
        pageFinder.finder.findBarContainer = container
        container.onFindBarVisibilityChange = { [weak self] visible in
            self?.call("setFinding", String(visible))
        }
        Self.open.add(self)
        webView.controller = self
        files.root = { [weak self] in (self?.library?.store as? FolderStore)?.root }
        configuration.userContentController.addScriptMessageHandler(files, contentWorld: .page, name: "files")
        #if DEBUG
        webView.isInspectable = true
        #endif
        // The content controller retains its handlers, so a proxy keeps the cycle out.
        configuration.userContentController.add(MessageProxy(target: self), name: "host")
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            window.addEventListener('error', (event) => {
              webkit.messageHandlers.host.postMessage({ type: 'error', message: String(event.message) })
            })
            window.addEventListener('unhandledrejection', (event) => {
              webkit.messageHandlers.host.postMessage({ type: 'error', message: String(event.reason) })
            })
            """,
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemColorsDidChange), name: NSColor.systemColorsDidChangeNotification, object: nil
        )
        // The accent resolves differently in light and dark, so it is sent again when the appearance changes.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applyAccent() }
        }
        guard let url = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            preconditionFailure("editor.html missing from the bundle")
        }
        pageURL = url
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: Driving the page

    /// Shows a note, with the caret at its end. A deleted note is shown read-only. The note shown before is
    /// left once its last edit is in.
    func load(_ note: Note) {
        if noteID != nil, noteID != note.id { flush() }
        show(note, as: "load")
    }

    /// The note changed from elsewhere, another window say, or was deleted or recovered. The page takes the new
    /// text where the caret is.
    func noteChanged(_ note: Note) {
        guard note.id == noteID else { return load(note) }
        guard note.body != markdown || note.isDeleted == isEditable else { return }
        show(note, as: "reload")
    }

    private func show(_ note: Note, as function: String) {
        noteID = note.id
        markdown = note.body
        isEditable = !note.isDeleted
        guard isReady else { return }
        call("setImageBase", json(library?.directory(of: note) ?? note.directory))
        generation += 1
        // A late report can only belong to the load before this one.
        notesByGeneration = notesByGeneration.filter { $0.key >= generation - 1 }
        notesByGeneration[generation] = note.id
        call(function, json(note.body), String(generation), String(isEditable))
    }

    /// Hands over an edit the page has not yet reported, as when the window closes or another note is shown,
    /// and then leaves the note. The page answers in order, so this lands before anything asked of it later.
    /// The reply keeps this controller alive until it arrives.
    func flush(then done: @escaping () -> Void = {}) {
        guard let noteID else { return done() }
        guard isReady else {
            onLeave(noteID)
            return done()
        }
        webView.evaluateJavaScript("window.editor.flush()") { [self] result, _ in
            if let markdown = result as? String {
                if noteID == self.noteID { self.markdown = markdown }
                onChange(noteID, markdown)
            }
            onLeave(noteID)
            done()
        }
    }

    /// Hands over every open editor's last edit, then carries on. A page that does not answer within a couple
    /// of seconds is not waited for.
    static func flushAll(then done: @escaping () -> Void) {
        let editors = open.allObjects
        let gate = Gate(waitingFor: editors.count, then: done)
        for editor in editors { editor.flush(then: gate.arrive) }
        Task {
            try? await Task.sleep(for: .seconds(2))
            gate.open()
        }
    }

    private final class Gate {
        private var remaining: Int
        private var action: (() -> Void)?

        init(waitingFor count: Int, then action: @escaping () -> Void) {
            remaining = count
            self.action = action
            if count == 0 { open() }
        }

        func arrive() {
            remaining -= 1
            if remaining <= 0 { open() }
        }

        func open() {
            action?()
            action = nil
        }
    }

    /// Gives the page the keyboard: now if it is ready, otherwise once it is. One request, never repeated.
    func focus() {
        guard isReady else {
            wantsFocus = true
            return
        }
        wantsFocus = false
        guard let window = webView.window else { return }
        window.makeFirstResponder(webView)
        call("focus")
    }

    /// Formats from outside the page, as the toolbar does: the page takes the keyboard first, so the command
    /// acts where its caret was and typing carries on there.
    func apply(_ format: Format) {
        focus()
        self.format(format)
    }

    func format(_ format: Format) {
        let (name, argument) = format.command
        if let argument {
            call("format", json(name), json(argument))
        } else {
            call("format", json(name))
        }
    }

    // MARK: Find

    /// Whether a note is on the page to find in.
    var hasNote: Bool { isReady && noteID != nil }

    /// Does what an item of Edit > Find asks, through the system find bar above the page.
    func performFind(_ action: NSTextFinder.Action) {
        guard hasNote else { return }
        pageFinder.finder.performAction(action)
    }

    func findSelect(_ range: NSRange) {
        call("findSelect", String(range.location), String(NSMaxRange(range)))
    }

    func findScroll(_ range: NSRange) {
        call("findScroll", String(range.location))
    }

    func findReplace(_ range: NSRange, with text: String) {
        call("findReplace", String(range.location), String(NSMaxRange(range)), json(text))
    }

    /// Puts images into the note: into the attachments folder, and linked where they were dropped, given in the
    /// page's own coordinates, or at the caret. Whether there were images to take; they are read and placed
    /// once their files have been read, if the note is still the one on the page.
    @discardableResult
    func insertImages(_ sources: [PastedImages.Source], at point: CGPoint? = nil) -> Bool {
        guard isEditable, let noteID, library != nil, !sources.isEmpty else { return false }
        let height = webView.bounds.height
        Task {
            let files = await PastedImages.read(sources)
            guard self.noteID == noteID, isEditable, let library else { return }
            let images = library.attach(files, to: noteID).map { ["src": $0.link, "alt": $0.name] }
            guard !images.isEmpty else { return }
            if let point {
                call("insertImages", json(images), String(Double(point.x)), String(Double(point.y)), String(Double(height)))
            } else {
                call("insertImages", json(images))
            }
        }
        return true
    }

    func undo() { call("undo") }
    func redo() { call("redo") }

    private func call(_ function: String, _ arguments: String...) {
        webView.evaluateJavaScript("window.editor.\(function)(\(arguments.joined(separator: ", ")))") { _, error in
            if let error {
                let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                log.error("\(function, privacy: .public): \(detail, privacy: .public)")
            }
        }
    }

    private func json(_ value: some Encodable) -> String {
        String(decoding: (try? JSONEncoder().encode(value)) ?? Data("null".utf8), as: UTF8.self)
    }

    // MARK: Matching the system

    @objc private func systemColorsDidChange() {
        applyAccent()
    }

    /// The page's accent follows the system's, or the app's own when the system leaves it to apps.
    private func applyAccent() {
        guard isReady else { return }
        var hex: String?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            hex = NSColor.controlAccentColor.usingColorSpace(.sRGB).map {
                String(format: "#%02X%02X%02X", Int(($0.redComponent * 255).rounded()),
                       Int(($0.greenComponent * 255).rounded()), Int(($0.blueComponent * 255).rounded()))
            }
        }
        guard let hex else { return }
        webView.evaluateJavaScript("document.documentElement.style.setProperty('--accent', \(json(hex)))")
    }

    /// The page's own words, from the String Catalog.
    private func applyLabels() {
        let labels = [
            "note": String(localized: "Note"),
            "copy": String(localized: "Copy"),
            "addRow": String(localized: "Add Row"),
            "addColumn": String(localized: "Add Column"),
            "deleteRow": String(localized: "Delete Row"),
            "deleteColumn": String(localized: "Delete Column"),
            "alignLeft": String(localized: "Align Left"),
            "alignCenter": String(localized: "Align Center"),
            "alignRight": String(localized: "Align Right"),
            "row": String(localized: "Row"),
            "column": String(localized: "Column"),
        ]
        call("setLabels", json(labels))
    }

    private func applyKeymap() {
        var keymap: [String: [String]] = [:]
        for format in Format.allCases {
            guard let key = format.pageKey else { continue }
            let (name, argument) = format.command
            keymap[key] = [name] + (argument.map { [$0] } ?? [])
        }
        call("setKeymap", json(keymap))
    }

    // MARK: Hearing from the page

    fileprivate func receive(_ message: EditorMessage) {
        switch message {
        case .ready:
            isReady = true
            applyAccent()
            applyLabels()
            applyKeymap()
            if let noteID {
                if let note = library?.note(noteID) { call("setImageBase", json(library?.directory(of: note) ?? "")) }
                generation += 1
                notesByGeneration[generation] = noteID
                call("load", json(markdown), String(generation), String(isEditable))
            }
            if wantsFocus { focus() }
        case .changed(let markdown, let generation):
            guard let id = notesByGeneration[generation] else { return }
            if id == noteID, generation == self.generation { self.markdown = markdown }
            onChange(id, markdown)
            // An edit made before the note on the page was reloaded from outside lands after the reload. The
            // person's text wins, so the page takes it back, as the library now holds it.
            if id == noteID, generation != self.generation, let note = library?.note(id) { noteChanged(note) }
        case .state(let state):
            if state != caret { caret = state }
        case .openLink(let href):
            if let url = URL(string: href), let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .escape:
            onEscape()
        case .pasteImages:
            insertImages(PastedImages.sources(on: .general))
        case .find(let state):
            pageFinder.update(state)
        case .scrolled(let scrolled):
            isScrolled = scrolled
        case .error(let message):
            log.error("page error: \(message, privacy: .public)")
        }
    }
}

private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: EditorController?

    init(target: EditorController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let parsed = EditorMessage(body: message.body) else {
            // The body may hold a note, which does not belong in the log; its type says what went wrong.
            log.error("unreadable message of type \(String(describing: (message.body as? [String: Any])?["type"]), privacy: .public)")
            return
        }
        target?.receive(parsed)
    }
}

extension EditorController: WKNavigationDelegate {
    /// The page never navigates: a link opens in the browser on Command-click, and nothing else loads.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(action.request.url == pageURL ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        log.error("navigation failed: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        log.error("load failed: \(error.localizedDescription, privacy: .public)")
    }

    /// A page that crashes after working comes back with the note it held. One that never got going is not
    /// retried, since it would only fail again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard isReady, let pageURL else {
            log.error("web content process ended before the editor was ready")
            return
        }
        log.error("web content process ended; reloading")
        isReady = false
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
    }
}
