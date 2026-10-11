import AppKit
import PDFKit
import Testing
@testable import MAPP

@Suite(.serialized)
struct PrintDocumentTests {
    private func html() throws -> String {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<80 { for x in 0..<80 { bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: x, y: y) } }
        let image = try #require(bitmap.representation(using: .png, properties: [:])).base64EncodedString()
        return "<html><head><style>body{font:16px Helvetica} p{margin:0 0 16px} table{border-collapse:collapse}</style></head><body><h1>First heading</h1><table><tr><td>Table value</td></tr></table>"
        + (0..<150).map { "<p>Paragraph \($0): complete text belongs in the exported note.</p>" }.joined()
        + "<p>Long block begins " + String(repeating: "A wrapped line remains intact. ", count: 100) + "Long block complete</p>"
        + "<img alt='Image' width='80' height='80' src='data:image/png;base64,\(image)'><p>Last complete tail</p></body></html>"
    }

    @Test func longDocumentExportsCompleteBoundedPages() async throws {
        let renderer = PrintDocumentRenderer()
        defer { renderer.close() }
        try await renderer.load(html())
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "long.pdf")
        try await renderer.exportPDF(to: url)
        let document = try #require(PDFDocument(url: url))
        #expect((3...20).contains(document.pageCount))
        #expect(document.string?.contains("First heading") == true)
        #expect(document.string?.contains("Table value") == true)
        #expect(document.string?.contains("Paragraph 149") == true)
        #expect(document.string?.contains("Long block complete") == true)
        #expect(document.string?.contains("Last complete tail") == true)
        #expect((try Data(contentsOf: url)).count < 1_000_000)
        var bluePixels = 0
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            let thumbnail = page.thumbnail(of: NSSize(width: 160, height: 200), for: .mediaBox)
            let bitmap = try #require(thumbnail.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.blueComponent > 0.8, color.redComponent < 0.2, color.greenComponent < 0.2 { bluePixels += 1 }
            } }
        }
        #expect(bluePixels > 20, "the portable image is drawn in the PDF")
    }

    @Test func limitsRejectWithoutCreatingOrReplacingADestination() async throws {
        let renderer = PrintDocumentRenderer()
        defer { renderer.close() }
        try await renderer.load(html())
        let folder = try TemporaryFolder()
        let absent = folder.url.appending(path: "absent.pdf")
        await #expect(throws: (any Error).self) { try await renderer.exportPDF(to: absent, limits: .init(pages: 1)) }
        #expect(!FileManager.default.fileExists(atPath: absent.path))
        let existing = folder.url.appending(path: "existing.pdf")
        let original = Data("Existing content".utf8)
        try original.write(to: existing)
        await #expect(throws: (any Error).self) { try await renderer.exportPDF(to: existing, limits: .init(bytes: 512)) }
        #expect(try Data(contentsOf: existing) == original)
    }
}
