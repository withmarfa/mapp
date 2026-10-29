import Foundation
import Testing

@testable import MAPP

struct TextZoomTests {
    @Test func biggerAndSmallerMoveOneStep() {
        #expect(TextZoom.note.size(after: .bigger, from: 13) == 14)
        #expect(TextZoom.note.size(after: .smaller, from: 13) == 12)
        #expect(TextZoom.interface.size(after: .bigger, from: 14) == 15)
        #expect(TextZoom.interface.size(after: .smaller, from: 16) == 15)
    }

    @Test func theEndsOfTheRangeChangeNothing() {
        #expect(TextZoom.note.size(after: .bigger, from: 24) == nil)
        #expect(TextZoom.note.size(after: .smaller, from: 11) == nil)
        #expect(TextZoom.interface.size(after: .bigger, from: 24) == nil)
        #expect(TextZoom.interface.size(after: .smaller, from: 11) == nil)
    }

    @Test func aSizeBetweenStepsMovesToTheNearestStepAsked() {
        #expect(TextZoom.note.size(after: .bigger, from: 15) == 16)
        #expect(TextZoom.note.size(after: .smaller, from: 15) == 14)
        #expect(TextZoom.note.size(after: .bigger, from: 400) == nil)
        #expect(TextZoom.note.size(after: .smaller, from: -3) == nil)
    }

    @Test func actualSizeReturnsToTheDefault() {
        #expect(TextZoom.note.size(after: .actual, from: 20) == 13)
        #expect(TextZoom.interface.size(after: .actual, from: 11) == 13)
        #expect(TextZoom.note.size(after: .actual, from: 13) == nil)
    }

    @Test func thePageHasItsOwnSettingAndEverythingElseTheInterfaces() {
        #expect(TextZoom.acting(pageFocused: true).key == PageKey.textSize)
        #expect(TextZoom.acting(pageFocused: false).key == InterfaceKey.textSize)
    }

    @Test func applyWritesOnlyTheSettingItActsOn() throws {
        let suite = "TextZoomTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        TextZoom.note.apply(.bigger, in: defaults)
        #expect(defaults.integer(forKey: PageKey.textSize) == 14)
        #expect(defaults.object(forKey: InterfaceKey.textSize) == nil)
        defaults.set(24, forKey: InterfaceKey.textSize)
        TextZoom.interface.apply(.bigger, in: defaults)
        #expect(defaults.integer(forKey: InterfaceKey.textSize) == 24)
        TextZoom.interface.apply(.actual, in: defaults)
        #expect(defaults.integer(forKey: InterfaceKey.textSize) == 13)
    }
}
