import AppKit
import Testing
import WebKit
@testable import MAPP

/// The sidebar's Outline moves the page to a heading by its place in Inkkit's list.
extension EditorTests {
    @Test func revealingAHeadingScrollsToItEvenTheFirstTimeAfterALoad() async throws {
        let page = try await Page()
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        let paragraphs = (1...40).map { "Paragraph \($0) of the section." }.joined(separator: "\n\n")
        try await page.load("# One\n\n\(paragraphs)\n\n## Two\n\n\(paragraphs)\n\n## Three\n\n\(paragraphs)\n")
        let web = page.editor.webView

        func top(of ordinal: Int) async throws -> Double {
            let script = "document.querySelectorAll('.ProseMirror h1, .ProseMirror h2')[\(ordinal)].getBoundingClientRect().top"
            return try #require(try await web.evaluateJavaScript(script) as? Double)
        }
        func reveal(_ ordinal: Int) async throws {
            let revealed = try await web.evaluateJavaScript("window.editor.revealHeadingAt(\(ordinal))") as? Bool
            #expect(revealed == true)
            // Scrolling may finish a frame later.
            _ = try await eventuallyAsking {
                let top = try await top(of: ordinal)
                let height = try #require(try await web.evaluateJavaScript("window.innerHeight") as? Double)
                return top >= 0 && top < height
            }
            let height = try #require(try await web.evaluateJavaScript("window.innerHeight") as? Double)
            let place = try await top(of: ordinal)
            #expect(place >= 0 && place < height, "heading \(ordinal) is at \(place) in a window \(height) high")
        }

        try #require(try await web.evaluateJavaScript("window.scrollY") as? Double == 0)
        try await reveal(2)
        try await page.run("window.scrollTo(0, 1200)")
        try await reveal(0)
        try await reveal(1)
    }
}
