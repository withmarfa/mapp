import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// The sample library's name and preview stand in for the core's, so a list row reads as text, never as Markdown.
@Suite struct SamplePreviewTests {
    private static func preview(_ body: String) -> String? {
        SampleLibrary.display(ItemDisplayInput(type: "core.note", properties: ["title": .string("T"), "body": .string(body)])).preview
    }

    @Test func aTableReadsAsItsCellsAndABulletAsItsText() {
        let body = "Three quotes in.\n\n| Supplier | Quote |\n| --- | ---: |\n| Harbour | £14,200 |\n\n## Next\n\n- [x] Measure\n- Ask **Oak** about *pricing*\n> A [link](https://example.test) and `code`"
        #expect(Self.preview(body) == "Three quotes in. Supplier Quote Harbour £14,200 Next Measure Ask Oak about pricing A link and code")
    }

    @Test func aBodyOfOnlyMarksHasNoPreviewAndAFenceKeepsItsLines() {
        #expect(Self.preview("---\n- \n> \n![](https://example.test/x.png)") == nil)
        #expect(Self.preview("```\n- kept\n```") == "- kept")
    }

    @Test func theNameOfAnItemWithNoTitleLosesItsHeadingMark() {
        let display = SampleLibrary.display(ItemDisplayInput(type: "core.note", properties: ["body": .string("## Garden *ideas*\n- Two beds")]))
        #expect(display.name == "Garden ideas")
        #expect(display.preview == "Two beds")
    }

    @Test func everySampleItemsPreviewHoldsNoMarkdownSource() {
        for item in SampleLibrary.items(now: .now, tasksAndEvents: true) {
            guard let preview = SampleLibrary.display(ItemDisplayInput(type: item.type, properties: item.properties)).preview else { continue }
            #expect(!preview.contains("|") && !preview.contains("- ") && !preview.contains("**"), "\(item.id): \(preview)")
        }
    }
}
