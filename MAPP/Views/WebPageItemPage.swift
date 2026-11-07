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
    /// The window's unsaved drafts, where a refused status is kept for the item, as on the note page.
    let drafts: DetailsPresentation
    /// Shows the item a pinned link names.
    let open: (ItemID) -> Void
    /// Told where the item's file is once it is, and nil when it is not, so the window can share it and open it in a
    /// browser. Never told of a document attached to the item.
    var onResolved: (URL?) -> Void = { _ in }

    @State private var loader = ItemFileLoader()
    @State private var content = Content.loading
    @State private var shownID: ItemID?
    @State private var pictures: SealedPictures?
    /// The look the person chose for this mail, which does not follow the choice made for articles.
    @State private var mailChoice: SourceViewMode?
    @State private var attempt = 0
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

    /// What the header's picker shows and sets: the look for this mail, or the one kept for articles.
    private var pickedMode: Binding<SourceViewMode> {
        Binding(
            get: { shownMode ?? mode },
            set: { chosen in
                if case .ready(let loaded) = content, loaded.analysis.isMail { mailChoice = chosen } else { mode = chosen }
            })
    }

    var body: some View {
        GeometryReader { geometry in
            let inset = style.horizontalInset(for: geometry.size.width)
            VStack(spacing: 0) {
                WebPageHeader(
                    item: item, inset: inset, drafts: drafts, open: open, mode: pickedMode, reading: headerMode == .reader,
                    offersReader: { if case .ready(let loaded) = content { loaded.reader != nil } else { false } }(),
                    isLoading: { if case .loading = content { true } else { false } }())
                // The header is inset like the other item pages' and the page draws to its own margin, so the line
                // sets the page apart as a document under its header.
                Divider()
                // At the top of the page, clearly further from the header than from the text it belongs to.
                if let pictures, pictures.waitingCount > 0 {
                    PicturesWaitingCallout(count: pictures.waitingCount) { pictures.loadWaiting() }
                        .padding(.horizontal, inset)
                        .padding(.top, calloutGap * 2)
                        .padding(.bottom, calloutGap * 0.75)
                }
                pageBody
            }
        }
        .accessibilityIdentifier("WebPageItemPage")
        .task(id: Load(id: item.id, document: document, version: library.item(document)?.version, attempt: attempt)) { await load() }
        .onChange(of: shownMode) {
            // The pictures the other look names wait for no one while it is not shown.
            if case .ready(let loaded) = content, let shownMode { pictures?.show(loaded.document(for: shownMode).addresses, version: loaded.version) }
        }
        .onChange(of: remotePictures) { pictures?.redraw() }
        .onChange(of: library.savedPictureStates(of: item.id)) { pictures?.redraw() }
    }

    @ViewBuilder private var pageBody: some View {
        switch content {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let loaded):
            let shown = loaded.mode(choosing: mode, mailChoice: mailChoice)
            let document = loaded.document(for: shown)
            WebPageView(
                html: document.html, encoding: document.encoding, pictures: pictures, runsScripts: runsScripts,
                look: SourceLook(mode: shown, isMail: loaded.analysis.isMail, page: style))
                // Each item's pictures are answered by a page made for it.
                .id(pictures.map(ObjectIdentifier.init))
        case .unavailable:
            ContentUnavailableView {
                Label("File Unavailable", systemImage: "questionmark.folder")
            } description: {
                Text("The file for this page isn’t in Marfa.")
            }
        case .failed:
            ContentUnavailableView {
                Label("Can’t Get This File", systemImage: "exclamationmark.icloud")
            } description: {
                Text("MAPP couldn’t get the file from the server. Check your connection, then try again.")
            } actions: {
                Button("Try Again") { attempt += 1 }
            }
        case .notHTML:
            ContentUnavailableView {
                Label("Can’t Show This Page", systemImage: "doc.questionmark")
            } description: {
                Text("This file isn’t an HTML page.")
            }
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

/// The switch between the reader look and the source's own, remembered for every article; a mail's choice is its own.
struct SourceViewPicker: View {
    @Binding var mode: SourceViewMode

    var body: some View {
        Picker("View", selection: $mode) {
            Text("Reader").tag(SourceViewMode.reader)
            Text("Original").tag(SourceViewMode.original)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("View")
        .accessibilityIdentifier("SourceViewMode")
    }
}

/// The page's header, drawn in SwiftUI as the note page's is drawn on the web: the title, then the pins, and where the
/// item's kind has a line of its own (a page for reading) its byline above the title and its description under it. The
/// same in either look: the look sets only the title's type, so the switch between the reader and the original, at the
/// trailing edge of the line above the title, never moves the pins or the lines.
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
    @Binding var mode: SourceViewMode
    /// Whether the page is shown, or is about to be, in Reader, which gives the title the reading header's serif.
    let reading: Bool
    /// Whether the page has an article to read, which is the only page the switch is offered for.
    let offersReader: Bool
    /// Whether the page may yet have an article, so the line holds the switch's place and the title stays where it is.
    let isLoading: Bool

    var body: some View {
        let parts = PageHeaderParts(of: item, in: library, placements: placements, dateFormat: dateFormat)
        let step = CGFloat(interfaceTextSize) * 4 / 13
        let textSize = CGFloat(style.textSize)
        let statusField = parts.type?.statusField
        VStack(alignment: .leading, spacing: 10) {
            let byline = [parts.lead.byline?.source, parts.lead.byline?.date, parts.lead.byline?.detail].compactMap { $0 }.filter { !$0.isEmpty }
            if offersReader || isLoading || !byline.isEmpty { line(byline, step: step) }
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
            Spacer(minLength: step * 4)
            if offersReader { SourceViewPicker(mode: $mode) } else { SourceViewPicker(mode: $mode).hidden() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("WebPageLine")
    }
}
