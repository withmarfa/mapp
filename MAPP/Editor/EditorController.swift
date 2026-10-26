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
    /// The load whose page stopped answering a flush and was given up on, so the next flush goes ahead without it.
    @ObservationIgnored var abandonedGeneration: Int?
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
    /// The library the notes come from: their text, and the files a note points at. Given when the editor is made,
    /// so no note is ever shown before its text can be read.
    @ObservationIgnored private(set) weak var library: (any ItemLibrary)?
    @ObservationIgnored let embeds = EmbeddedFiles()
    /// The embedded file the context menu is opening over, which it offers to show, and to open where the page
    /// was told it may be.
    @ObservationIgnored var menuEmbed: (item: ItemID, reference: EmbedReference, opens: Bool)?
    /// Escape in the page, which hands the keyboard back to the list.
    @ObservationIgnored var onEscape: () -> Void = {}
    /// A link in the page names this note, which the window opens as choosing it in the list does.
    @ObservationIgnored var onOpenNote: (ItemID) -> Void = { _ in }
    /// A link in the page names no note the window can open, which is told only by a beep: nothing is made.
    @ObservationIgnored var onUnopenableLink: () -> Void = { NSSound.beep() }
    /// The heading a link asked for in the note it is opening, scrolled to once that note is on the page.
    @ObservationIgnored var pendingHeading: (note: ItemID, text: String)?
    @ObservationIgnored var isWatchingLinks = false
    @ObservationIgnored private let noteRequests = NoteRequests()
    @ObservationIgnored private let noteTitles = NoteLinks.Index()

    /// The Link to Note command, until the person has chosen a note or declined; the page waits on it.
    struct LinkRequest: Identifiable {
        let id = UUID()
        let note: ItemID
    }
    var linkRequest: LinkRequest?
    @ObservationIgnored var linking: CheckedContinuation<String?, Never>?
    @ObservationIgnored var windowIsGone = false

    @ObservationIgnored let webView: EditorWebView
    /// The page with the system find bar above it, which is what the window shows.
    @ObservationIgnored let container: EditorContainer
    @ObservationIgnored private(set) var pageFinder: PageFinder!

    /// The note on the page, and the markdown the page holds for it as far as the app knows, read from the
    /// library at `read`.
    private(set) var noteID: ItemID?
    /// An explicit selection can outlive a missing body, so its next update can retry the load.
    @ObservationIgnored var requestedNoteID: ItemID?
    @ObservationIgnored private var markdown = ""
    @ObservationIgnored private var read = ItemVersion(0)
    /// Each load gets a generation, and an edit reports the one it belongs to, so a late edit to the previous
    /// note still reaches that note rather than the one now showing, and an edit typed before the page took in
    /// newer text says it was typed on the older text.
    @ObservationIgnored var generation = 0
    @ObservationIgnored private var shown: [Int: Shown] = [:]

    private struct Shown {
        let id: ItemID
        /// The version of the text the page holds for this generation.
        var read: ItemVersion
    }
    @ObservationIgnored private var loadRequest = 0
    @ObservationIgnored private var closeDelegate: EditorCloseDelegate?
    /// Where the keyboard goes once the page shows the item: its text, after `caret` where given, or its title.
    private struct FocusWish: Equatable {
        let id: ItemID
        let onTitle: Bool
        let caret: PageCaret?
    }
    @ObservationIgnored private var wantsFocus: FocusWish?
    @ObservationIgnored var style = PageStyle()
    @ObservationIgnored private var pageURL: URL?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored var printRenderer: PrintDocumentRenderer?

    /// Every editor open, so their edits can be handed over before the app quits or changes library.
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
        if let requested = wantsFocus { focus(requested.id, onTitle: requested.onTitle, caret: requested.caret) }
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


    /// Gives the page the keyboard, in the item's text or, with `onTitle`, in its title with the title selected:
    /// now if the page is ready and in a window, otherwise once it is, as when the page comes back after the
    /// gallery. One request, never repeated. With `caret`, from quick add, the caret goes after the same text in the
    /// page, or to its end.
    func focus(_ itemID: ItemID? = nil, onTitle: Bool = false, caret: PageCaret? = nil) {
        guard let requested = itemID ?? noteID else { return }
        guard requested == noteID, isReady, let window = webView.window else {
            wantsFocus = FocusWish(id: requested, onTitle: onTitle, caret: caret)
            return
        }
        wantsFocus = nil
        window.makeFirstResponder(webView)
        if onTitle {
            call("focusTitle", json(requested.rawValue))
        } else if let caret {
            switch caret {
            case .after(let prefix): call("focusText", json(prefix))
            case .end: call("focusText", "null")
            }
        } else {
            call("focus")
        }
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
            if let requested = wantsFocus { focus(requested.id, onTitle: requested.onTitle, caret: requested.caret) }
        }
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
        // Inkkit names a heading's availability by its level, as it names the command: heading1 to heading6.
        let available = name == "heading" ? name + (argument ?? "") : name
        return table.map { caret.tables[$0] == true } ?? (caret.formats[available] == true)
    }

    func setSourceMode(_ source: Bool) {
        guard hasNote, isReady else { return }
        call("setEditingMode", json(source ? "source" : "formatted"), String(generation))
    }

    func undo() { call("undo", String(generation)) }
    func redo() { call("redo", String(generation)) }

    func call(_ function: String, _ arguments: String...) {
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

    func json(_ value: some Encodable) -> String {
        String(decoding: (try? JSONEncoder().encode(value)) ?? Data("null".utf8), as: UTF8.self)
    }

    // MARK: Hearing from the page

    /// Hands an edit to the library with the version of the text it was typed on. Where the library still holds
    /// what the page last reported, the page's text is the library's at its version now, as after the library
    /// takes in the answer to the person's own save. An edit typed before the page took in newer text keeps the
    /// older version, so the library never lays it over text the person did not see.
    func report(_ markdown: String, of generation: Int) {
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
            if let requested = wantsFocus { focus(requested.id, onTitle: requested.onTitle, caret: requested.caret) }
        case .changed(let markdown, let generation):
            // A page that reports again is answering, so the next flush waits for it as before.
            if generation == abandonedGeneration { abandonedGeneration = nil }
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
            library?.notices.tell(String(localized: "Editor Couldn’t Complete the Action"), message)
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
