import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers
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
    private(set) var scrollOffset: CGFloat = 0
    private(set) var isHeaderScrolledAway = false
    private(set) var findBarHeight: CGFloat = 0
    @ObservationIgnored private var headerHeight: CGFloat = 0
    /// Whether the note on the page can be changed; a deleted note cannot.
    private(set) var isEditable = true
    /// Whether the window is asking which images to attach to the note, from the toolbar or the menu bar.
    var isChoosingImages = false

    /// An edit to a note, with the markdown the note now holds.
    @ObservationIgnored var onChange: (ItemID, String) -> Void = { _, _ in }
    /// A note the page has moved on from, once any edit to it has been handed over.
    @ObservationIgnored var onLeave: (ItemID) -> Void = { _ in }
    /// The library the notes come from: their text, and the files a note points at. Given when the editor is made,
    /// so no note is ever shown before its text can be read.
    @ObservationIgnored private(set) weak var library: (any ItemLibrary)?
    @ObservationIgnored private let embeds = EmbeddedFiles()
    /// The embedded file the context menu is opening over, which it offers to open.
    @ObservationIgnored private(set) var menuEmbed: (item: ItemID, reference: EmbedReference)?
    /// Escape in the page, which hands the keyboard back to the list.
    @ObservationIgnored var onEscape: () -> Void = {}

    @ObservationIgnored let webView: EditorWebView
    /// The page with the system find bar above it, which is what the window shows.
    @ObservationIgnored let container: EditorContainer
    @ObservationIgnored private var pageFinder: PageFinder!

    /// The note on the page, and the markdown the page holds for it as far as the app knows.
    private(set) var noteID: ItemID?
    @ObservationIgnored private var markdown = ""
    /// Each load gets a generation, and an edit reports the one it belongs to, so a late edit to the previous
    /// note still reaches that note rather than the one now showing.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var notesByGeneration: [Int: ItemID] = [:]
    @ObservationIgnored private var wantsFocus = false
    @ObservationIgnored private var style = PageStyle()
    @ObservationIgnored private var pageURL: URL?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    /// Every editor open, so their edits can be handed over before the app quits or changes folder.
    @ObservationIgnored private static let open = NSHashTable<EditorController>.weakObjects()

    init(library: any ItemLibrary) {
        self.library = library
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.setURLSchemeHandler(embeds, forURLScheme: EmbeddedFiles.scheme)
        webView = EditorWebView(frame: .zero, configuration: configuration)
        container = EditorContainer(webView: webView)
        super.init()
        pageFinder = PageFinder(controller: self)
        pageFinder.finder.findBarContainer = container
        container.onFindBarVisibilityChange = { [weak self] visible in
            self?.call("setFinding", String(visible))
        }
        container.onFindBarHeightChange = { [weak self] height in self?.findBarHeight = height }
        Self.open.add(self)
        webView.controller = self
        embeds.resolve = { [weak self] reference, item in await self?.library?.embeddedFile(reference, in: item) }
        configuration.userContentController.addScriptMessageHandler(embeds, contentWorld: .page, name: "embeds")
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
        webView.showsWindowBackground()
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
    func load(_ item: Item) {
        if noteID != nil, noteID != item.id { flush() }
        scrollOffset = 0
        isHeaderScrolledAway = false
        show(item, as: "load")
    }

    func setHeaderHeight(_ height: CGFloat) {
        guard height != headerHeight else { return }
        headerHeight = height
        isHeaderScrolledAway = height > 0 && scrollOffset >= height
        if isReady { call("setHeaderHeight", String(Double(height))) }
    }

    /// The note changed from elsewhere, another window say, or was deleted or recovered. The page takes the new
    /// text where the caret is.
    func noteChanged(_ item: Item) {
        guard item.id == noteID else { return load(item) }
        guard let body = library?.body(of: item.id), body.text != markdown || item.isWritable != isEditable else { return }
        show(item, as: "reload")
    }

    /// A note whose text cannot be read is not shown at all: an empty page would take typing and save it over the
    /// note. The note shown before is left, so nothing on the page acts for one out of sight.
    private func show(_ item: Item, as function: String) {
        guard let body = library?.body(of: item.id)?.text else { return close() }
        noteID = item.id
        markdown = body
        isEditable = item.isWritable
        guard isReady else { return }
        embeds.version += 1
        call("setItem", json(item.id.rawValue))
        generation += 1
        // A late report belongs to one of the last few loads, however quickly outside changes came in.
        notesByGeneration = notesByGeneration.filter { $0.key >= generation - 8 }
        notesByGeneration[generation] = item.id
        call(function, json(body), String(generation), String(isEditable))
    }

    /// Leaves the note once the page no longer shows it, as when nothing or several notes are selected, so the
    /// commands for the note on the page (Print, Find) stop acting on one out of sight.
    func close() {
        flush()
        noteID = nil
        isHeaderScrolledAway = false
    }

    /// Hands over an edit the page has not yet reported, as when the window closes or another note is shown,
    /// and then leaves the note, unless the page stays on it. The page answers in order, so this lands before
    /// anything asked of it later. The reply keeps this controller alive until it arrives.
    func flush(leaving: Bool = true, then done: @escaping () -> Void = {}) {
        guard let noteID else { return done() }
        guard isReady else {
            if leaving { onLeave(noteID) }
            return done()
        }
        webView.evaluateJavaScript("window.editor.flush()") { [self] result, _ in
            if let markdown = result as? String {
                if noteID == self.noteID { self.markdown = markdown }
                onChange(noteID, markdown)
            }
            if leaving { onLeave(noteID) }
            done()
        }
    }

    /// Hands over every open editor's last edit, then carries on; with `leaving` off, the pages stay on their
    /// notes, as before a note is deleted, since a note in Recently Deleted takes no edit. A page that does not
    /// answer within a couple of seconds is not waited for.
    static func flushAll(leaving: Bool = true, then done: @escaping () -> Void) {
        let editors = open.allObjects
        let gate = Gate(waitingFor: editors.count, then: done)
        for editor in editors { editor.flush(leaving: leaving, then: gate.arrive) }
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

    /// Gives the page the keyboard: now if it is ready and in a window, otherwise once it is, as when the page
    /// comes back after Marfa Types. One request, never repeated.
    func focus() {
        guard isReady, let window = webView.window else {
            wantsFocus = true
            return
        }
        wantsFocus = false
        window.makeFirstResponder(webView)
        call("focus")
    }

    /// The page is in a window again, where a request for the keyboard made while it was out can be granted.
    func pageDidMoveToWindow() {
        if wantsFocus, webView.window != nil { focus() }
    }

    /// How the page is set out: its width, its text size and whether spelling is checked.
    func setStyle(_ style: PageStyle) {
        self.style = style
        if isReady { applyStyle() }
    }

    private func applyStyle() {
        call("setFullWidth", String(style.fullWidth))
        call("setTextSize", String(style.textSize))
        call("setReadingWidth", String(style.readingWidth))
        call("setSpellcheck", String(style.checksSpelling))
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
            let embeds: [Embed]
            do {
                embeds = try await library.attach(files, to: noteID)
            } catch {
                library.failure = (String(localized: "Can’t Attach Images"), String(localized: "The images weren’t added to the note. \(error.localizedDescription)"))
                return
            }
            // The images are kept either way; they go into the note only if it is still the one on the page.
            guard self.noteID == noteID, isEditable else { return }
            let images = embeds.map { ["src": $0.link, "alt": $0.name] }
            guard !images.isEmpty else { return }
            if let point {
                call("insertImages", json(images), String(Double(point.x)), String(Double(point.y)), String(Double(height)))
            } else {
                call("insertImages", json(images))
            }
        }
        return true
    }

    // MARK: Printing

    /// The note's title, which names a print job and an exported file.
    private var title: String {
        noteID.flatMap { library?.item($0)?.title } ?? String(localized: "Note")
    }

    /// Prints the note as the page shows it, laid out for paper, through the system's print panel.
    func printNote() {
        guard hasNote, let window = webView.window else { return }
        printOperation(Self.printInfo)
            .runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Asks where to save the note as a PDF, laid out as it prints, and saves it there.
    func exportPDF() {
        guard hasNote, let window = webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = NoteText.fileSafe(title)
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            exportPDF(to: url)
        }
    }

    /// Saves the note as a PDF at the URL, without asking anything.
    func exportPDF(to url: URL) {
        guard hasNote, let window = webView.window else { return }
        let info = Self.printInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = printOperation(info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// The person's paper and printer, taken fresh for each job.
    private static var printInfo: NSPrintInfo {
        NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
    }

    private func printOperation(_ info: NSPrintInfo) -> NSPrintOperation {
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        let operation = webView.printOperation(with: info)
        operation.jobTitle = title
        // WebKit's print view lays the note out for paper only once it has a size to start from.
        operation.view?.frame = webView.bounds
        return operation
    }

    // MARK: Embedded files

    /// Opens a file the note embeds in the app the system opens it with, or shows it in the Finder.
    func openEmbed(_ reference: EmbedReference, in item: ItemID, revealing: Bool = false) {
        Task {
            guard let url = await library?.embeddedFile(reference, in: item) else { return }
            if revealing {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// The embed the context menu opening now is over, heard from the page just before; each menu takes it once.
    func takeMenuEmbed() -> (item: ItemID, reference: EmbedReference)? {
        defer { menuEmbed = nil }
        return menuEmbed
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
            applyStyle()
            call("setHeaderHeight", String(Double(headerHeight)))
            if let noteID {
                embeds.version += 1
                call("setItem", json(noteID.rawValue))
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
            if id == noteID, generation != self.generation, let item = library?.item(id) { noteChanged(item) }
        case .state(let state):
            if state != caret { caret = state }
        case .scrolled(let offset, let generation):
            guard generation == self.generation else { return }
            scrollOffset = max(0, offset)
            isHeaderScrolledAway = headerHeight > 0 && scrollOffset >= headerHeight
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
        case .openEmbed(let item, let reference):
            openEmbed(reference, in: item)
        case .embedMenu(let embed):
            menuEmbed = embed
        case .find(let state):
            pageFinder.update(state)
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
    /// The page never navigates: a link opens in the browser on Command-click, and nothing else loads but the
    /// frame a PDF the note embeds shows in.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isEmbed = action.targetFrame?.isMainFrame == false && action.request.url?.scheme == EmbeddedFiles.scheme
        decisionHandler(action.request.url == pageURL || isEmbed ? .allow : .cancel)
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
