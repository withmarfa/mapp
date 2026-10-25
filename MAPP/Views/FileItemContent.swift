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
    @State private var zoom = 1.0
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
                if type.conforms(to: .image) {
                    Button("Zoom Out", systemImage: "minus.magnifyingglass") { zoom = max(0.25, zoom - 0.25) }
                    Button("Zoom In", systemImage: "plus.magnifyingglass") { zoom = min(4, zoom + 0.25) }
                    Button("Fit") { zoom = 1 }
                }
                Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
            }
            .padding()
            if type.conforms(to: .pdf) {
                FilePDFPreview(url: url)
            } else if type.conforms(to: .image) {
                FileImageView(url: url, title: title, zoom: zoom)
            } else {
                FileQuickLookView(url: url, title: title, type: type)
            }
        }
        .id(url)
    }
}

/// Reads the document once for its file, rather than each time the preview's body runs.
private struct FilePDFPreview: View {
    let url: URL
    @State private var loaded: (url: URL, document: PDFDocument?)?

    var body: some View {
        Group {
            if let loaded, loaded.url == url {
                if let document = loaded.document {
                    FilePDFView(document: document)
                } else {
                    ContentUnavailableView("Can’t Preview This PDF", systemImage: "doc", description: Text("The file may be damaged or unavailable. Try opening it in another app."))
                }
            }
        }
        .task(id: url) { loaded = (url, PDFDocument(url: url)) }
    }
}

private struct FilePDFView: NSViewRepresentable {
    let document: PDFDocument
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

/// Decodes the image once for its file, off the main actor, since the body runs again on every zoom and resize.
private struct FileImageView: View {
    let url: URL
    let title: String
    let zoom: Double
    @State private var decoded: (url: URL, image: NSImage?)?

    var body: some View {
        GeometryReader { geometry in
            if let decoded, decoded.url == url {
                if let image = decoded.image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(width: max(1, geometry.size.width) * zoom, height: max(1, geometry.size.height) * zoom)
                            .accessibilityLabel(title)
                    }
                } else {
                    ContentUnavailableView("Can’t Preview This Image", systemImage: "photo", description: Text("Open the file in another app to view it."))
                }
            }
        }
        .task(id: url) {
            let image = await Self.decode(url)
            guard !Task.isCancelled else { return }
            decoded = (url, image.map { NSImage(cgImage: $0, size: .zero) })
        }
    }

    @concurrent private static func decode(_ url: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 3000,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
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
