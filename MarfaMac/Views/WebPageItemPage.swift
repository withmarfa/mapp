import MarfaIcons
import SwiftUI

/// An item shown as an HTML document: its title and pins in the manner of the item page's header (`WebPageHeader`), then
/// the HTML filling the rest of the detail area (`WebPageView`). The document is analyzed first (`PageAnalyzer`): an
/// article is read in Reader, the article alone in the item page's text, or shown as it was written; any other page is
/// shown as it was written, with no Reader to switch to, and a mail sits centered on the surface behind pages. The
/// document is the item's own file, for a Web Page or an HTML file, or the HTML file attached to it, for a document a
/// connector keeps that way (`ItemLibrary.pageLayout(of:)`). The body is read only, and the title and properties are
/// not edited on the page, except a pinned status, which keeps its menu; the inspector shows them all.
///
/// Its pictures are the app's to give (`SealedPictures`), for this item: while some wait for the person, the page's notice
/// (`PageNotice`) at the top, above the title, says how many and loads them, as on an item's page. Its close button hides
/// it for the page until the page is opened again. The same line says a deleted item, a copy saved beside it, a held write
/// and a file the library does not have.
struct WebPageItemPage: View {
    private enum Content: Equatable {
        case loading
        /// The document in each look it has, with its pictures pointed at the app.
        case ready(Loaded)
        /// The library has no file for the item.
        case unavailable
        /// The library has one but could not get it.
        case failed
        /// The file is not an HTML page.
        case notHTML
    }

    /// What a file turned out to be, and the document to show for each look. Both are written with the pictures'
    /// `version` of the time, which the page redraws to the current one (`SealedPictures.show`).
    private nonisolated struct Loaded: Equatable, Sendable {
        nonisolated struct Document: Equatable, Sendable {
            let html: Data
            let encoding: String.Encoding
            let addresses: [URL]

            init(_ rewritten: SealedPictureRewrite.Result) {
                html = rewritten.html
                encoding = rewritten.encoding
                addresses = rewritten.addresses
            }
        }

        let analysis: PageAnalysis
        let original: Document
        /// The article's document, where the page has an article.
        let reader: Document?
        let version: Int

        func mode(choosing chosen: SourceViewMode, mailChoice: SourceViewMode?) -> SourceViewMode {
            reader == nil ? .original : analysis.mode(choosing: chosen, mailChoice: mailChoice)
        }
        func document(for mode: SourceViewMode) -> Document { mode == .reader ? reader ?? original : original }
    }

    private struct Load: Hashable {
        let id: ItemID
        let document: ItemID
        let version: ItemVersion?
        /// Counts Try Again, so a retry is the task's own: it ends with the item's, and a late answer never reaches the next.
        let attempt: Int
    }

    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.settingsLauncher) private var settingsLauncher
    @StoredPageStyle private var style
    @AppStorage(RemotePictureSetting.key) private var remotePictures = RemotePictureSetting.standard
    @AppStorage(SourceViewMode.key) private var mode = SourceViewMode.standard
    let item: Item
    /// The file that holds the HTML.
    let document: ItemID
    let runsScripts: Bool
    /// The window's unsaved drafts, where a refused status is kept for the item, as on the item page. The page also
    /// gives it the switch between its looks, which the page's corner and the menus hold.
    let drafts: DetailsPresentation
    /// Shows the item a pinned link names.
    let open: (ItemID) -> Void
    /// Told where the item's file is once it is, and nil when it is not, so the window can share it and open it in a
    /// browser. Never told of a document attached to the item.
    var onResolved: (URL?) -> Void = { _ in }
    /// Whether the page backs the toolbar with a band while the page is under it, as the item page does. A window whose
    /// toolbar draws its own background has no need.
    var backsToolbar = true

    @State private var loader = ItemFileLoader()
    @State private var content = Content.loading
    @State private var shownID: ItemID?
    @State private var pictures: SealedPictures?
    /// Whether the person closed the pictures notice on this page.
    @State private var noticeDismissal = PicturesNoticeDismissal()
    /// The look the person chose for this mail, which does not follow the choice made for articles.
    @State private var mailChoice: SourceViewMode?
    @State private var attempt = 0
    /// How far the page has scrolled, which the header follows. Read only by the views that move with it, so a scroll
    /// redraws them and not the page.
    @State private var headerScroll = HeaderScroll()
    /// How far down the title and pins reach, below the notice when there is one: the distance the page scrolls before the
    /// header is under the toolbar.
    @State private var headerHeight: CGFloat = 0
    @State private var blockHeight: CGFloat = 0
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsToolbarBackground = true
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize

    /// One step of the notice's spacing, as on the item page.
    private var noticeGap: CGFloat { CGFloat(interfaceTextSize) * 4 / 13 * 4 }

    /// What the page says, if anything: the item's own notice, then the pictures that wait unless the person put that away.
    private var notices: [PageNotice] {
        let waiting = pictures.map { noticeDismissal.isClosed(for: item.id) ? 0 : $0.waitingCount } ?? 0
        return PageNotice.all(for: item, fileIsMissing: content == .unavailable, waitingPictures: waiting)
    }

    private func run(_ notice: PageNotice) {
        notice.run(in: library, undoManager: undoManager, openWindow: openWindow, openSettings: { [settingsLauncher] in settingsLauncher?.show($0) }) { pictures?.loadWaiting() }
    }

    /// The look the page is in, once it is known.
    private var shownMode: SourceViewMode? {
        guard case .ready(let loaded) = content else { return nil }
        return loaded.mode(choosing: mode, mailChoice: mailChoice)
    }

    /// The look to show on the corner's switch, while the page has an article to switch from.
    private var offeredMode: SourceViewMode? {
        guard case .ready(let loaded) = content, loaded.reader != nil else { return nil }
        return shownMode
    }

    /// Sets the look for this mail, or the one kept for articles.
    private func choose(_ chosen: SourceViewMode) {
        if case .ready(let loaded) = content, loaded.analysis.isMail { mailChoice = chosen } else { mode = chosen }
    }

    private func offerLook() {
        drafts.offerPageLook(offeredMode.map { PageLookSwitch(item: item.id, mode: $0, choose: choose) }, for: item.id)
    }

    var body: some View {
        GeometryReader { geometry in
            let inset = style.horizontalInset(for: geometry.size.width)
            // The page runs under the toolbar and starts below the header, which is drawn over the space it leaves and
            // moves up with the page as it scrolls, as an item's header does inside its page.
            ZStack(alignment: .top) {
                pageBody(toolbarHeight: geometry.safeAreaInsets.top)
                ScrollingHeader(scroll: headerScroll) {
                    VStack(spacing: 0) {
                        // Above the title, so the page says it first. It stays in Focus, which leaves only the page.
                        if !notices.isEmpty {
                            PageNoticeView(
                                notices: notices, run: run,
                                close: notices.contains(where: \.isClosable) ? { noticeDismissal.close(for: item.id) } : nil)
                                .padding(.horizontal, inset)
                                .padding(.top, noticeGap * 3)
                                // The header's own space is under it, unless Focus has taken the header out.
                                .padding(.bottom, drafts.isFocused(on: item.id) ? noticeGap * 3 : 0)
                        }
                        // Focus leaves only the page: its title is in the toolbar and its properties are hidden.
                        if !drafts.isFocused(on: item.id) {
                            WebPageHeader(item: item, inset: inset, drafts: drafts, open: open)
                                // As far down as the header reaches, with the notice above it counted.
                                .onGeometryChange(for: CGFloat.self) { [space = Self.headerBlock] in $0.frame(in: .named(space)).maxY } action: { headerHeight = $0 }
                        }
                    }
                    .coordinateSpace(name: Self.headerBlock)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { blockHeight = $0 }
                    // Above the block too, so a page pulled past its start shows the window's color there and not the
                    // page's own.
                    .background { Color(nsColor: .windowBackgroundColor).padding(.top, -Self.overscroll) }
                }
                ScrollingToolbarBand(scroll: headerScroll, toolbarHeight: geometry.safeAreaInsets.top, isEnabled: backsToolbar && showsToolbarBackground)
            }
        }
        .accessibilityIdentifier("WebPageItemPage")
        .onAppear {
            // Opening the page again, the same item included, shows a notice the person closed.
            noticeDismissal.reopen()
            offerLook()
        }
        .onDisappear {
            drafts.offerPageLook(nil, for: item.id)
            drafts.headerScrolled(nil, for: item.id)
        }
        .onChange(of: offeredMode) { offerLook() }
        .onChange(of: item.id) { previous, _ in
            drafts.offerPageLook(nil, for: previous)
            drafts.headerScrolled(nil, for: previous)
            headerScroll.reset()
            offerLook()
        }
        .onChange(of: headerHeight) { feedAway() }
        .onChange(of: item.displayTitle) { feedAway() }
        // A header taken out by Focus reports no height of its own, so its last one is forgotten here: otherwise the
        // page would still count it as scrolled away, and the toolbar's title would stay on once the header is back.
        .onChange(of: drafts.isFocused(on: item.id)) { _, focused in
            guard focused else { return }
            headerHeight = 0
            feedAway()
        }
        // Only a shown page scrolls, so a header is never left away over an error or a page on its way.
        .onChange(of: isShowingPage) { _, showing in
            guard !showing else { return }
            headerScroll.reset()
            feedAway()
        }
        .task(id: Load(id: item.id, document: document, version: library.item(document)?.version, attempt: attempt)) { await load() }
        .onChange(of: shownMode) {
            // The pictures the other look names wait for no one while it is not shown.
            if case .ready(let loaded) = content, let shownMode { pictures?.show(loaded.document(for: shownMode).addresses, version: loaded.version) }
        }
        .onChange(of: remotePictures) { pictures?.redraw() }
        .onChange(of: library.savedPictureStates(of: item.id)) { pictures?.redraw() }
    }

    private static let headerBlock = "headerBlock"

    /// How far a page pulled past its start can show above the header.
    private static let overscroll: CGFloat = 1_000

    private var isShowingPage: Bool {
        if case .ready = content { true } else { false }
    }

    /// The page has moved to `offset` from its start, which is also where the header is.
    private func scrolled(_ offset: CGFloat) {
        headerScroll.scrolled(to: offset, isShowingPage: isShowingPage)
        feedAway()
    }

    private func feedAway() {
        let head = ScrolledHead(item: item.id, title: item.displayTitle, typeIcon: library.catalogue.icon(for: item.type))
        drafts.headerScrolled(headerScroll.isAway(headerHeight: headerHeight) ? head : nil, for: item.id)
    }

    @ViewBuilder private func pageBody(toolbarHeight: CGFloat) -> some View {
        switch content {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, blockHeight)
        case .ready(let loaded):
            let shown = loaded.mode(choosing: mode, mailChoice: mailChoice)
            let document = loaded.document(for: shown)
            WebPageView(
                html: document.html, encoding: document.encoding, pictures: pictures, runsScripts: runsScripts,
                look: SourceLook(mode: shown, isMail: loaded.analysis.isMail, page: style),
                toolbarInset: toolbarHeight, topSpace: blockHeight, scrolled: scrolled)
                .ignoresSafeArea(.container, edges: .top)
                // Each item's pictures are answered by a page made for it.
                .id(pictures.map(ObjectIdentifier.init))
        // The page's notice says so.
        case .unavailable:
            Color.clear
        case .failed:
            ContentUnavailableView {
                Label("Can’t Get This File", systemImage: "exclamationmark.icloud")
            } description: {
                Text("The app couldn’t get the file from the server. Check your connection, then try again.")
            } actions: {
                Button("Try Again") { attempt += 1 }
            }
            .padding(.top, blockHeight)
        case .notHTML:
            ContentUnavailableView {
                Label("Can’t Show This Page", systemImage: "doc.questionmark")
            } description: {
                Text("This file isn’t an HTML page.")
            }
            .padding(.top, blockHeight)
        }
    }

    private func load() async {
        onResolved(nil)
        // A change to the same item's file is shown over the page it replaces, not a blank one.
        if shownID != item.id {
            content = .loading
            mailChoice = nil
            let id = item.id
            pictures = SealedPictures(
                item: id, pictures: .standard, inFeed: { [library] in library.item(id)?.tier == .feed },
                saved: { [library] address in await library.openSavedPicture(of: id, at: address) })
        }
        shownID = item.id
        guard let pictures, WebPageFile.isHTML(library.item(document)?.fileType) else {
            content = .notHTML
            return
        }
        switch await loader.load(document, in: library) {
        case nil:
            return
        case .unavailable:
            content = .unavailable
        case .failed:
            content = .failed
        case .ready(let url):
            // The file of an item that is itself a file is the item; a document attached to one is not, so the item
            // shares and opens as it would without it.
            if document == item.id { onResolved(url) }
            let (item, version, title) = (item.id, pictures.version, item.displayTitle)
            do {
                let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                // A cancelled analysis throws, so an answer for an item the person has left never reaches the next.
                let analysis = try await PageAnalyzer.analyze(data, title: title)
                let loaded = await Task.detached(priority: .userInitiated) {
                    Loaded(
                        analysis: analysis, original: .init(SealedPictureRewrite.rewrite(data, item: item, version: version)),
                        reader: analysis.article.map {
                            .init(SealedPictureRewrite.rewrite(Data(ReaderDocument.html(for: $0).utf8), item: item, version: version))
                        },
                        version: version)
                }.value
                guard !Task.isCancelled else { return }
                pictures.show(loaded.document(for: loaded.mode(choosing: mode, mailChoice: mailChoice)).addresses, version: version)
                content = .ready(loaded)
            } catch {
                guard !Task.isCancelled else { return }
                content = .failed
            }
        }
    }
}

/// How far a web page has scrolled, for the header over its start to follow, and what that says of the toolbar.
@Observable final class HeaderScroll {
    /// The distance the page has moved from its start.
    private(set) var offset: CGFloat = 0

    /// The page has moved to `offset`. A page that is not shown (one still loading, or an error) has not moved, whatever
    /// a document on its way out reports.
    func scrolled(to offset: CGFloat, isShowingPage: Bool) { self.offset = isShowingPage ? offset : 0 }

    func reset() { offset = 0 }

    func isAway(headerHeight: CGFloat) -> Bool { Self.isAway(scrolled: offset, headerHeight: headerHeight) }

    /// Whether the header, which the page starts below, has gone under the toolbar, as the item page's has once it
    /// scrolls as far as the header is tall. Until the header has a height there is nothing to have gone.
    nonisolated static func isAway(scrolled: CGFloat, headerHeight: CGFloat) -> Bool {
        headerHeight > 0 && scrolled >= headerHeight
    }

    /// Whether the page is under the toolbar: it moves more than the point that a trackpad's settling can account for.
    nonisolated static func isUnderToolbar(scrolled: CGFloat) -> Bool { scrolled > 1 }
}

/// Moves its content up with the page, so the header scrolls as the rest of the page does. A scroll redraws only this.
private struct ScrollingHeader<Content: View>: View {
    let scroll: HeaderScroll
    @ViewBuilder let content: Content

    var body: some View { content.offset(y: -scroll.offset) }
}

/// The band behind the toolbar once the page is under it. It reads the offset itself, so a scroll redraws only this.
private struct ScrollingToolbarBand: View {
    let scroll: HeaderScroll
    let toolbarHeight: CGFloat
    let isEnabled: Bool

    var body: some View {
        ToolbarBand(toolbarHeight: toolbarHeight, isShown: isEnabled && HeaderScroll.isUnderToolbar(scrolled: scroll.offset))
    }
}

/// Whether the person closed the pictures notice, and for which item. Closing hides it for that item until the page
/// is opened again; a different item never inherits it, and neither the count of waiting pictures nor loading them
/// brings it back.
struct PicturesNoticeDismissal: Equatable {
    private var closed: ItemID?

    func isClosed(for item: ItemID) -> Bool { closed == item }

    mutating func close(for item: ItemID) { closed = item }

    /// The page is opened, again or anew.
    mutating func reopen() { closed = nil }
}

/// A page's switch between its looks, as the page's corner and the menus reach it.
struct PageLookSwitch {
    let item: ItemID
    let mode: SourceViewMode
    let choose: (SourceViewMode) -> Void
}

/// The page's head, drawn in SwiftUI from the same `PageHead` as the item page's web head: the kicker, the title, the
/// pins and the rows. The same in either look, which sets only the title's type, so changing it never moves the rows.
private struct WebPageHeader: View {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @AppStorage(PageKey.titleLines) private var titleLines = TitleLines.standard
    @AppStorage(PageKey.showsCoordinates) private var showsCoordinates = false
    @AppStorage(PageKey.pinsProperties) private var pinsProperties = false
    @StoredPageStyle private var style
    let item: Item
    let inset: CGFloat
    let drafts: DetailsPresentation
    let open: (ItemID) -> Void

    var body: some View {
        let head = PageHead(
            of: item, in: library, placements: placements, pinsProperties: pinsProperties, dateFormat: dateFormat,
            showsCoordinates: showsCoordinates)
        let textSize = CGFloat(style.textSize)
        let statusField = library.catalogue.itemTypes[item.type]?.statusField
        VStack(alignment: .leading, spacing: 0) {
            PageHeadView(item: item, head: head, statusField: statusField, drafts: drafts, open: open) {
                Text(verbatim: item.displayTitle)
                    .font(.system(size: textSize * 28 / 15, weight: .bold))
                    .tracking(-textSize * 28 / 15 * 0.022)
                    .lineLimit(TitleLines.resolved(titleLines))
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("WebPageTitle")
            }
            if let statusField, drafts.draft(for: item.id, key: statusField.key).rejected {
                Text("The value could not be saved.")
                    .font(.system(size: CGFloat(interfaceTextSize) * 10 / 13))
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, inset)
        .padding(.top, 16)
        .padding(.bottom, 12)
        // A refused status belongs to the visit, as the item page's does.
        .onChange(of: item.id) { old, _ in
            if let key = library.item(old).flatMap({ library.catalogue.itemTypes[$0.type]?.statusField?.key }) {
                drafts.draft(for: old, key: key).rejected = false
            }
        }
    }
}
