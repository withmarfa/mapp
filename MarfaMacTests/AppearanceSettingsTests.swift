import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

/// What Settings > Appearance keeps on this Mac.
@MainActor
struct AppearanceSettingsTests {
    private func defaults() throws -> (UserDefaults, () -> Void) {
        let suite = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    // MARK: Accent

    @Test func theSwatchesAfterTheMacsAccentLeaveOutBlueButAStoredBlueStillReads() throws {
        #expect(AccentChoice.Offered.swatched.map(\.rawValue) == ["purple", "pink", "red", "orange", "yellow", "green", "graphite"])
        let (defaults, done) = try defaults()
        defer { done() }
        defaults.set("blue", forKey: AppearanceKey.accent)
        #expect(AccentChoice.stored(in: defaults) == .offered(.blue))
        #expect(AccentChoice.stored(in: defaults).nsColor != nil)
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

    // MARK: Fonts

    @Test func aFamilyNameCannotBreakOutOfTheFontList() {
        #expect(FontChoice.css(family: "Odd\" ; color: red", generic: "serif") == "\"Odd ; color: red\", serif")
    }
}
