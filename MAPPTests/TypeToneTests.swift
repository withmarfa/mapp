import Testing

@testable import MAPP

struct TypeToneTests {
    /// The icons of Marfa's built-in catalogue.
    nonisolated private static let builtInIcons = [
        "audio-lines", "book-open", "bookmark", "calendar", "circle-play", "disc-3", "file", "file-image", "file-music",
        "file-video-camera", "film", "gamepad-2", "globe", "highlighter", "layers", "library-big", "map-pin",
        "message-square", "newspaper", "shapes", "square-check-big", "sticky-note", "tv", "user",
    ].map { "lucide:" + $0 }

    @Test func aKnownIconTakesItsTone() {
        #expect(TypeTone(icon: "lucide:calendar") == .red)
    }

    @Test func anUnknownIconTakesTheNeutralTone() {
        #expect(TypeTone(icon: "simple-icons:github") == .neutral)
        #expect(TypeTone(icon: "lucide:no-such-icon") == .neutral)
        #expect(TypeTone(icon: "") == .neutral)
    }

    @Test func noIconTakesTheNeutralTone() {
        #expect(TypeTone(icon: nil) == .neutral)
    }

    @MainActor @Test func anIconSitsDarkerThanItsTintInLightAndLighterInDark() {
        var looks = ChipLooks()
        looks.inkDepth = 0.22
        let light = TypeTone.cssColors(for: .blue, dark: false, looks: looks)
        let dark = TypeTone.cssColors(for: .blue, dark: true, looks: looks)
        #expect(light["--tone"] == "rgb(0, 122, 255)")
        #expect(light["--tone-ink"] == "rgb(0, 95, 199)")
        #expect(dark["--tone"] == "rgb(43, 149, 255)")
        #expect(dark["--tone-ink"] == "rgb(90, 172, 255)")
    }

    @Test(arguments: builtInIcons)
    func everyBuiltInIconHasAnEntry(icon: String) {
        #expect(TypeTone.table[icon] != nil)
    }
}
