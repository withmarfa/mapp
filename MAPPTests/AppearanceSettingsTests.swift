import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MAPP

/// What Settings > Appearance keeps on this Mac.
@MainActor
struct AppearanceSettingsTests {
    private func defaults() throws -> (UserDefaults, () -> Void) {
        let suite = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    // MARK: Accent

    @Test func theInstalledFontsAreNotAskedForWhereNoFontIsChosen() {
        var asked = false
        #expect(FontChoice.resolved("", among: { asked = true; return ["Helvetica"] }()) == nil)
        #expect(!asked)
        #expect(FontChoice.resolved("Helvetica", among: { asked = true; return ["Helvetica"] }()) == "Helvetica")
        #expect(asked)
    }

    @Test func aMissingChoiceIsNamedOneWayWhateverItIs() {
        #expect(MissingChoice.label("Comic Sans") == "Comic Sans (Missing)")
        #expect(MissingChoice.typeName("core.task") == "Task")
        #expect(MissingChoice.typeName("app.thing.reading_list") == "Reading List")
        #expect(MissingChoice.placeName(.itemType("core.event")) == "Event")
        #expect(MissingChoice.label(MissingChoice.placeName(.itemType("core.event"))) == "Event (Missing)")
    }

    @Test func everyAccentIsReadBackAndAnythingElseIsTheSystems() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        #expect(AccentChoice.stored(in: defaults) == .system)
        let choices: [AccentChoice] = [.system] + AccentChoice.Offered.allCases.map { .offered($0) } + [.custom("#FF8800")]
        for choice in choices {
            defaults.set(choice.rawValue, forKey: AppearanceKey.accent)
            #expect(AccentChoice.stored(in: defaults) == choice)
        }
        for unreadable in ["", "teal", "#12", "#GGGGGG", "FF8800"] {
            defaults.set(unreadable, forKey: AppearanceKey.accent)
            #expect(AccentChoice.stored(in: defaults) == .system, "\(unreadable) is not an accent")
        }
    }

    @Test func theOfferedAccentsAreSystemSettingsOwnInItsOrderAndEachIsDistinct() {
        #expect(AccentChoice.Offered.allCases.map(\.rawValue) == ["blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"])
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let colors = AccentChoice.Offered.allCases.compactMap { $0.nsColor.rgb(in: appearance) }
            #expect(colors.count == 8)
            for (index, first) in colors.enumerated() {
                for second in colors[(index + 1)...] {
                    let distance = abs(first.0 - second.0) + abs(first.1 - second.1) + abs(first.2 - second.2)
                    #expect(distance > 0.3, "two accents read alike in \(appearance)")
                }
            }
        }
    }

    @Test func aCustomAccentIsStoredAsItsHexAndReadBackAsTheSameColor() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        let chosen = Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 1)
        let accent = AccentChoice.custom(chosen)
        #expect(accent == .custom("#FF8000"))
        defaults.set(accent.rawValue, forKey: AppearanceKey.accent)
        let read = try #require(AccentChoice.stored(in: defaults).nsColor?.usingColorSpace(.sRGB))
        #expect(abs(read.redComponent - 1) < 0.005 && abs(read.greenComponent - 0.5) < 0.005 && read.blueComponent < 0.005)
    }

    @Test func theSystemAccentLeavesTheTintToTheSystem() {
        #expect(AccentChoice.system.nsColor == nil && AccentChoice.system.color == nil)
        #expect(AccentChoice.Offered.green.nsColor.hexValue(in: .aqua) == "#62BA46")
    }

    // MARK: Theme and highlights

    @Test func aThemeIsReadBackAndAnUnknownOneFollowsTheSystem() throws {
        let (defaults, done) = try defaults()
        defer { done() }
        #expect(AppTheme.stored(in: defaults) == .system)
        for theme in AppTheme.allCases {
            defaults.set(theme.rawValue, forKey: AppearanceKey.theme)
            #expect(AppTheme.stored(in: defaults) == theme)
        }
        defaults.set("sepia", forKey: AppearanceKey.theme)
        #expect(AppTheme.stored(in: defaults) == .system)
        #expect(AppTheme.system.appearance == nil)
        #expect(AppTheme.dark.appearance?.name == .darkAqua)
    }

    @Test func yellowIsThePagesOwnAndEveryOtherHighlightIsASoftColor() {
        #expect(HighlightChoice.yellow.css(accent: .systemBlue) == nil)
        for choice in HighlightChoice.allCases where choice != .yellow {
            #expect(choice.css(accent: .systemBlue)?.hasPrefix("rgba(") == true)
        }
        #expect(HighlightChoice.accent.css(accent: .systemRed) != HighlightChoice.accent.css(accent: .systemGreen))
    }

    // MARK: Fonts

    @Test func aFontThatIsNoLongerInstalledFallsBackToTheDefault() {
        let installed = ["Helvetica", "Menlo"]
        #expect(FontChoice.resolved("", among: installed) == nil)
        #expect(FontChoice.resolved("Helvetica", among: installed) == "Helvetica")
        #expect(FontChoice.resolved("Uninstalled Sans", among: installed) == nil)
    }

    @Test func theInstalledFamiliesAreListedAndTheMonospacedOnesAreASubset() {
        let all = FontChoice.installedFamilies()
        let monospaced = FontChoice.installedMonospacedFamilies()
        #expect(all.contains("Helvetica"))
        #expect(monospaced.contains("Menlo"))
        #expect(!monospaced.contains("Helvetica"))
        #expect(Set(monospaced).isSubset(of: Set(all)))
    }

    @Test func aFamilyNameCannotBreakOutOfTheFontList() {
        #expect(FontChoice.css(family: "Odd\" ; color: red", generic: "serif") == "\"Odd ; color: red\", serif")
    }
}

private extension NSColor {
    func rgb(in name: NSAppearance.Name) -> (Double, Double, Double)? {
        var result: (Double, Double, Double)?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            if let color = usingColorSpace(.sRGB) { result = (color.redComponent, color.greenComponent, color.blueComponent) }
        }
        return result
    }

    func hexValue(in name: NSAppearance.Name) -> String? {
        rgb(in: name).map { String(format: "#%02X%02X%02X", Int(($0.0 * 255).rounded()), Int(($0.1 * 255).rounded()), Int(($0.2 * 255).rounded())) }
    }
}
