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

    @Test func theAppSendsOnlyWhatTheHeaderReads() throws {
        let css = try Self.stylesheet()
        for name in ChipLooks.cssVariables(dark: false, looks: .defaults).keys {
            #expect(css.contains("var(\(name)"), "\(name) is sent and editor/src/style.css never reads it")
        }
    }

    /// Sizes, paddings and weights each have two copies: `ChipLooks` for the app and the fallback written in the page's
    /// CSS. A number in a `var(--chip-*, fallback)` is the value the app sends.
    @Test func theHeadersFallbacksAreTheAppsMeasures() throws {
        let sent = ChipLooks.cssVariables(dark: false, looks: .defaults)
        let fallbacks = try Self.matches(#"var\((--chip-[a-z-]+), ([0-9.]+(?:px)?)\)"#, in: Self.stylesheet())
        #expect(fallbacks.count >= 14)
        for fallback in fallbacks {
            #expect(sent[fallback[1]] == fallback[2], "\(fallback[1]) falls back to \(fallback[2]), the app sends \(sent[fallback[1]] ?? "nothing")")
        }
        let weights = ["--chip-weight": "500", "--chip-fact-weight": "400", "--chip-person-initials-weight": "600"]
        for (name, weight) in weights {
            #expect(sent[name] == weight, "\(name) is \(sent[name] ?? "not sent"), the design says \(weight)")
            #expect(fallbacks.contains { $0[1] == name }, "editor/src/style.css has no fallback for \(name)")
        }
        #expect(sent["--chip-text-size"] == "12px" && sent["--chip-fact-size"] == "13px")
        #expect(ChipLooks.defaults.rowTextSize == 11.5 && ChipLooks.defaults.rowFactSize == 12 && ChipLooks.defaults.rowWeight == 400)
    }

    @Test func theFocusRingIsTheSamePercentageInTheAppAndOnThePage() throws {
        let percent = try Self.matches(#"--focus-ring: color-mix\(in srgb, var\(--label-primary\) ([0-9]+)%"#, in: Self.stylesheet())
        #expect(percent.first?[1] == String(Int((ChipLooks.defaults.focusRingOpacity * 100).rounded())))
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

    // MARK: Dark contrast

    private typealias RGB = (Double, Double, Double)

    private static func blend(_ top: RGB, _ opacity: Double, over bottom: RGB) -> RGB {
        (top.0 * opacity + bottom.0 * (1 - opacity), top.1 * opacity + bottom.1 * (1 - opacity), top.2 * opacity + bottom.2 * (1 - opacity))
    }

    private static func luminance(_ color: RGB) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.0) + 0.7152 * linear(color.1) + 0.0722 * linear(color.2)
    }

    private static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let (high, low) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (high + 0.05) / (low + 0.05)
    }

    /// What words sit on: white in light, and in dark the window and the lighter popover surface.
    private static let surfaces: [(dark: Bool, color: RGB)] = [
        (false, (1, 1, 1)),
        (true, (30.0 / 255, 30.0 / 255, 30.0 / 255)),
        (true, (44.0 / 255, 44.0 / 255, 46.0 / 255)),
    ]

    @Test func aPersonsLettersReadOnTheirCircleInLightAndDark() {
        let looks = ChipLooks.defaults
        for (dark, surface) in Self.surfaces {
            let fill = Self.blend(TypeTone.purple.components(dark: dark), looks.personFill(dark: dark), over: surface)
            let ratio = Self.contrast(looks.personInk(dark: dark), fill)
            #expect(ratio >= 4.5, "a person's letters are \(ratio) to 1 on their circle (dark: \(dark))")
        }
    }

    @Test func aTintedTypeChipsNameReadsOnItsFillForEveryTone() {
        let looks = ChipLooks.defaults
        for tone in TypeTone.allCases {
            for (dark, surface) in Self.surfaces {
                let opacity = dark ? looks.typeTintOpacityDark : looks.typeTintOpacity
                let fill = Self.blend(tone.components(dark: dark), opacity, over: surface)
                let ratio = Self.contrast(tone.nameInkComponents(looks, dark: dark), fill)
                #expect(ratio >= 4.5, "\(tone) name is \(ratio) to 1 on its chip (dark: \(dark))")
            }
        }
    }

    @Test func aChipsTextReadsOnItsWash() {
        let looks = ChipLooks.defaults
        for (dark, surface) in Self.surfaces {
            let ink: RGB = dark ? (1, 1, 1) : (0, 0, 0)
            let wash = Self.blend(ink, looks.chipWashOpacity, over: surface)
            let ratio = Self.contrast(Self.blend(ink, looks.chipTextOpacity, over: wash), wash)
            #expect(ratio >= 4.5, "a chip's text is \(ratio) to 1 on its wash (dark: \(dark))")
        }
    }
}
