import MarfaIcons
import SwiftUI

/// An item shown as an HTML document: its title and pins in the manner of the note page's header (`WebPageHeader`), then
/// the HTML filling the rest of the detail area (`WebPageView`). The document is analyzed first (`PageAnalyzer`): an
/// article is read in Reader, the article alone in the note page's text, or shown as it was written; any other page is
/// shown as it was written, with no Reader to switch to, and a mail sits centered on the surface behind pages. The
/// document is the item's own file, for a Web Page or an HTML file, or the HTML file attached to it, for a document a
/// connector keeps that way (`ItemLibrary.pageLayout(of:)`). The body is read only, and the title and properties are
/// not edited on the page, except a pinned status, which keeps its menu; the inspector shows them all.
///
/// Its pictures are the app's to give (`SealedPictures`), for this item: while some wait for the person, a callout at the
/// top of the page says how many and loads them, as on a note's page.
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
    @StoredPageStyle private var style
    @AppStorage(RemotePictureSetting.key) private var remotePictures = RemotePictureSetting.standard
    @AppStorage(SourceViewMode.key) private var mode = SourceViewMode.standard
    let item: Item
    /// The file that holds the HTML.
    let document: ItemID
    let runsScripts: Bool
    /// The window's unsaved drafts, where a refused status is kept for the item, as on the note page. The page also
    /// gives it the switch between its looks, which the window's toolbar and menus hold.
    let drafts: DetailsPresentation
    /// Shows the item a pinned link names.
    let open: (ItemID) -> Void
    /// Told where the item's file is once it is, and nil when it is not, so the window can share it and open it in a
    /// browser. Never told of a document attached to the item.
    var onResolved: (URL?) -> Void = { _ in }
    /// Whether the page backs the toolbar with a band while the page is under it, as the note page does. A window whose
    /// toolbar draws its own background has no need.
    var backsToolbar = true

    @State private var loader = ItemFileLoader()
    @State private var content = Content.loading
    @State private var shownID: ItemID?
    @State private var pictures: SealedPictures?
    /// The look the person chose for this mail, which does not follow the choice made for articles.
    @State private var mailChoice: SourceViewMode?
    @State private var attempt = 0
    /// How far the page has scrolled, which the header follows. Read only by the views that move with it, so a scroll
    /// redraws them and not the page.
    @State private var headerScroll = HeaderScroll()
    /// The height of the title and pins, and with the callout under them, which the page starts below.
    @State private var headerHeight: CGFloat = 0
    @State private var blockHeight: CGFloat = 0
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsToolbarBackground = true
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize

    /// One step of the callout's spacing, as on the note page.
    private var calloutGap: CGFloat { CGFloat(interfaceTextSize) * 4 / 13 * 4 }

    /// The look the page is in, once it is known.
    private var shownMode: SourceViewMode? {
        guard case .ready(let loaded) = content else { return nil }
        return loaded.mode(choosing: mode, mailChoice: mailChoice)
    }

    /// The look the header is drawn for. While the page loads it is the look it will most likely have, the one kept for
    /// articles, so the title does not change type when the page arrives.
    private var headerMode: SourceViewMode { shownMode ?? mode }

    /// The look to show on the window's switch, while the page has an article to switch from.
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
            // moves up with the page as it scrolls, as a note's header does inside its page.
            ZStack(alignment: .top) {
                pageBody(toolbarHeight: geometry.safeAreaInsets.top)
                ScrollingHeader(scroll: headerScroll) {
                    VStack(spacing: 0) {
                        WebPageHeader(item: item, inset: inset, drafts: drafts, open: open, reading: headerMode == .reader)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        // At the top of the page, clearly further from the header than from the text it belongs to.
                        if let pictures, pictures.waitingCount > 0 {
                            PicturesWaitingCallout(count: pictures.waitingCount) { pictures.loadWaiting() }
                                .padding(.horizontal, inset)
                                .padding(.top, calloutGap * 2)
                                .padding(.bottom, calloutGap * 0.75)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { blockHeight = $0 }
                    // Above the block too, so a page pulled past its start shows the window's color there and not the
                    // page's own.
                    .background { Color(nsColor: .windowBackgroundColor).padding(.top, -Self.overscroll) }
                }
                ScrollingToolbarBand(scroll: headerScroll, toolbarHeight: geometry.safeAreaInsets.top, isEnabled: backsToolbar && showsToolbarBackground)
            }
        }
        .accessibilityIdentifier("WebPageItemPage")
        .onAppear { offerLook() }
        .onDisappear {
            drafts.offerPageLook(nil, for: item.id)
            drafts.headerScrolled(away: false, for: item.id)
        }
        .onChange(of: offeredMode) { offerLook() }
        .onChange(of: item.id) { previous, _ in
            drafts.offerPageLook(nil, for: previous)
            drafts.headerScrolled(away: false, for: previous)
            headerScroll.reset()
            offerLook()
        }
        .onChange(of: headerHeight) { feedAway() }
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
        drafts.headerScrolled(away: headerScroll.isAway(headerHeight: headerHeight), for: item.id)
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
        case .unavailable:
            ContentUnavailableView {
                Label("File Unavailable", systemImage: "questionmark.folder")
            } description: {
                Text("The file for this page isn’t in Marfa.")
            }
            .padding(.top, blockHeight)
        case .failed:
            ContentUnavailableView {
                Label("Can’t Get This File", systemImage: "exclamationmark.icloud")
            } description: {
                Text("MAPP couldn’t get the file from the server. Check your connection, then try again.")
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

    /// Whether the header, which the page starts below, has gone under the toolbar, as the note page's has once it
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

/// At the top of the page while some of its pictures wait for the person, in the words and the look of the callout on a
/// note's page, which follows Mail's mailing-list banner: how many are not loaded, and a pill button that loads them.
/// Its measures are the note page's, in steps of 4/13 of the interface text size (4 points at 13).
struct PicturesWaitingCallout: View {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    let count: Int
    let load: () -> Void

    var body: some View {
        let size = CGFloat(textSize)
        let step = size * 4 / 13
        HStack(spacing: step * 3) {
            Image(systemName: "photo")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Group {
                if count == 1 {
                    Text("1 picture from another website isn’t loaded.")
                } else {
                    Text("\(count) pictures from other websites aren’t loaded.")
                }
            }
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: load) {
                if count == 1 { Text("Load Picture") } else { Text("Load Pictures") }
            }
            .buttonStyle(PicturePillStyle(step: step))
        }
        .font(.system(size: size))
        .padding(.horizontal, step * 3)
        .padding(.vertical, step * 2.5)
        .background(.quinary, in: RoundedRectangle(cornerRadius: step * 3.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PicturesWaitingCallout")
    }
}

/// A tinted pill with no border, brighter under the pointer.
private struct PicturePillStyle: ButtonStyle {
    let step: CGFloat
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(.tint)
            .padding(.horizontal, step * 3)
            .padding(.vertical, step)
            .background(.tint.opacity(hovering || configuration.isPressed ? 0.26 : 0.16), in: Capsule())
            .onHover { hovering = $0 }
    }
}

/// A page's switch between its looks, as the window's toolbar and menus reach it.
struct PageLookSwitch {
    let item: ItemID
    let mode: SourceViewMode
    let choose: (SourceViewMode) -> Void
}

/// The switch between the reader look and the source's own, remembered for every article; a mail's choice is its own.
struct SourceViewPicker: View {
    let details: DetailsPresentation

    var body: some View {
        Picker("Reader or Original", selection: Binding(get: { details.pageLook?.mode ?? .standard }, set: { details.pageLook?.choose($0) })) {
            Text("Reader").tag(SourceViewMode.reader)
            Text("Original").tag(SourceViewMode.original)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("SourceViewMode")
    }
}

/// The page's header, drawn in SwiftUI as the note page's is drawn on the web: the title, then the pins, and where the
/// item's kind has a line of its own (a page for reading) its byline above the title and its description under it. The
/// same in either look: the look sets only the title's type, so changing it never moves the pins or the lines.
/// `PageHeaderParts` gives both pages their kind, line and pins, and `PageChip` their looks.
private struct WebPageHeader: View {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @AppStorage(PageKey.titleLines) private var titleLines = TitleLines.standard
    @StoredPageStyle private var style
    let item: Item
    let inset: CGFloat
    let drafts: DetailsPresentation
    let open: (ItemID) -> Void
    /// Whether the page is shown, or is about to be, in Reader, which gives the title the reading header's serif.
    let reading: Bool

    var body: some View {
        let parts = PageHeaderParts(of: item, in: library, placements: placements, dateFormat: dateFormat)
        let step = CGFloat(interfaceTextSize) * 4 / 13
        let textSize = CGFloat(style.textSize)
        let statusField = parts.type?.statusField
        VStack(alignment: .leading, spacing: 10) {
            let byline = [parts.lead.byline?.source, parts.lead.byline?.date, parts.lead.byline?.detail].compactMap { $0 }.filter { !$0.isEmpty }
            if !byline.isEmpty { line(byline, step: step) }
            VStack(alignment: .leading, spacing: step) {
                Text(verbatim: item.displayTitle)
                    .font(reading
                        ? .system(size: textSize * 2.1, weight: .semibold, design: .serif)
                        : .system(size: textSize * 1.9, weight: .semibold))
                    .tracking(reading ? -textSize * 2.1 * 0.01 : 0)
                    .lineLimit(TitleLines.resolved(titleLines))
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("WebPageTitle")
                if let dek = parts.lead.subtitle {
                    Text(verbatim: dek)
                        .font(.system(size: textSize * 1.2, design: .serif))
                        .lineSpacing(textSize * 0.2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if !parts.pins.pins.isEmpty {
                PagePinsView(item: item, pins: parts.pins.pins, statusField: statusField, drafts: drafts, open: open)
                    .padding(.top, step * 1.5)
            }
            if let statusField, drafts.draft(for: item.id, key: statusField.key).rejected {
                Text("The value could not be saved. Please try again.")
                    .font(.system(size: CGFloat(interfaceTextSize) * 10 / 13))
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, inset)
        .padding(.top, 16)
        .padding(.bottom, 12)
        // A refused status belongs to the visit, as the note page's does.
        .onChange(of: item.id) { old, _ in
            if let key = library.item(old).flatMap({ library.catalogue.itemTypes[$0.type]?.statusField?.key }) {
                drafts.draft(for: old, key: key).rejected = false
            }
        }
    }

    /// Where a page for reading came from, when it was published and how long it takes, as one quiet line, with the
    /// switch at its trailing edge where the page has an article to read. The line is drawn where it has either, and while
    /// the page loads. The switch is always there, hidden where it is not offered, so the line keeps its height.
    private func line(_ parts: [String], step: CGFloat) -> some View {
        HStack(spacing: step * 2.5) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Circle().fill(.secondary).opacity(0.7).frame(width: 2, height: 2).accessibilityHidden(true) }
                Text(verbatim: part).lineLimit(1)
            }
            .font(.system(size: CGFloat(interfaceTextSize) * 12 / 13, weight: .medium))
            .tracking(CGFloat(interfaceTextSize) * 12 / 13 * 0.02)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("WebPageLine")
    }
}
