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
    @ObservationIgnored private var hasLoadedPage = false
    private(set) var isPresented = false
    /// Whether the page has the keyboard, so the Format menu applies.
    var isFocused = false
    /// Whether the item's header in the page has gone under the toolbar, which then shows the title.
    private(set) var isHeaderScrolledAway = false
    /// Whether the item's title in the page has the keyboard rather than the note's text.
    private(set) var isEditingTitle = false
    @ObservationIgnored private var header: PageHeader?
    @ObservationIgnored private var headerIconSize: Int?
    /// What the person does in the page's item header, for the window showing it to carry out.
    @ObservationIgnored var onHeaderEvent: (PageHeaderEvent) -> Void = { _ in }
    /// The window's drafts of item titles, which are saved before the window closes or the library changes.
    @ObservationIgnored var titleDrafts: DetailsPresentation?
    /// Whether the note on the page can be changed; a deleted note cannot.
    private(set) var isEditable = true
    /// Whether the window is asking which images to attach to the note, from the toolbar or the menu bar.
    var isChoosingImages = false

    /// An edit to a note, with the markdown the note now holds and the version of the text it was typed on.
    @ObservationIgnored var onChange: (ItemID, String, ItemVersion) -> Void = { _, _, _ in }
    /// A note the page has moved on from, once any edit to it has been handed over.
    @ObservationIgnored var onLeave: (ItemID) -> Void = { _ in }
    /// The library the notes come from: their text, and the files a note points at. Given when the editor is made,
    /// so no note is ever shown before its text can be read.
    @ObservationIgnored private(set) weak var library: (any ItemLibrary)?
    @ObservationIgnored private let embeds = EmbeddedFiles()
    /// The embedded file the context menu is opening over, which it offers to show, and to open where the page
    /// was told it may be.
    @ObservationIgnored private(set) var menuEmbed: (item: ItemID, reference: EmbedReference, opens: Bool)?
    /// Escape in the page, which hands the keyboard back to the list.
    @ObservationIgnored var onEscape: () -> Void = {}

    @ObservationIgnored let webView: EditorWebView
    /// The page with the system find bar above it, which is what the window shows.
    @ObservationIgnored let container: EditorContainer
    @ObservationIgnored private(set) var pageFinder: PageFinder!

    /// The note on the page, and the markdown the page holds for it as far as the app knows, read from the
    /// library at `read`.
    private(set) var noteID: ItemID?
    @ObservationIgnored private var markdown = ""
    @ObservationIgnored private var read = ItemVersion(0)
    /// Each load gets a generation, and an edit reports the one it belongs to, so a late edit to the previous
    /// note still reaches that note rather than the one now showing, and an edit typed before the page took in
    /// newer text says it was typed on the older text.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var shown: [Int: Shown] = [:]

    private struct Shown {
        let id: ItemID
        /// The version of the text the page holds for this generation.
        var read: ItemVersion
    }
    @ObservationIgnored private var loadRequest = 0
    @ObservationIgnored private var closeDelegate: EditorCloseDelegate?
    @ObservationIgnored private var wantsFocus: ItemID?
    @ObservationIgnored private var style = PageStyle()
    @ObservationIgnored private var pageURL: URL?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    /// Every editor open, so their edits can be handed over before the app quits or changes folder.
    @ObservationIgnored private static let open = NSHashTable<EditorController>.weakObjects()

    init(library: any ItemLibrary) {
        self.library = library
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(embeds, forURLScheme: EmbeddedFiles.scheme)
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
        embeds.open = { [weak self] reference, item in await self?.library?.openEmbeddedFile(reference, in: item) }
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
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.mappLabels = \(json(Self.editorLabels))", injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        pageURL = url
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: Driving the page

    /// Shows a note for reading. A deleted note is shown read-only. The note shown before is
    /// left once its last edit is in.
    func load(_ item: Item) {
        if wantsFocus != item.id { wantsFocus = nil }
        loadRequest += 1
        let request = loadRequest
        let present = { [self] in
            guard request == loadRequest else { return }
            isHeaderScrolledAway = false
            show(item, as: "load")
        }
        if noteID != nil, noteID != item.id {
            flush { kept in if kept { present() } }
        } else { present() }
    }

    /// What the page's item header shows, sent whenever it changes.
    func setHeader(_ header: PageHeader?) {
        guard header != self.header else { return }
        self.header = header
        if isReady { sendHeader() }
    }

    private func sendHeader() {
        if let size = header?.interfaceTextSize, size != headerIconSize, let icons = PageHeaderIcons(textSize: size) {
            headerIconSize = size
            call("setHeaderIcons", json(icons))
        }
        call("setHeader", header.map(json) ?? "null")
    }

    /// Shows a chip's menu under it, as a pop-up button shows its own.
    func popUpMenu(_ menu: NSMenu, under rect: CGRect) {
        // Tracking a menu runs its own event loop, which waits until the page's message has been handled.
        Task { menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY + 4), in: container) }
    }

    /// A rect in the page's window, which starts below whatever covers the web view's top, in the container's
    /// coordinates.
    private func containerRect(_ rect: CGRect, viewportHeight: Double) -> CGRect {
        let covered = max(0, webView.bounds.height - viewportHeight)
        let top = rect.minY + covered
        let inWebView = webView.isFlipped
            ? CGRect(x: rect.minX, y: top, width: rect.width, height: rect.height)
            : CGRect(x: rect.minX, y: webView.bounds.height - top - rect.height, width: rect.width, height: rect.height)
        return container.convert(inWebView, from: webView)
    }

    /// The note changed from elsewhere, another window say, or was deleted or recovered. The page takes the new
    /// text where the caret is.
    func noteChanged(_ item: Item) {
        guard item.id == noteID else { return load(item) }
        guard let body = library?.body(of: item.id) else { return }
        guard body.text != markdown || item.isWritable != isEditable else {
            // The page already holds this text, so what is typed next is typed on this version of it.
            read = body.version
            shown[generation]?.read = body.version
            return
        }
        show(item, as: "reload")
    }

    /// A note whose text cannot be read is not shown at all: an empty page would take typing and save it over the
    /// note. The note shown before is left, so nothing on the page acts for one out of sight.
    private func show(_ item: Item, as function: String) {
        guard let body = library?.body(of: item.id) else { return close() }
        if function == "load" { isPresented = true }
        noteID = item.id
        markdown = body.text
        read = body.version
        isEditable = item.isWritable
        guard isReady else { return }
        embeds.version += 1
        call("setItem", json(item.id.rawValue))
        generation += 1
        // A late report belongs to one of the last few loads, however quickly outside changes came in.
        shown = shown.filter { $0.key >= generation - 8 }
        shown[generation] = Shown(id: item.id, read: body.version)
        call(function, json(body.text), String(generation), String(isEditable))
        if let requested = wantsFocus { focus(requested) }
    }

    /// Leaves the note once the page no longer shows it, as when nothing or several notes are selected, so the
    /// commands for the note on the page (Print, Find) stop acting on one out of sight.
    func close() {
        wantsFocus = nil
        isPresented = false
        loadRequest += 1
        let request = loadRequest
        flush { [self] kept in
            guard kept, request == loadRequest else { return }
            noteID = nil
            isHeaderScrolledAway = false
            isEditingTitle = false
        }
    }

    /// Hands over an edit the page has not yet reported, as when the window closes or another note is shown,
    /// and then leaves the note, unless the page stays on it. The page answers in order, so this lands before
    /// anything asked of it later. The reply keeps this controller alive until it arrives.
    func flush(leaving: Bool = true, then done: @escaping (Bool) -> Void = { _ in }) {
        guard let noteID else { return done(true) }
        guard isReady else { return done(!hasLoadedPage) }
        let generation = generation
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        func capture() {
            guard self.noteID == noteID, self.generation == generation else { return done(false) }
            webView.evaluateJavaScript("window.editor.flush(\(generation))") { [self] result, error in
                if error != nil {
                    if ContinuousClock.now < deadline {
                        Task { try? await Task.sleep(for: .milliseconds(50)); capture() }
                    } else {
                        library?.failure = (String(localized: "Couldn’t Save Note"), String(localized: "The editor could not finish the current change. Keep this window open and try again."))
                        done(false)
                    }
                    return
                }
                if let markdown = result as? String { report(markdown, of: generation) }
                guard self.noteID == noteID, self.generation == generation else { return done(false) }
                if leaving { onLeave(noteID) }
                done(true)
            }
        }
        capture()
    }

    /// Destructive transitions proceed only once every editor has handed over its current text and its window's
    /// titles. Where the window or the library goes, a title that still cannot be saved stops them as a failed
    /// capture does, since it would otherwise be lost; where they stay, as when a note is deleted, it waits.
    static func flushAll(leaving: Bool = true, then done: @escaping (Bool) -> Void) {
        let editors = open.allObjects
        let gate = Gate(waitingFor: editors.count, then: done)
        for editor in editors {
            guard editor.saveTitles(tellingRefusal: leaving) || !leaving else {
                gate.arrive(false)
                continue
            }
            editor.flush(leaving: leaving, then: gate.arrive)
        }
        Task { try? await Task.sleep(for: .seconds(3)); gate.open(false) }
    }

    private final class Gate {
        private var remaining: Int
        private var succeeded = true
        private var action: ((Bool) -> Void)?
        init(waitingFor count: Int, then action: @escaping (Bool) -> Void) {
            remaining = count
            self.action = action
            if count == 0 { open(true) }
        }
        func arrive(_ success: Bool) {
            succeeded = succeeded && success
            remaining -= 1
            if remaining <= 0 { open(succeeded) }
        }
        func open(_ success: Bool) {
            action?(success)
            action = nil
        }
    }

    /// Tries every title the window holds unsaved, since a name taken before may be free now, leaving out items that
    /// are gone or whose title cannot be set. Whether all are saved; if not, and asked to, says which is not.
    func saveTitles(tellingRefusal: Bool) -> Bool {
        guard let drafts = titleDrafts, let library else { return true }
        var refused: (draft: String, item: String)?
        for id in drafts.unsavedTitles {
            guard let item = library.item(id), library.canSetTitle(of: item) else { continue }
            if !drafts.saveTitle(of: id, in: library, undoManager: webView.window?.undoManager), refused == nil {
                refused = (drafts.draft(for: id, key: "title").text, item.title)
            }
        }
        guard let refused else { return true }
        if tellingRefusal {
            library.failure = (String(localized: "Couldn’t Save Title"),
                               String(localized: "The title “\(refused.draft)” for “\(refused.item)” couldn’t be saved. Open the item to change the title or discard your changes."))
        }
        return false
    }

    /// Gives the page the keyboard: now if it is ready and in a window, otherwise once it is, as when the page
    /// comes back after Marfa Types. One request, never repeated.
    func focus(_ itemID: ItemID? = nil) {
        guard let requested = itemID ?? noteID else { return }
        guard requested == noteID, isReady, let window = webView.window else {
            wantsFocus = requested
            return
        }
        wantsFocus = nil
        window.makeFirstResponder(webView)
        call("focus")
    }

    func releaseFocus() {
        wantsFocus = nil
        if isReady { call("blurText", String(generation)) }
        guard let window = webView.window, let responder = window.firstResponder as? NSView,
              responder === webView || responder.isDescendant(of: webView) else { return }
        window.makeFirstResponder(nil)
    }

    /// The page is in a window again, where a request for the keyboard made while it was out can be granted.
    func pageDidMoveToWindow() {
        if let window = webView.window {
            if closeDelegate?.window !== window {
                closeDelegate?.detach()
                closeDelegate = EditorCloseDelegate(editor: self, window: window)
            }
            if let requested = wantsFocus { focus(requested) }
        }
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
        guard canApply(format) else { return }
        let (name, argument) = format.command
        if let argument {
            call("format", json(name), json(argument), String(generation))
        } else {
            call("format", json(name), "null", String(generation))
        }
    }

    func canApply(_ format: Format) -> Bool {
        guard hasNote, isEditable, caret.generation == generation else { return false }
        let (name, argument) = format.command
        let table: String? = switch name {
        case "table": "insert"
        case "addRowAbove": "addRowBefore"
        case "addRowBelow": "addRowAfter"
        case "addColumnBefore", "addColumnAfter", "deleteRow", "deleteColumn": name
        case "alignColumn": argument.map { "align" + $0.prefix(1).uppercased() + $0.dropFirst() }
        default: nil
        }
        return table.map { caret.tables[$0] == true } ?? (caret.formats[name] == true)
    }

    // MARK: Find

    /// Whether a note is on the page to find in.
    var hasNote: Bool { isPresented && isReady && noteID != nil }

    /// Does what an item of Edit > Find asks, through the system find bar above the page.
    func performFind(_ action: NSTextFinder.Action) {
        guard hasNote else { return }
        pageFinder.finder.performAction(action)
    }

    func findSelect(_ range: NSRange, state: FindState) {
        call("findSelect", String(range.location), String(NSMaxRange(range)), String(state.generation), json(state.snapshotID))
    }

    func findScroll(_ range: NSRange, state: FindState) {
        call("findScroll", String(range.location), String(state.generation), json(state.snapshotID))
    }

    func findReplace(_ range: NSRange, with text: String, state: FindState, batch: String) {
        call("findReplace", String(range.location), String(NSMaxRange(range)), json(text), String(state.generation), json(state.snapshotID), json(batch))
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

    @ObservationIgnored private var printRenderer: PrintDocumentRenderer?

    func printNote() {
        guard hasNote, let window = webView.window else { return }
        renderDocument(in: window, destination: nil)
    }

    func exportPDF() {
        guard hasNote, let window = webView.window else { return }
        let id = noteID
        let generation = generation
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = NoteText.fileSafe(title)
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url, noteID == id, self.generation == generation else { return }
            exportPDF(to: url)
        }
    }

    func exportPDF(to url: URL) {
        guard hasNote, let window = webView.window else { return }
        renderDocument(in: window, destination: url)
    }

    private func renderDocument(in window: NSWindow, destination: URL?) {
        guard printRenderer == nil, isReady, let id = noteID else { return }
        let generation = generation
        let title = title
        let renderer = PrintDocumentRenderer()
        printRenderer = renderer
        Task { [self] in
            defer { renderer.close(); printRenderer = nil }
            do {
                guard noteID == id, self.generation == generation else { return }
                let value = try await webView.callAsyncJavaScript("return await window.editor.printable(expected)", arguments: ["expected": generation], in: nil, contentWorld: .page)
                if let result = value as? [String: Any], result["snapshotError"] != nil, let message = result["message"] as? String {
                    throw NSError(domain: "MAPP.Print", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
                }
                guard let result = value as? [String: Any], let html = result["html"] as? String,
                      let revision = result["revision"] as? Int else {
                    throw NSError(domain: "MAPP.Print", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "The printable note could not finish loading.")])
                }
                guard noteID == id, self.generation == generation else { return }
                try await renderer.load(html, textSize: CGFloat(style.textSize))
                guard noteID == id, self.generation == generation, webView.window === window,
                      let current = try await webView.evaluateJavaScript("window.editor.snapshot(\(generation))") as? [String: Any],
                      current["revision"] as? Int == revision else { return }
                if let destination { try await renderer.exportPDF(to: destination) }
                else { _ = await renderer.printDocument(in: window, title: title) }
            } catch {
                guard noteID == id, self.generation == generation else { return }
                library?.failure = (String(localized: "Couldn’t Print Note"), error.localizedDescription)
            }
        }
    }

    // MARK: Embedded files

    /// Opens a file the note embeds in the app the system opens it with, or shows it in the Finder: always for
    /// one that might run when opened (`EmbeddedFiles.opens`), whatever the page asked.
    func openEmbed(_ reference: EmbedReference, in item: ItemID, revealing: Bool = false) {
        Task {
            guard let url = await library?.openEmbeddedFile(reference, in: item)?.url else { return }
            if revealing || !EmbeddedFiles.opens(url) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// The embed the context menu opening now is over, heard from the page just before; each menu takes it once.
    func takeMenuEmbed() -> (item: ItemID, reference: EmbedReference, opens: Bool)? {
        defer { menuEmbed = nil }
        return menuEmbed
    }

    func setSourceMode(_ source: Bool) {
        guard hasNote, isReady else { return }
        call("setEditingMode", json(source ? "source" : "formatted"), String(generation))
    }

    func undo() { call("undo", String(generation)) }
    func redo() { call("redo", String(generation)) }

    private func call(_ function: String, _ arguments: String...) {
        webView.evaluateJavaScript("window.editor.\(function)(\(arguments.joined(separator: ", ")))") { result, error in
            if let rejected = result as? [String: Any], let message = rejected["message"] as? String, rejected["commandError"] != nil {
                log.notice("\(function, privacy: .public) rejected: \(message, privacy: .public)")
            }
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
    private static var editorLabels: [String: String] {
        [
            "plainTextEditor": String(localized: "Plain Text"),
            "placeholder": String(localized: "Start typing…"),
            "expandCallout": String(localized: "Expand"),
            "collapseCallout": String(localized: "Collapse"),
            "diagramRendering": String(localized: "Rendering diagram…"),
            "diagramUnavailable": String(localized: "Diagram unavailable:"),
            "footnote": String(localized: "Footnote"),
            "fileLoading": String(localized: "Loading file…"),
            "fileError": String(localized: "File could not be loaded"),
            "filePreviewUnavailable": String(localized: "Preview unavailable"),
            "filePDFPreview": String(localized: "Open to view this PDF"),
            "wikiMissing": String(localized: "Link unavailable"),
            "formattedEditor": String(localized: "Note"),
            "noteReference": String(localized: "Note reference: %@. Open to edit source."),
            "sourceEditor": String(localized: "Markdown Source"),
            "copyCode": String(localized: "Copy"),
            "tableAddRow": String(localized: "Add Row"),
            "tableAddColumn": String(localized: "Add Column"),
            "tableDeleteRow": String(localized: "Delete Row"),
            "tableDeleteColumn": String(localized: "Delete Column"),
            "tableAlignLeft": String(localized: "Align Left"),
            "tableAlignCenter": String(localized: "Align Center"),
            "tableAlignRight": String(localized: "Align Right"),
            "tableMoveRow": String(localized: "Row"),
            "tableMoveColumn": String(localized: "Column"),
            "fileOpen": String(localized: "Open"),
            "fileMissing": String(localized: "File Not Found"),
            "fileRetry": String(localized: "Try Again"),
            "untitled": String(localized: "Untitled"),
            "title": String(localized: "Title"),
            "itemType": String(localized: "Item Type"),
            "status": String(localized: "Status"),
            "discardChanges": String(localized: "Discard Changes"),
            "propertyRejected": String(localized: "The value could not be saved. Please try again."),
        ]
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

    /// Hands an edit to the library with the version of the text it was typed on. Where the library still holds
    /// what the page last reported, the page's text is the library's at its version now, as after the library
    /// takes in the answer to the person's own save. An edit typed before the page took in newer text keeps the
    /// older version, so the library never lays it over text the person did not see.
    private func report(_ markdown: String, of generation: Int) {
        guard var page = shown[generation] else { return }
        let isCurrent = page.id == noteID && generation == self.generation
        if isCurrent, let body = library?.body(of: page.id), body.text == self.markdown {
            page.read = body.version
            read = body.version
            shown[generation] = page
        }
        if isCurrent { self.markdown = markdown }
        onChange(page.id, markdown, page.read)
        // An edit the library took from before a reload, as when the note was only deleted or recovered, is
        // shown again; one it kept apart from newer text leaves the page as it is.
        if !isCurrent, page.id == noteID, let item = library?.item(page.id) { noteChanged(item) }
    }

    fileprivate func receive(_ message: EditorMessage) {
        switch message {
        case .ready:
            isReady = true
            hasLoadedPage = true
            applyAccent()
            applyKeymap()
            applyStyle()
            isEditingTitle = false
            headerIconSize = nil
            sendHeader()
            if let noteID {
                embeds.version += 1
                call("setItem", json(noteID.rawValue))
                generation += 1
                shown[generation] = Shown(id: noteID, read: read)
                call("load", json(markdown), String(generation), String(isEditable))
            }
            if let requested = wantsFocus { focus(requested) }
        case .changed(let markdown, let generation):
            report(markdown, of: generation)
        case .state(let state):
            guard state.generation == generation else { return }
            if state != caret { caret = state }
        case .headerScrolledAway(let away, let generation):
            guard generation == self.generation, away != isHeaderScrolledAway else { return }
            isHeaderScrolledAway = away
        case .titleFocus(let focused):
            isEditingTitle = focused
            if focused { webView.beginEditingTitle() }
        case .titleInput(let item, let text):
            onHeaderEvent(.titleInput(item, text))
        case .titleCommit(let item, let text, let startWriting):
            onHeaderEvent(.titleCommit(item, text, startWriting: startWriting))
        case .titleDiscard(let item):
            onHeaderEvent(.titleDiscard(item))
        case .headerMenu(let menu, let item, let rect, let viewportHeight):
            onHeaderEvent(.menu(menu, item, containerRect(rect, viewportHeight: viewportHeight)))
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
            guard state.generation == generation else { return }
            pageFinder.update(state)
        case .diagnostic(let message):
            log.notice("preview diagnostic: \(message, privacy: .public)")
        case .error(let message):
            log.error("page error: \(message, privacy: .public)")
            library?.failure = (String(localized: "Editor Couldn’t Complete the Action"), message)
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
