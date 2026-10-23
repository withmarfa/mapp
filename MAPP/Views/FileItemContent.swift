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
    @State private var zoom = 1.0

    private var type: UTType { UTType(filenameExtension: url.pathExtension) ?? .data }

    var body: some View {
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
                if PDFDocument(url: url) != nil {
                    FilePDFView(url: url)
                } else {
                    ContentUnavailableView("Can’t Preview This PDF", systemImage: "doc", description: Text("The file may be damaged or unavailable. Try opening it in another app."))
                }
            } else if type.conforms(to: .image) {
                FileImageView(url: url, title: title, zoom: zoom)
            } else {
                FileQuickLookView(url: url)
            }
        }
        .id(url)
    }
}

private struct FilePDFView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

private struct FileImageView: View {
    let url: URL
    let title: String
    let zoom: Double
    private var previewImage: NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 3000,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: .zero)
    }
    var body: some View {
        GeometryReader { geometry in
            if let image = previewImage {
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
}

private struct FileQuickLookView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
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
