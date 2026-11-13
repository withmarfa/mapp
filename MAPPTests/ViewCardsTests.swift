import Foundation
import Testing
@testable import MAPP

/// What a gallery's card settings hold and how they read back. What a card says is its type's look.
@MainActor
struct ViewCardsTests {
    // MARK: The settings

    @Test func theDefaultsAreTheCardAsItHasAlwaysBeen() {
        let cards = ViewCards()
        #expect(cards.preview == .pictureOrText)
        #expect(!cards.fitsPicture)
        #expect(cards.size == .medium)
        #expect(ViewMacSettings().cards == cards)
    }

    @Test func aSizeSetsHowWideACardIs() {
        let widths = ViewCards.Size.allCases.map(\.columnWidth)
        #expect(widths == widths.sorted())
        #expect(Set(widths).count == widths.count)
    }

    @Test func settingsRoundTripThroughTheStoredText() throws {
        let cards = ViewCards(preview: .text, fitsPicture: true, size: .large)
        let settings = ViewMacSettings(cards: cards)
        let layouts = ViewLayouts(["view": settings])
        let read = try #require(ViewLayouts(rawValue: layouts.rawValue))
        #expect(read.views["view"]?.cards == cards)
    }

    @Test func aChoiceThisVersionDoesNotKnowNeverVoidsTheRest() throws {
        let text = #"{"preview":"hologram","size":"large","fitsPicture":"yes","properties":["tags"]}"#
        let cards = try JSONDecoder().decode(ViewCards.self, from: Data(text.utf8))
        #expect(cards.preview == .pictureOrText)
        #expect(cards.size == .large)
        #expect(!cards.fitsPicture)
    }

    @Test func theSubtextAndPropertiesAnEarlierVersionKeptAreLeftUnread() throws {
        let text = #"{"preview":"text","subtext":"date","properties":["tags","field.status"],"size":"small"}"#
        let cards = try JSONDecoder().decode(ViewCards.self, from: Data(text.utf8))
        #expect(cards == ViewCards(preview: .text, size: .small))
        let written = String(decoding: try JSONEncoder().encode(cards), as: UTF8.self)
        #expect(!written.contains("subtext") && !written.contains("properties"))
    }

    @Test func settingsStoredBeforeCardsExistOpenWithTheDefaults() throws {
        let settings = try JSONDecoder().decode(ViewMacSettings.self, from: Data(#"{"layout":"gallery"}"#.utf8))
        #expect(settings.cards == ViewCards())
    }

    @Test func choicesThatDifferInCardsAreDifferentChoices() {
        var other = ViewMacSettings()
        other.cards.size = .small
        #expect(!ViewMacSettings().sameChoices(as: other))
        var taken = ViewMacSettings(widths: Data([1]))
        taken.take(choicesOf: other)
        #expect(taken.cards.size == .small)
        #expect(taken.widths == Data([1]))
    }
}
