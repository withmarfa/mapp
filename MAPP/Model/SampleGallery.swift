#if DEBUG
import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import Marfa
import MarfaTesting

/// Pictures, a PDF and bookmarks for a screenshot of the gallery: made here, so no picture ships. A debug build asks for
/// them with `-MAPPGallerySample`.
nonisolated enum SampleGallery {
    static let flag = "-MAPPGallerySample"

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
                    id: "attached-\(file.id)", sourceId: file.id, targetId: $0, edgeType: "attached-to", properties: [:], version: 1,
                    createdAt: SampleLibrary.stamp(now), updatedAt: SampleLibrary.stamp(now))
            }
        }
    }

    private static var directory: URL { FileManager.default.temporaryDirectory.appending(path: "mapp-gallery-sample") }

    /// Writes each file's bytes where `url(forBlob:)` finds them: the fake working copy has no blobs to fetch.
    static func writeFiles() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files { try? file.data.write(to: directory.appending(path: file.id)) }
    }

    /// The generated file whose blob hash is `hash`, when the gallery sample is on.
    static func url(forBlob hash: String) -> URL? {
        guard isRequested, let file = files.first(where: { $0.hash == hash }) else { return nil }
        return directory.appending(path: file.id)
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
