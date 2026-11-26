import AppKit
import ImageIO
import PDFKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// Uses system renderers without loading binary content into the Markdown editor.
struct FileItemContent: View {
    let url: URL
    /// The item's title. A Marfa file is kept under its hash, so the file's own name says nothing to the person.
    let title: String
    /// What the item's library says the file is. A Marfa file is kept under its hash with no extension, so the
    /// name says nothing there; a type the library does not know leaves it to the name.
    var contentType: UTType?
    /// The item and window the page offers an image's or a PDF's size and page to, for the corner and the menus. A
    /// page shown with neither offers nothing.
    var item: ItemID?
    var details: DetailsPresentation?
    /// The head the viewer starts below, where the page has one (`FileHeadSpace`). Only a picture and a PDF take it.
    var head: FileHeadSpace?
    @State private var textPreview: PlainTextFile.Preview?
    @State private var previewURL: URL?

    /// What a file is shown with: the library's type where it gives one, and the file's name where it does not.
    nonisolated static func type(of url: URL, contentType: UTType?) -> UTType {
        if let contentType, contentType != .data { return contentType }
        return UTType(filenameExtension: url.pathExtension) ?? .data
    }

    private var type: UTType { Self.type(of: url, contentType: contentType) }

    var body: some View {
        ZStack {
            if type.conforms(to: .plainText) {
                switch previewURL == url ? textPreview : nil {
                case .text(let text):
                    PlainTextFilePage(text: text, title: title)
                case .unsupported:
                    systemPreview
                case .unavailable:
                    ContentUnavailableView("Can’t Read This Text File", systemImage: "doc.text", description: Text("The file may have moved or become unavailable. Select it again to retry."))
                case nil:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                systemPreview
            }
        }
        .task(id: [url.absoluteString, type.identifier]) {
            textPreview = nil
            guard type.conforms(to: .plainText) else { return }
            let preview = await Task.detached(priority: .userInitiated) { PlainTextFile.read(url) }.value
            guard !Task.isCancelled else { return }
            previewURL = url
            textPreview = preview
        }
    }

    private var systemPreview: some View {
        VStack(spacing: 0) {
            switch FileViewKind.of(type) {
            case .pdf:
                FilePDFPreview(url: url, item: item, details: details, head: head)
            case .image:
                FileImageView(url: url, title: title, item: item, details: details, head: head)
            case nil:
                FileQuickLookView(url: url, title: title, type: type)
            }
        }
        // The item is part of the identity: two items can hold the same bytes, and each has its own size and page.
        .id("\(url.absoluteString)|\(item?.rawValue ?? "")")
    }
}

/// Offers a file's controls to its window once the file is ready, and withdraws them when its page goes.
private struct OfferedFileView: ViewModifier {
    let viewing: FileViewing
    let item: ItemID?
    let details: DetailsPresentation?
    let isReady: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isReady, initial: true) {
                guard let item, let details else { return }
                if isReady { details.offerFileView(viewing, for: item) } else { details.withdrawFileView(viewing) }
            }
            .onDisappear { details?.withdrawFileView(viewing) }
    }
}

/// Reads the document once for its file, rather than each time the preview's body runs.
private struct FilePDFPreview: View {
    let url: URL
    let item: ItemID?
    let details: DetailsPresentation?
    let head: FileHeadSpace?
    @State private var loaded: (url: URL, document: PDFDocument?)?
    @State private var viewing = FileViewing(kind: .pdf)

    var body: some View {
        let document = loaded?.url == url ? loaded?.document : nil
        Group {
            if let loaded, loaded.url == url {
                if let document {
                    FilePDFView(document: document, viewing: viewing, head: head)
                } else {
                    ContentUnavailableView("Can’t Preview This PDF", systemImage: "doc", description: Text("The file may be damaged or unavailable. Try opening it in another app."))
                        .padding(.top, head?.top ?? 0)
                }
            } else {
                // Something always shows, so the page keeps its height and the read below starts: a view with nothing in
                // it never runs its task.
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, head?.top ?? 0)
            }
        }
        .modifier(OfferedFileView(viewing: viewing, item: item, details: details, isReady: document != nil))
        // A document with no pages, as a locked one has, has nothing to page through or zoom. Parsed off the main
        // actor; a load that was cancelled or replaced does not show its document.
        .task(id: url) {
            let parsed = await Self.parse(url)
            guard !Task.isCancelled else { return }
            loaded = (url, parsed.document)
        }
    }

    /// PDFKit's document is not sendable. It is parsed away from the main actor and used only there afterwards.
    private nonisolated struct ParsedPDF: @unchecked Sendable {
        let document: PDFDocument?
    }

    @concurrent private static func parse(_ url: URL) async -> ParsedPDF {
        let document = PDFDocument(url: url).flatMap { $0.pageCount > 0 ? $0 : nil }
        return ParsedPDF(document: document)
    }
}

private struct FilePDFView: NSViewRepresentable {
    let document: PDFDocument
    let viewing: FileViewing
    let head: FileHeadSpace?
    @AppStorage(PDFBackground.key) private var background = PDFBackground.gray

    func makeCoordinator() -> Coordinator { Coordinator(viewing: viewing) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.minScaleFactor = FileZoom.range.lowerBound
        view.maxScaleFactor = FileZoom.range.upperBound
        view.document = document
        context.coordinator.attach(to: view)
        context.coordinator.place(head, background: background, in: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            context.coordinator.attach(to: view)
        }
        context.coordinator.apply(viewing.zoom, to: view)
        context.coordinator.place(head, background: background, in: view)
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Carries the PDF view's page and size to the file's controls, and the controls' page to the view.
    final class Coordinator {
        let viewing: FileViewing
        private weak var view: PDFView?
        /// The document Fit has sized, so a new one opens at its start.
        private weak var document: PDFDocument?
        private var observers: [any NSObjectProtocol] = []
        /// The size last given to the view, or taken from it. The view is written only when the chosen size differs from
        /// this, so an update that runs between a pinch and its being read never writes the old size back.
        private var appliedZoom: FileZoom?
        private var scrolled: ((CGFloat) -> Void)?
        private var top: CGFloat = 0
        private var toolbar: CGFloat = 0
        private var clipObserver: (any NSObjectProtocol)?
        /// The size Fit last gave the view, which the view reports back as Fit rather than as a size of its own.
        private var fitted: CGFloat?
        /// Whether Fit has sized this document yet; only that first fit goes to the start, with the head above it.
        private var hasFitted = false

        /// The scroller PDFKit keeps inside its view. It is found by type because PDFKit offers no handle to it; a view
        /// without one is left as it is, with no head inset.
        private func scroller(of view: PDFView) -> NSScrollView? {
            view.subviews.lazy.compactMap { $0 as? NSScrollView }.first
        }

        /// Starts the pages below the toolbar and the head, which scrolls with them, and sets the ground behind the
        /// pages. The PDF stays the scroller, so its gestures, zoom and find are its own.
        func place(_ head: FileHeadSpace?, background: PDFBackground, in view: PDFView) {
            view.backgroundColor = background.ground
            let white = background == .white
            if view.pageShadowsEnabled != white { view.pageShadowsEnabled = white }
            scrolled = head?.scrolled
            toolbar = head?.toolbar ?? 0
            guard let scroll = scroller(of: view) else { return }
            let newTop = head?.top ?? 0
            if clipObserver == nil {
                scroll.contentView.postsBoundsChangedNotifications = true
                clipObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
                ) { [weak self, weak scroll] _ in
                    MainActor.assumeIsolated {
                        guard let self, let scroll else { return }
                        self.scrolled?(scroll.contentView.bounds.origin.y + self.top)
                    }
                }
            }
            guard newTop != top || scroll.contentInsets.top != newTop else { return }
            // A file still at its start stays there as the head grows or shrinks.
            let atStart = abs(scroll.contentView.bounds.origin.y + top) < 1
            top = newTop
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets(top: newTop, left: 0, bottom: 0, right: 0)
            scroll.scrollerInsets = NSEdgeInsets(top: toolbar, left: 0, bottom: 0, right: 0)
            if atStart {
                scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: -newTop))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        init(viewing: FileViewing) {
            self.viewing = viewing
        }

        /// Gives the view the chosen size, once for each change of it.
        func apply(_ zoom: FileZoom, to view: PDFView) {
            guard appliedZoom != zoom else { return }
            appliedZoom = zoom
            switch zoom {
            case .fit:
                fit(view)
            case .scale(let scale):
                fitted = nil
                if abs(view.scaleFactor - scale) > 0.0005 { view.scaleFactor = scale }
            }
        }

        /// Fit shows a page as wide as the boards' paper where the column has room, and as wide as the column where it
        /// has not. PDFKit's own fit fills the column, which leaves a wide window with a page far larger than the
        /// boards'.
        private func fit(_ view: PDFView) {
            guard let page = view.document?.page(at: 0) else { return }
            let box = page.bounds(for: view.displayBox)
            let width = page.rotation % 180 == 0 ? box.width : box.height
            guard width > 0 else { return }
            let scale = FileZoom.clamped(min(Self.paperWidth / width, view.scaleFactorForSizeToFit))
            // A file opened now, or at its start, goes to its start with the head above it. Any other keeps the page
            // the reader is on, which PDFKit can leave as it keeps the middle of what shows.
            let scroll = scroller(of: view)
            let atStart = !hasFitted || scroll.map { abs($0.contentView.bounds.origin.y + top) < 1 } == true
            let reading = atStart ? nil : view.currentPage
            hasFitted = true
            fitted = scale
            if abs(view.scaleFactor - scale) > 0.0005 { view.scaleFactor = scale }
            if let reading {
                if view.currentPage !== reading { view.go(to: reading) }
                return
            }
            guard let scroll else { return }
            let start = { [top] in
                scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: -top))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            start()
            // PDFKit lays the pages out again a turn later.
            DispatchQueue.main.async(execute: start)
        }

        /// The width of a page in the boards (`PDF`, `PDF-Full`).
        static let paperWidth: CGFloat = 600

        func attach(to view: PDFView) {
            detach()
            self.view = view
            appliedZoom = nil
            if view.document !== document {
                document = view.document
                hasFitted = false
            }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pageChanged() }
                },
                center.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scaleChanged() }
                },
                // Fit follows the column as the window or the panes change width.
                center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self, weak view] _ in
                    MainActor.assumeIsolated {
                        guard let self, let view, self.appliedZoom == .fit else { return }
                        self.fit(view)
                    }
                },
            ]
            view.postsFrameChangedNotifications = true
            viewing.showPage = { [weak self] number in
                guard let self, let shown = self.view, let page = shown.document?.page(at: number - 1) else { return number }
                shown.go(to: page)
                // The page's top is put at the scroller's top edge, which is under the toolbar.
                if let scroll = scroller(of: shown), toolbar > 0 {
                    let origin = scroll.contentView.bounds.origin
                    scroll.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y - toolbar))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                return currentPage(in: shown)
            }
            // Attaching happens while SwiftUI makes or updates the view, so what it reports is read a turn later.
            pageChanged()
            scaleChanged()
        }

        func detach() {
            if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
            clipObserver = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            viewing.showPage = nil
        }

        private func currentPage(in view: PDFView) -> Int {
            guard let document = view.document, let page = view.currentPage else { return 1 }
            return document.index(for: page) + 1
        }

        // Read a turn later: the view posts them while SwiftUI is still updating it.
        private func pageChanged() {
            Task { @MainActor [weak self] in
                guard let self, let view else { return }
                viewing.reportPages(count: view.document?.pageCount ?? 0, current: currentPage(in: view))
            }
        }

        /// What Fit gives while the view fits itself; a size the view took on its own, as from a pinch, becomes the
        /// chosen one.
        private func scaleChanged() {
            Task { @MainActor [weak self] in
                guard let self, let view else { return }
                // Fit has not sized a view with no pages yet, so the size it has is not one the person chose.
                if appliedZoom == .fit, fitted == nil { return }
                if let fitted, abs(view.scaleFactor - fitted) <= 0.0005 {
                    viewing.reportFit(fitted)
                } else {
                    fitted = nil
                    viewing.adopt(scale: view.scaleFactor)
                    // A size the view took on its own is now the chosen one, so it is not written back.
                    appliedZoom = viewing.zoom
                }
            }
        }
    }
}

/// Decodes the image once for its file, off the main actor, since the body runs again on every zoom and resize.
private struct FileImageView: View {
    let url: URL
    let title: String
    let item: ItemID?
    let details: DetailsPresentation?
    let head: FileHeadSpace?
    @StoredPageStyle private var style
    @State private var decoded: (url: URL, image: DecodedImage?)?
    @State private var viewing = FileViewing(kind: .image)

    /// The picture, and how large the file says it is: the bitmap is held to 3,000 pixels a side, and a size is a
    /// fraction of the file's own.
    nonisolated struct DecodedImage: Sendable {
        let image: CGImage
        let pixelSize: CGSize
    }

    var body: some View {
        let image = decoded?.url == url ? decoded?.image : nil
        GeometryReader { geometry in
            if let decoded, decoded.url == url {
                if let image = decoded.image {
                    picture(image, in: geometry.size)
                } else {
                    ContentUnavailableView("Can’t Preview This Image", systemImage: "photo", description: Text("Open the file in another app to view it."))
                        .padding(.top, head?.top ?? 0)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, head?.top ?? 0)
            }
        }
        .modifier(OfferedFileView(viewing: viewing, item: item, details: details, isReady: image != nil))
        .task(id: url) {
            let image = await Self.decode(url)
            guard !Task.isCancelled else { return }
            decoded = (url, image)
        }
    }

    /// The picture sits in the page's column under the head, with the page's own scroller, and Fit shows it whole in the
    /// column and the window's height. Larger sizes scroll both ways.
    private func picture(_ decoded: DecodedImage, in pane: CGSize) -> some View {
        let inset = head == nil ? 0 : style.horizontalInset(for: pane.width)
        let toolbar = head?.toolbar ?? 0
        let column = CGSize(width: max(pane.width - inset * 2, 1), height: max(pane.height - toolbar - 48, 1))
        let fit = FileZoom.imageFit(content: decoded.pixelSize, in: column) ?? 1
        let scale = viewing.zoom.scale(fit: fit)
        // Fitted, the picture is never a rounding error larger than the column, which would show scroll bars. A picture
        // too large for Fit's smallest size overflows its pane and scrolls.
        let isFitted = viewing.zoom == .fit && fit > FileZoom.range.lowerBound
        let width = isFitted ? min(decoded.pixelSize.width * scale, column.width) : decoded.pixelSize.width * scale
        let height = isFitted ? min(decoded.pixelSize.height * scale, column.height) : decoded.pixelSize.height * scale
        let top = head?.top ?? 0
        return ScrollView([.horizontal, .vertical]) {
            Image(decorative: decoded.image, scale: 1).resizable()
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityLabel(title)
                .padding(.horizontal, inset)
                .padding(.bottom, 24)
                .frame(minWidth: pane.width, alignment: .leading)
        }
        .contentMargins(.top, top, for: .scrollContent)
        .contentMargins(.top, toolbar, for: .scrollIndicators)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + top } action: { _, offset in head?.scrolled(offset) }
        .onChange(of: fit, initial: true) { viewing.reportFit(fit) }
    }

    @concurrent private static func decode(_ url: URL) async -> DecodedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 3000,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let size: CGSize
        if let width = properties?[kCGImagePropertyPixelWidth] as? Double, let height = properties?[kCGImagePropertyPixelHeight] as? Double,
           width >= 1, height >= 1 {
            size = FileZoom.orientedSize(width: width, height: height, orientation: properties?[kCGImagePropertyOrientation] as? Int ?? 1)
        } else {
            size = CGSize(width: image.width, height: image.height)
        }
        return DecodedImage(image: image, pixelSize: size)
    }
}

private struct FileQuickLookView: NSViewRepresentable {
    let url: URL
    let title: String
    let type: UTType

    final class Coordinator {
        var file: QuickLookFile?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The item is set once. `FileItemContent` makes a new view for another file, and setting it again on every
    /// update would have Quick Look load the file again each time.
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        // Closed once, by `dismantleNSView`: closing it again after its window closed it is a crash.
        view.shouldCloseWithWindow = false
        context.coordinator.file = QuickLookFile.copy(of: url, titled: title, as: type)
        view.previewItem = (context.coordinator.file?.url ?? url) as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {}

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.close()
        coordinator.file?.remove()
    }
}

#if DEBUG
private enum FilePreviewFixtures {
    static func url(_ name: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Design/PreviewAssets/\(name)")
    }
}

#Preview("Photo item") {
    let url = FilePreviewFixtures.url("item-preview-photo.png")
    FileItemContent(url: url, title: url.lastPathComponent).frame(width: 700, height: 600)
}

#Preview("PDF item") {
    let url = FilePreviewFixtures.url("item-preview-brief.pdf")
    FileItemContent(url: url, title: url.lastPathComponent).frame(width: 700, height: 600)
}

#Preview("Other file item") {
    let url = FilePreviewFixtures.url("item-preview-file.txt")
    FileItemContent(url: url, title: url.lastPathComponent).frame(width: 700, height: 600)
}
#endif
