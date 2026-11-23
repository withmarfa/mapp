import AppKit
import Foundation
import Testing
import WebKit
@testable import MarfaMac

/// What the page does with the fonts, the accent and the highlight color Settings > Appearance chooses.
extension EditorTests {
    private func property(_ name: String, onBody: Bool, in page: Harness<FakeItemLibrary>) async throws -> String {
        let target = onBody ? "document.body" : "document.documentElement"
        return try await page.editor.webView.evaluateJavaScript("\(target).style.getPropertyValue('\(name)')") as? String ?? ""
    }

    @Test func theChosenFontsReachThePageAndAMissingOneLeavesItsOwn() async throws {
        let page = try await Harness(library: FakeItemLibrary())
        var style = PageStyle()
        style.textFont = "Helvetica"
        style.codeFont = "Menlo"
        page.editor.setStyle(style)
        var text = ""
        _ = try await eventuallyAsking {
            text = try await property("--inkkit-font-family", onBody: true, in: page)
            return !text.isEmpty
        }
        #expect(text.hasPrefix("\"Helvetica\""))
        #expect(try await property("--inkkit-monospace-font", onBody: true, in: page).hasPrefix("\"Menlo\""))

        style.textFont = "Uninstalled Family That Does Not Exist"
        style.codeFont = ""
        page.editor.setStyle(style)
        _ = try await eventuallyAsking { try await property("--inkkit-font-family", onBody: true, in: page).isEmpty }
        #expect(try await property("--inkkit-font-family", onBody: true, in: page).isEmpty)
        #expect(try await property("--inkkit-monospace-font", onBody: true, in: page).isEmpty)
    }

    @Test func aCustomAccentAndAHighlightColorReachThePageAndPaintAMark() async throws {
        let page = try await Harness(library: FakeItemLibrary())
        var style = PageStyle()
        style.accent = .custom("#FF8000")
        style.highlight = .green
        page.editor.setStyle(style)
        _ = try await eventuallyAsking { try await property("--item-highlight", onBody: false, in: page).hasPrefix("rgba(") }
        #expect(try await property("--inkkit-accent-color", onBody: false, in: page) == "#FF8000")
        let color = try await page.editor.webView.evaluateJavaScript("""
            (() => { const m = document.createElement('mark'); document.querySelector('.ProseMirror').appendChild(m);
              const c = getComputedStyle(m).backgroundColor; m.remove(); return c })()
            """) as? String
        let highlight = try await property("--item-highlight", onBody: false, in: page)
        #expect(color == highlight)
    }
}
