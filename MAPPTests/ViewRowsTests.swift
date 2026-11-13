import Foundation
import Testing
@testable import MAPP

/// What a list's rows take from a view's own choice and what from Settings.
@MainActor
struct ViewRowsTests {
    @Test func aViewWithNoChoiceFollowsSettingsInEverything() {
        let rows = ViewRows()
        #expect(rows.style == nil)
        #expect(rows.previewLines(settings: 2) == 2)
        #expect(rows.previewLines(settings: 0) == 0)
        #expect(rows.showsPictures(settings: true))
        #expect(!rows.showsPictures(settings: false))
        #expect(ViewMacSettings().rows == rows)
    }

    @Test func aSwitchStoresAValueOnlyWhenItDiffersFromSettings() {
        var rows = ViewRows()
        rows.setShowsPreview(true, settings: 2)
        rows.setShowsPictures(true, settings: true)
        #expect(rows == ViewRows())
        rows.setShowsPreview(false, settings: 2)
        rows.setShowsPictures(false, settings: true)
        #expect(rows.previewLines(settings: 2) == 0)
        #expect(!rows.showsPictures(settings: true))
        // Putting a switch back to what Settings holds makes it follow Settings again.
        rows.setShowsPreview(true, settings: 1)
        rows.setShowsPictures(true, settings: true)
        #expect(rows == ViewRows())
    }

    @Test func aPreviewTheViewTurnsOnWhereSettingsHoldNoneShowsTheStandardLines() {
        var rows = ViewRows()
        rows.setShowsPreview(true, settings: 0)
        #expect(rows.previewLines(settings: 0) == ListKey.defaultPreviewLines)
        #expect(rows.previewLines(settings: 1) == 1)
    }

    @Test func aStyleOfTheViewIsTheFirstThatResolves() {
        var rows = ViewRows()
        rows.style = .compact
        #expect(ListRowStyle.resolve(view: rows.style, fields: .person, rowStyle: .withPictures) == .compact)
        rows.style = nil
        #expect(ListRowStyle.resolve(view: rows.style, rowStyle: .withPictures) == .withPictures)
    }

    @Test func rowsRoundTripThroughTheStoredTextAndDefaultsStoreNothingNew() throws {
        var rows = ViewRows(style: .highlight)
        rows.setShowsPreview(false, settings: 2)
        let layouts = ViewLayouts(["view": ViewMacSettings(rows: rows)])
        let read = try #require(ViewLayouts(rawValue: layouts.rawValue))
        #expect(read.views["view"]?.rows == rows)
        let before = try JSONDecoder().decode(ViewMacSettings.self, from: Data(#"{"layout":"list"}"#.utf8))
        #expect(before.rows == ViewRows())
    }

    @Test func aChoiceThisVersionDoesNotKnowNeverVoidsTheRest() throws {
        let rows = try JSONDecoder().decode(ViewRows.self, from: Data(#"{"style":"hologram","showsPreview":false,"showsPictures":"yes"}"#.utf8))
        #expect(rows.style == nil)
        #expect(rows.showsPreview == false)
        #expect(rows.showsPictures == nil)
    }

    @Test func choicesThatDifferInRowsAreDifferentChoices() {
        var other = ViewMacSettings()
        other.rows.style = .compact
        #expect(!ViewMacSettings().sameChoices(as: other))
        var taken = ViewMacSettings(widths: Data([1]))
        taken.take(choicesOf: other)
        #expect(taken.rows.style == .compact)
        #expect(taken.widths == Data([1]))
    }
}
