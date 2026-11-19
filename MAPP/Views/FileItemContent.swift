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
                    PlainTextFilePage(text: text, title: title) { NSWorkspace.shared.open(url) }
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
            HStack {
                Text(title).interfaceFont(.headline).lineLimit(1)
                Spacer()
                Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                    .mappButton(.secondary)
            }
            .padding()
            switch FileViewKind.of(type) {
            case .pdf:
                FilePDFPreview(url: url, item: item, details: details)
            case .image:
                FileImageView(url: url, title: title, item: item, details: details)
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
    @State private var loaded: (url: URL, document: PDFDocument?)?
    @State private var viewing = FileViewing(kind: .pdf)

    var body: some View {
        let document = loaded?.url == url ? loaded?.document : nil
        Group {
            if let loaded, loaded.url == url {
                if let document {
                    FilePDFView(document: document, viewing: viewing)
                } else {
                    ContentUnavailableView("Can’t Preview This PDF", systemImage: "doc", description: Text("The file may be damaged or unavailable. Try opening it in another app."))
                }
            }
        }
        .modifier(OfferedFileView(viewing: viewing, item: item, details: details, isReady: document != nil))
        // A document with no pages, as a locked one has, has nothing to page through or zoom.
        .task(id: url) {
            let document = PDFDocument(url: url)
            loaded = (url, document.flatMap { $0.pageCount > 0 ? $0 : nil })
        }
    }
}

private struct FilePDFView: NSViewRepresentable {
    let document: PDFDocument
    let viewing: FileViewing

    func makeCoordinator() -> Coordinator { Coordinator(viewing: viewing) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.minScaleFactor = FileZoom.range.lowerBound
        view.maxScaleFactor = FileZoom.range.upperBound
        view.document = document
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            context.coordinator.attach(to: view)
        }
        switch viewing.zoom {
        case .fit:
            if !view.autoScales { view.autoScales = true }
        case .scale(let scale):
            if view.autoScales || abs(view.scaleFactor - scale) > 0.0005 {
                view.autoScales = false
                view.scaleFactor = scale
            }
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Carries the PDF view's page and size to the file's controls, and the controls' page to the view.
    final class Coordinator {
        let viewing: FileViewing
        private weak var view: PDFView?
        private var observers: [any NSObjectProtocol] = []

        init(viewing: FileViewing) {
            self.viewing = viewing
        }

        func attach(to view: PDFView) {
            detach()
            self.view = view
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pageChanged() }
                },
                center.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scaleChanged() }
                },
            ]
            viewing.showPage = { [weak self] number in
                guard let view = self?.view, let page = view.document?.page(at: number - 1) else { return }
                view.go(to: page)
            }
            viewing.reportPages(count: view.document?.pageCount ?? 0, current: currentPage(in: view))
            scaleChanged()
        }

        func detach() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            viewing.showPage = nil
        }

        private func currentPage(in view: PDFView) -> Int {
            guard let document = view.document, let page = view.currentPage else { return 1 }
            return document.index(for: page) + 1
        }

        // Both are read a turn later: the view posts them while SwiftUI is still updating it.
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
                if view.autoScales { viewing.reportFit(view.scaleFactor) } else { viewing.adopt(scale: view.scaleFactor) }
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
                }
            }
        }
        .modifier(OfferedFileView(viewing: viewing, item: item, details: details, isReady: image != nil))
        .task(id: url) {
            let image = await Self.decode(url)
            guard !Task.isCancelled else { return }
            decoded = (url, image)
        }
    }

    private func picture(_ decoded: DecodedImage, in pane: CGSize) -> some View {
        let fit = FileZoom.fitScale(content: decoded.pixelSize, in: pane) ?? 1
        let scale = viewing.zoom.scale(fit: fit)
        // Fitted, the picture is never a rounding error larger than the pane, which would show scroll bars.
        let width = decoded.pixelSize.width * scale
        let height = decoded.pixelSize.height * scale
        let isFitted = viewing.zoom == .fit
        return ScrollView([.horizontal, .vertical]) {
            Image(decorative: decoded.image, scale: 1).resizable()
                .frame(width: isFitted ? min(width, pane.width) : width, height: isFitted ? min(height, pane.height) : height)
                .accessibilityLabel(title)
                // A picture smaller than the pane sits in its middle.
                .frame(minWidth: pane.width, minHeight: pane.height)
        }
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

private enum FilePreviewFixtures {
    static func url(_ name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
    }
}

#Preview("Photo item") {
    if let url = FilePreviewFixtures.url("item-preview-photo", extension: "png") {
        FileItemContent(url: url, title: url.lastPathComponent).frame(width: 700, height: 600)
    }
}

#Preview("PDF item") {
    if let url = FilePreviewFixtures.url("item-preview-brief", extension: "pdf") {
        FileItemContent(url: url, title: url.lastPathComponent).frame(width: 700, height: 600)
    }
}

#Preview("Other file item") {
    if let url = FilePreviewFixtures.url("item-preview-file", extension: "txt") {
        FileItemContent(url: url, title: url.lastPathComponent).frame(width: 700, height: 600)
    }
}
