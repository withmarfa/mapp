@testable import MarfaMac
import Foundation
import Testing

private let media = TypeID("core.media")
private let entry = TypeID("app.books.entry")

private func catalogue() -> Catalogue {
    let rating = ItemTypeInfo.Field(key: "rating", label: "Rating", kind: .choice(["good", "bad"]), declaredBy: media)
    let genre = ItemTypeInfo.Field(key: "genre", label: "Genre", kind: .choice(["fiction", "history"]), declaredBy: entry)
    let shelf = ItemTypeInfo.Field(key: "shelf", label: "Shelf", kind: .text, declaredBy: entry)
    return Catalogue(itemTypes: [
        ItemTypeInfo(id: media, label: "Media", fields: [rating], titleField: "title", bodyField: nil, parent: nil),
        ItemTypeInfo(id: entry, label: "Entry", fields: [rating, genre, shelf], titleField: "title", bodyField: "notes", parent: media),
    ])
}

/// A row's menu: how the row shows, where it goes, then the field's own entries.
@Suite struct FieldMenuTests {
    private let placing = FieldMenu.Placing(shows: .whenSet, canMoveUp: false, canMoveDown: true)

    private func commands(_ menu: FieldMenu) -> [[FieldMenu.Command]] { menu.sections.map { $0.map(\.command) } }

    @Test func theMenuShowsHowTheRowShowsThenMovesThenTheFieldsOwnEntries() {
        let menu = FieldMenu(row: "genre", type: catalogue().itemTypes[entry], placing: placing, catalogue: catalogue(), editsValue: false, reachesServer: true)
        #expect(commands(menu) == [[.showWhenSet, .alwaysShow, .hide], [.moveUp, .moveDown], [.rename, .editChoices], [.remove]])
        #expect(menu.sections[0].map(\.isChecked) == [true, false, false])
        #expect(menu.sections[1].map(\.isEnabled) == [false, true], "the first row cannot go up")
    }

    @Test func pinningIsOfferedOnlyWhilePinnedPropertiesAreOn() {
        var on = placing
        on.isPinned = false
        on.canPin = false
        let menu = FieldMenu(row: "shelf", type: catalogue().itemTypes[entry], placing: on, catalogue: catalogue(), editsValue: false, reachesServer: true)
        #expect(menu.sections[0].map(\.command) == [.showWhenSet, .alwaysShow, .hide, .pin])
        #expect(menu.sections[0].last?.isEnabled == false, "a fifth pin is refused")
        let off = FieldMenu(row: "shelf", type: catalogue().itemTypes[entry], placing: placing, catalogue: catalogue(), editsValue: false, reachesServer: true)
        #expect(!off.sections.joined().contains { $0.command == .pin || $0.command == .unpin })
    }

    @Test func anInheritedFieldIsPlacedButNotChanged() {
        let menu = FieldMenu(row: "rating", type: catalogue().itemTypes[entry], placing: placing, catalogue: catalogue(), editsValue: true, reachesServer: true)
        #expect(menu.lockText != nil)
        #expect(commands(menu) == [[.showWhenSet, .alwaysShow, .hide], [.moveUp, .moveDown], [.editValue]])
    }

    @Test func aRowThatIsNoPersonsToPlaceHasNoPlacingEntries() {
        let menu = FieldMenu(row: PagePlacement.when, type: catalogue().itemTypes[entry], placing: nil, catalogue: catalogue(), editsValue: false, reachesServer: true)
        #expect(menu.sections.isEmpty)
    }

    @Test func movingARowStoresTheWholeOrderAndStopsAtEitherEnd() {
        var placements = PagePlacements()
        let moved = placements.move("shelf", by: -1, in: ["rating", "genre", "shelf"], of: entry)
        #expect(moved)
        #expect(placements.choices[entry.rawValue]?.rowOrder == ["rating", "shelf", "genre"])
        let first = placements.move("rating", by: -1, in: ["rating", "shelf", "genre"], of: entry)
        let unknown = placements.move("gone", by: 1, in: ["rating"], of: entry)
        #expect(!first && !unknown)
    }
}
