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
    /// Shows the item whose refused title is being told, in the window holding the draft.
    @ObservationIgnored var onShowRefusedTitle: (ItemID) -> Void = { _ in }
    /// Whether the note on the page can be changed; a deleted note cannot.
    private(set) var isEditable = true
    /// Whether the window is asking which images to attach to the note, from the toolbar or the menu bar.
    var isChoosingImages = false

    /// An edit to a note, with the markdown the note now holds and the version of the text it was typed on.
    @ObservationIgnored var onChange: (ItemID, String, ItemVersion) -> Void = { _, _, _ in }
    /// A note the page has moved on from, once any edit to it has been handed over. `closing` is true where the
    /// window or the app is going, so the note will not be shown again by this window.
    @ObservationIgnored var onLeave: (_ id: ItemID, _ closing: Bool) -> Void = { _, _ in }
    /// The library the notes come from: their text, and the files a note points at. Given when the editor is made,
    /// so no note is ever shown before its text can be read.
    @ObservationIgnored private(set) weak var library: (any ItemLibrary)?
    @ObservationIgnored private let embeds = EmbeddedFiles()
    /// The embedded file the context menu is opening over, which it offers to show, and to open where the page
    /// was told it may be.
    @ObservationIgnored private(set) var menuEmbed: (item: ItemID, reference: EmbedReference, opens: Bool)?
    /// Escape in the page, which hands the keyboard back to the list.
    @ObservationIgnored var onEscape: () -> Void = {}
    /// A link in the page names this note, which the window opens as choosing it in the list does.
    @ObservationIgnored var onOpenNote: (ItemID) -> Void = { _ in }
    /// A link in the page names no note the window can open, which is told only by a beep: nothing is made.
    @ObservationIgnored var onUnopenableLink: () -> Void = { NSSound.beep() }
    /// The heading a link asked for in the note it is opening, scrolled to once that note is on the page.
    @ObservationIgnored private var pendingHeading: (note: ItemID, text: String)?
    @ObservationIgnored private var isWatchingLinks = false
    @ObservationIgnored private let noteRequests = NoteRequests()
    @ObservationIgnored private let noteTitles = NoteLinks.Index()

    /// The Link to Note command, until the person has chosen a note or declined; the page waits on it.
    struct LinkRequest: Identifiable {
        let id = UUID()
        let note: ItemID
    }
    var linkRequest: LinkRequest?
    @ObservationIgnored private var linking: CheckedContinuation<String?, Never>?
    @ObservationIgnored private var windowIsGone = false

    @ObservationIgnored let webView: EditorWebView
    /// The page with the system find bar above it, which is what the window shows.
    @ObservationIgnored let container: EditorContainer
    @ObservationIgnored private(set) var pageFinder: PageFinder!

    /// The note on the page, and the markdown the page holds for it as far as the app knows, read from the
    /// library at `read`.
    private(set) var noteID: ItemID?
    /// An explicit selection can outlive a missing body, so its next update can retry the load.
    @ObservationIgnored private var requestedNoteID: ItemID?
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
    /// Where the keyboard goes once the page shows the item: its text, or its title.
    private struct FocusWish: Equatable {
        let id: ItemID
        let onTitle: Bool
    }
    @ObservationIgnored private var wantsFocus: FocusWish?
    @ObservationIgnored private var style = PageStyle()
    @ObservationIgnored private var pageURL: URL?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    /// Every editor open, so their edits can be handed over before the app quits or changes folder.
    @ObservationIgnored static let open = NSHashTable<EditorController>.weakObjects()

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
        noteRequests.suggest = { [weak self] query, source in
            guard let self, let current = self.library else { return [] }
            return await current.noteNames(matching: query, in: source, using: self.noteTitles)
        }
        noteRequests.pick = { [weak self] note in await self?.chooseNoteToLink(from: note) }
        noteRequests.missing = { [weak self] links, source in
            guard let library = self?.library else { return links.map { _ in false } }
            return links.map { library.resolveLink($0, in: source) == .missing }
        }
        configuration.userContentController.addScriptMessageHandler(noteRequests, contentWorld: .page, name: "notes")
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

    /// A selection is navigation intent, including returning to a note whose outgoing capture failed.
    func select(_ item: Item) {
        requestedNoteID = item.id
        if wantsFocus?.id != item.id { wantsFocus = nil }
        if pendingHeading?.note != item.id { pendingHeading = nil }
        loadRequest += 1
        if noteID == item.id, isPresented { noteChanged(item) }
        else { load(item) }
    }

    /// Shows a note for reading. A deleted note is shown read-only. The note shown before is
    /// left once its last edit is in.
    func load(_ item: Item) {
        requestedNoteID = item.id
        if wantsFocus?.id != item.id { wantsFocus = nil }
        if pendingHeading?.note != item.id { pendingHeading = nil }
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

    @ObservationIgnored private var headerSource: () -> PageHeader? = { nil }
    /// Only the latest reading of the header follows changes, so readings never pile up.
    @ObservationIgnored private var headerReading = 0

    /// Shows in the page's header what `source` builds, and again whenever anything it read changes. It is followed
    /// here rather than by a view, so the page keeps up even when the view showing it is not updated.
    func showHeader(_ source: @escaping () -> PageHeader?) {
        headerSource = source
        refreshHeader()
    }

    func refreshHeader() {
        headerReading += 1
        let reading = headerReading
        // Weak here as well as in the task, or the tracking would hold the editor until the next change.
        let header = withObservationTracking(headerSource) { [weak self] in
            // Heard before the change is made, so the header is read again once it has been.
            Task { @MainActor [weak self] in
                guard let self, headerReading == reading else { return }
                refreshHeader()
            }
        }
        setHeader(header)
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

    /// Shows a pin's menu under it, as a pop-up button shows its own.
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
        // SwiftUI can deliver a change from the page just left after another item has loaded.
        // Only an explicit selection or load may navigate; an old update must not take the page back.
        guard item.id == requestedNoteID else { return }
        guard item.id == noteID, isPresented else { return load(item) }
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
        // The request was typed into the text now being replaced, which the page would refuse an answer for.
        cancelLinkRequest()
        guard let body = library?.body(of: item.id) else { return hide() }
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
        revealPendingHeading(in: item.id)
        if let requested = wantsFocus { focus(requested.id, onTitle: requested.onTitle) }
    }

    /// Leaves the note once the page no longer shows it, as when nothing or several notes are selected, so the
    /// commands for the note on the page (Print, Find) stop acting on one out of sight.
    func close() {
        requestedNoteID = nil
        hide()
    }

    private func hide() {
        cancelLinkRequest()
        wantsFocus = nil
        pendingHeading = nil
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
    func flush(leaving: Bool = true, closing: Bool = false, then done: @escaping (Bool) -> Void = { _ in }) {
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
                if leaving { onLeave(noteID, closing) }
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
        // One refusal is told, from the window that holds it, which the library's single failure can carry.
        var told = false
        for editor in editors {
            guard editor.saveTitles(tellingRefusal: leaving && !told) || !leaving else {
                told = true
                gate.arrive(false)
                continue
            }
            editor.flush(leaving: leaving, closing: leaving, then: gate.arrive)
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

    /// The window is gone and its text already flushed, so its drafts and page take no part in later flushes, even
    /// while SwiftUI still holds the editor for a moment.
    func windowWent() {
        windowIsGone = true
        requestedNoteID = nil
        cancelLinkRequest()
        titleDrafts = nil
        Self.open.remove(self)
    }

    /// Tries every title the window holds unsaved, since a name taken before may be free now, leaving out items that
    /// are gone or whose title cannot be set. Whether all are saved; if not, and asked to, says which is not.
    func saveTitles(tellingRefusal: Bool) -> Bool {
        guard let drafts = titleDrafts, let library else { return true }
        var refused: (id: ItemID, draft: String, item: String)?
        for id in drafts.unsavedTitles {
            guard let item = library.item(id), library.canSetTitle(of: item) else { continue }
            if !drafts.saveTitle(of: id, in: library, undoManager: webView.window?.undoManager), refused == nil {
                refused = (id, drafts.draft(for: id, key: "title").text, item.title)
            }
        }
        guard let refused else { return true }
        if tellingRefusal {
            let message = refused.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "The title for “\(refused.item)” is empty. Open the item to enter a title or discard your changes.")
                : String(localized: "The title “\(refused.draft)” for “\(refused.item)” couldn’t be saved. Open the item to change the title or discard your changes.")
            library.failure = (String(localized: "Couldn’t Save Title"), message)
            // The draft is shown only in its own window, so that window comes forward with the item.
            webView.window?.makeKeyAndOrderFront(nil)
            onShowRefusedTitle(refused.id)
        }
        return false
    }

    /// Gives the page the keyboard, in the item's text or, with `onTitle`, in its title with the title selected:
    /// now if the page is ready and in a window, otherwise once it is, as when the page comes back after the
    /// gallery. One request, never repeated.
    func focus(_ itemID: ItemID? = nil, onTitle: Bool = false) {
        guard let requested = itemID ?? noteID else { return }
        guard requested == noteID, isReady, let window = webView.window else {
            wantsFocus = FocusWish(id: requested, onTitle: onTitle)
            return
        }
        wantsFocus = nil
        window.makeFirstResponder(webView)
        if onTitle { call("focusTitle", json(requested.rawValue)) } else { call("focus") }
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
            if let requested = wantsFocus { focus(requested.id, onTitle: requested.onTitle) }
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
        // InkKit names a heading's availability by its level, as it names the command: heading1 to heading6.
        let available = name == "heading" ? name + (argument ?? "") : name
        return table.map { caret.tables[$0] == true } ?? (caret.formats[available] == true)
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

    // MARK: Linking to a note

    /// Asks the person which note to link to, and gives the page the link to write, or nil if they decline or the
    /// page has moved on from the note the command was typed in. A new request cancels the earlier one. A request
    /// made after the window went is answered with nothing.
    func chooseNoteToLink(from note: ItemID) async -> String? {
        cancelLinkRequest()
        guard !windowIsGone, note == noteID, isEditable, isReady else { return nil }
        return await withCheckedContinuation { continuation in
            linking = continuation
            linkRequest = LinkRequest(note: note)
        }
    }

    /// Answers the page with the link to the note chosen, read from the library as the note is now, not as the
    /// picker listed it, and by identity, so a note renamed meanwhile is linked by its new name and one that shares
    /// its name is not mistaken for it. Whether it was answered: a note no link can name alone leaves the request
    /// open for the person to choose another.
    @discardableResult
    func finishLinkRequest(choosing id: ItemID) -> Bool {
        guard linking != nil, let source = linkRequest?.note, let link = library?.bodyLink(to: id, in: source) else { return false }
        answerLinkRequest(link)
        return true
    }

    /// Any other end of the request answers the page with nothing, so it is never left waiting.
    func cancelLinkRequest() { answerLinkRequest(nil) }

    private func answerLinkRequest(_ link: String?) {
        let continuation = linking
        linking = nil
        linkRequest = nil
        continuation?.resume(returning: link)
    }

    // MARK: Following a link

    /// Opens the note a link in `source` names, as the library reads that very link, and scrolls to the heading it asks
    /// for. A link that names no note, or more than one, or that the library has not been able to look up, opens
    /// nothing and beeps; no note is made for it. A click in a note the page has since left is ignored.
    func openNote(_ link: NoteLink, from source: ItemID) {
        guard !windowIsGone, source == noteID, let library else { return }
        guard case .resolved(let id) = library.resolveLink(link, in: source), library.item(id) != nil else {
            return onUnopenableLink()
        }
        pendingHeading = link.heading.map { (id, $0) }
        if id == noteID { revealPendingHeading(in: id) } else { onOpenNote(id) }
    }

    private func revealPendingHeading(in note: ItemID) {
        guard let pending = pendingHeading, pending.note == note, isReady else { return }
        pendingHeading = nil
        call("revealHeading", json(pending.text), String(generation))
    }

    /// Tells the page when the library's notes change, since a link there may then name a note or none. Changes
    /// come in bursts, as typing is saved, so the page hears once they pause. Followed here, as the header is, so
    /// the page keeps up whether or not a view is updated.
    private func watchLinks() {
        guard !isWatchingLinks, let library else { return }
        isWatchingLinks = true
        withObservationTracking {
            _ = library.items(in: .allNotes)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !windowIsGone else { return }
                isWatchingLinks = false
                if noteID != nil, isReady { call("linksChanged") }
                watchLinks()
            }
        }
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
        webView.evaluateJavaScript("document.documentElement.style.setProperty('--inkkit-accent-color', \(json(hex)))")
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
            "comment": String(localized: "Author Comment"),
            "preservedMarkdown": String(localized: "Preserved Markdown"),
            "suggestions": String(localized: "Suggestions"),
            "suggestionsLoading": String(localized: "Loading…"),
            "suggestionsEmpty": String(localized: "No Results"),
            "slashHeading1": String(localized: "Heading 1"),
            "slashHeading2": String(localized: "Heading 2"),
            "slashHeading3": String(localized: "Heading 3"),
            "slashBulletList": String(localized: "Bulleted List"),
            "slashOrderedList": String(localized: "Numbered List"),
            "slashTaskList": String(localized: "Checklist"),
            "slashQuote": String(localized: "Quote"),
            "slashCodeBlock": String(localized: "Code Block"),
            "slashTable": String(localized: "Table"),
            "slashCallout": String(localized: "Callout"),
            "slashDivider": String(localized: "Divider"),
            "slashDiagram": String(localized: "Diagram"),
            "slashNote": String(localized: "Note"),
            "slashTip": String(localized: "Tip"),
            "slashImportant": String(localized: "Important"),
            "slashWarning": String(localized: "Warning"),
            "slashCaution": String(localized: "Caution"),
            "linkToNote": String(localized: "Link to Note"),
            "untitled": String(localized: "Untitled"),
            "title": String(localized: "Title"),
            "itemType": String(localized: "Item Type"),
            "status": String(localized: "Status"),
            "discardChanges": String(localized: "Discard Changes"),
            "propertyRejected": String(localized: "The value could not be saved. Please try again."),
            "parentRejected": String(localized: "The connection could not be removed."),
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
            watchLinks()
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
            if let requested = wantsFocus { focus(requested.id, onTitle: requested.onTitle) }
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
        case .openNote(let item, let link):
            openNote(link, from: item)
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
        cancelLinkRequest()
        isReady = false
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
    }
}
