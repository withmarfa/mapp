#if DEBUG
import AppKit
import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation
import Marfa
import UniformTypeIdentifiers
import MarfaTesting

/// Pictures, a PDF and bookmarks for a screenshot of the gallery: made here, so no picture ships. A debug build asks for
/// them with `-MarfaMacGallerySample`.
nonisolated enum SampleGallery {
    static let flag = "-MarfaMacGallerySample"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    struct File {
        let id: String
        let title: String
        let type: String
        let mime: String
        let data: Data
        let favorite: Bool
        let daysAgo: Int
        let attachedTo: String?

        /// Quick Look picks a preview by the extension, so the file keeps one.
        var fileName: String { id + "." + (UTType(mimeType: mime)?.preferredFilenameExtension ?? "bin") }

        var hash: String { "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    }

    static let types: [Marfa.ItemType] = [
        ItemType(
            id: "core.file", label: "File", description: "A file.",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: "core.file"),
                TypeField(name: "blob_ref", type: "string", declaredBy: "core.file"),
                TypeField(name: "mime_type", type: "string", declaredBy: "core.file"),
                TypeField(name: "size_bytes", type: "integer", declaredBy: "core.file"),
            ], titleField: "title"),
        ItemType(
            id: "core.file.image", label: "Image", description: "A picture.", parent: "core.file",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: "core.file"),
                TypeField(name: "blob_ref", type: "string", declaredBy: "core.file"),
                TypeField(name: "mime_type", type: "string", declaredBy: "core.file"),
                TypeField(name: "size_bytes", type: "integer", declaredBy: "core.file"),
            ], titleField: "title"),
        ItemType(
            id: "core.bookmark", label: "Bookmark", description: "A saved web page.",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: "core.bookmark"),
                TypeField(name: "url", type: "string", declaredBy: "core.bookmark"),
                TypeField(name: "image_url", type: "string", declaredBy: "core.bookmark"),
                TypeField(name: "body", type: "string", declaredBy: "core.bookmark"),
            ], titleField: "title", bodyField: "body"),
    ]

    /// Four photographs' worth of color, a PDF, a bookmark's saved cover, and the bookmarks themselves.
    static let files: [File] = [
        File(id: "pic-beds", title: "Raised beds in the evening", type: "core.file.image", mime: "image/png",
             data: picture(top: (0.72, 0.36, 0.25), bottom: (0.26, 0.4, 0.22)), favorite: true, daysAgo: 0, attachedTo: nil),
        File(id: "pic-path", title: "The path above Durdle Door", type: "core.file.image", mime: "image/png",
             data: picture(top: (0.93, 0.62, 0.5), bottom: (0.2, 0.4, 0.42)), favorite: false, daysAgo: 1, attachedTo: nil),
        File(id: "pic-quinces", title: "Quinces from the Ashley Vale plot", type: "core.file.image", mime: "image/png",
             data: picture(top: (0.9, 0.82, 0.4), bottom: (0.55, 0.38, 0.2)), favorite: false, daysAgo: 2, attachedTo: nil),
        File(id: "pdf-quotation", title: "Kitchen quotation, Harbour Joinery", type: "core.file", mime: "application/pdf",
             data: document(title: "Kitchen quotation", lines: ["Harbour Joinery", "Worktops, units and fitting", "Total: 14,200", "Lead time: eight weeks"]),
             favorite: false, daysAgo: 3, attachedTo: nil),
        File(id: "video-resize", title: "Live resize at 120 Hz", type: "core.file", mime: "video/mp4",
             data: video(top: (0.2, 0.35, 0.55), bottom: (0.85, 0.6, 0.35)), favorite: false, daysAgo: 4, attachedTo: nil),
        File(id: "cover-bm", title: "cover.png", type: "core.file.image", mime: "image/png",
             data: picture(top: (0.35, 0.5, 0.75), bottom: (0.12, 0.2, 0.4)), favorite: false, daysAgo: 4, attachedTo: "bm-desk"),
    ]

    static func rows(now: Date) -> [Marfa.Item] {
        var rows = files.map { file -> Marfa.Item in
            let at = SampleLibrary.stamp(now.addingTimeInterval(-Double(file.daysAgo) * 86_400 - 3_600))
            return Marfa.Item(
                id: file.id, type: file.type,
                properties: ["title": .string(file.title), "blob_ref": .string(file.hash), "mime_type": .string(file.mime),
                             "size_bytes": .number(Double(file.data.count))],
                state: .active, tier: .library, version: 1, schemaVersion: 1, source: "sample", sourceId: nil, occurredAt: at,
                createdAt: at, updatedAt: at, tags: file.favorite ? [ItemTag.favorite] : [])
        }
        rows.append(SampleLibrary.row("bm-desk", type: "core.bookmark", properties: [
            "title": "A reading desk for small rooms", "url": "https://example.com/desk"], created: now - 4 * 86_400, edited: now - 4 * 86_400))
        rows.append(SampleLibrary.row("bm-cliff", type: "core.bookmark", properties: [
            "title": "The cliff path that teaches you to slow down, an evening on the Jurassic Coast",
            "url": "https://example.com/cliff", "image_url": "https://example.com/cliff.png"], created: now - 5 * 86_400, edited: now - 5 * 86_400))
        rows.append(SampleLibrary.row("note-blank", type: "core.note", properties: [:], created: now - 6 * 86_400, edited: now - 6 * 86_400))
        return rows
    }

    static func edges(now: Date) -> [Marfa.Edge] {
        files.compactMap { file in
            file.attachedTo.map {
                Marfa.Edge(
                    id: "attached-\(file.id)", fromId: file.id, toId: $0, edgeType: "attached-to", properties: [:], version: 1,
                    createdAt: SampleLibrary.stamp(now), updatedAt: SampleLibrary.stamp(now))
            }
        }
    }

    private static var directory: URL { FileManager.default.temporaryDirectory.appending(path: "marfa-mac-gallery-sample") }

    /// Writes each file's bytes where `url(forBlob:)` finds them: the fake working copy has no blobs to fetch.
    static func writeFiles() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files { try? file.data.write(to: directory.appending(path: file.fileName)) }
    }

    /// The generated file whose blob hash is `hash`, when the gallery sample is on.
    static func url(forBlob hash: String) -> URL? {
        guard isRequested, let file = files.first(where: { $0.hash == hash }) else { return nil }
        return directory.appending(path: file.fileName)
    }

    private static func picture(top: (Double, Double, Double), bottom: (Double, Double, Double)) -> Data {
        let size = CGSize(width: 640, height: 480)
        let image = NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(
                starting: NSColor(red: top.0, green: top.1, blue: top.2, alpha: 1),
                ending: NSColor(red: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1))
            gradient?.draw(in: rect, angle: 270)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return Data() }
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }

    /// A one-second clip of a single gradient, written to a temporary file and read back.
    private static func video(top: (Double, Double, Double), bottom: (Double, Double, Double)) -> Data {
        let url = FileManager.default.temporaryDirectory.appending(path: "marfa-mac-gallery-sample-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return Data() }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 480])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 480])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_32ARGB, nil, &buffer)
        guard let buffer else { return Data() }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<480 {
                let t = Double(y) / 479
                let color = [top.0 + (bottom.0 - top.0) * t, top.1 + (bottom.1 - top.1) * t, top.2 + (bottom.2 - top.2) * t].map { UInt8($0 * 255) }
                for x in 0..<640 {
                    let at = y * rowBytes + x * 4
                    bytes[at] = 255; bytes[at + 1] = color[0]; bytes[at + 2] = color[1]; bytes[at + 3] = color[2]
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        return (try? Data(contentsOf: url)) ?? Data()
    }

    private static func document(title: String, lines: [String]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        box.fill()
        title.draw(at: CGPoint(x: 60, y: 760), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 30), .foregroundColor: NSColor.black])
        for (index, line) in lines.enumerated() {
            line.draw(at: CGPoint(x: 60, y: 690 - Double(index) * 40), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.darkGray])
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
#endif
