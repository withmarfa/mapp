import Foundation
import Testing
@testable import MarfaMac

/// The chip looks have two owners, `ChipLooks` for the app and the CSS variables of the item page's header; nothing
/// else compares them.
struct ChipLooksTests {
    private static func stylesheet() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "editor/src/style.css"), encoding: .utf8)
    }

    private static func matches(_ pattern: String, in text: String) throws -> [[String]] {
        try text.matches(of: Regex(pattern)).map { match in
            (0..<match.output.count).map { index in
                (match.output[index].substring ?? "").description
            }
        }
    }

    @Test func theHeaderReadsOnlyWhatTheAppSends() throws {
        let sent = ChipLooks.cssVariables(dark: false, looks: .defaults)
        let read = try Self.matches(#"var\((--chip-[a-z-]+)"#, in: Self.stylesheet()).map { $0[1] }
        #expect(!read.isEmpty)
        for name in Set(read) where name != "--chip-scale" {
            #expect(sent[name] != nil, "\(name) is read by editor/src/style.css and never sent")
        }
    }

    @Test func theHeadersFallbacksAreTheAppsMeasures() throws {
        let sent = ChipLooks.cssVariables(dark: false, looks: .defaults)
        let fallbacks = try Self.matches(#"var\((--chip-[a-z-]+), ([0-9.]+px)\)"#, in: Self.stylesheet())
        #expect(!fallbacks.isEmpty)
        for fallback in fallbacks {
            #expect(sent[fallback[1]] == fallback[2], "\(fallback[1]) falls back to \(fallback[2]), the app sends \(sent[fallback[1]] ?? "nothing")")
        }
    }

    @Test func aPersonsCircleHasADarkValueOfItsOwn() {
        let light = ChipLooks.cssVariables(dark: false, looks: .defaults)
        let dark = ChipLooks.cssVariables(dark: true, looks: .defaults)
        for name in ["--chip-wash", "--chip-person-fill", "--chip-person-ink"] {
            #expect(light[name] != nil && dark[name] != nil && light[name] != dark[name], "\(name) is the same in light and dark")
        }
    }

    @Test func aPriorityTakesItsToneFromItsRank() {
        #expect((0..<4).map { OptionTone.priority(rank: $0, of: 4) } == [.purple, .yellow, .orange, .red])
    }
}
