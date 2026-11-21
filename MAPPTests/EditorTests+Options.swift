import Foundation
import Testing
import WebKit
@testable import MAPP

/// Settings > Editor's options, which reach a page that is already open as one set.
extension EditorTests {
    @Test func editorOptionsReachAPageThatIsAlreadyOpen() async throws {
        let item = FakeItemLibrary.note("Plan", modified: .now)
        let library = FakeItemLibrary(items: [item])
        library.bodies[item.id] = "# Plan\n\n```swift\nlet a = 1\nlet b = 2\n```\n"
        let editor = try await attachingEditor(library)
        let numbered = "document.querySelector('pre[data-inkkit-line-numbers]') !== null"
        #expect(try await editor.webView.evaluateJavaScript(numbered) as? Bool == false)

        var style = PageStyle()
        style.showsCodeLineNumbers = true
        style.lineSpacing = .relaxed
        style.paragraphSpacing = .tight
        editor.setStyle(style)
        #expect(try await eventuallyAsking { try await editor.webView.evaluateJavaScript(numbered) as? Bool == true })
        let body = "getComputedStyle(document.body)"
        #expect(try await editor.webView.evaluateJavaScript("\(body).getPropertyValue('--inkkit-line-height')") as? String == "1.8")

        // The next set replaces the whole of the last, so a field left at its default is back at it.
        editor.setStyle(PageStyle())
        #expect(try await eventuallyAsking { try await editor.webView.evaluateJavaScript(numbered) as? Bool == false })
        #expect(try await editor.webView.evaluateJavaScript("\(body).getPropertyValue('--inkkit-line-height')") as? String == "1.55")
    }

    @Test func anItemOpenedNewlyTakesTheEditingModeInSettings() async throws {
        let first = FakeItemLibrary.note("Plan", modified: .now)
        let second = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [first, second])
        let editor = try await attachingEditor(library)
        var style = PageStyle()
        style.editingMode = .source
        editor.setStyle(style)
        editor.load(second)
        #expect(await eventually { editor.caret.sourceMode })

        style.editingMode = .formatted
        editor.setStyle(style)
        #expect(editor.caret.sourceMode, "the page on show keeps the mode it is in")
        editor.load(first)
        #expect(await eventually { !editor.caret.sourceMode })
    }
}
