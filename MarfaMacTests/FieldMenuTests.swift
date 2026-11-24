@testable import MarfaMac
import Foundation
import Testing

private let media = TypeID("core.media")
private let entry = TypeID("app.books.entry")

private func catalogue() -> Catalogue {
    let rating = ItemTypeInfo.Field(key: "rating", label: "Rating", kind: .choice(["good", "bad"]), declaredBy: media)
    let genre = ItemTypeInfo.Field(key: "genre", label: "Genre", kind: .choice(["fiction", "history"]), declaredBy: entry)
    let shelf = ItemTypeInfo.Field(key: "shelf", label: "Shelf", kind: .text, declaredBy: entry)
    let notes = ItemTypeInfo.Field(key: "notes", label: "Notes", kind: .text, declaredBy: entry)
    let isbn = ItemTypeInfo.Field(key: "isbn", label: "ISBN", kind: .text, declaredBy: entry)
    return Catalogue(itemTypes: [
        ItemTypeInfo(id: media, label: "Media", fields: [rating], titleField: "title", bodyField: nil, parent: nil),
        ItemTypeInfo(
            id: entry, label: "Entry", fields: [rating, genre, shelf, notes, isbn], titleField: "title", bodyField: "notes",
            parent: media, linkField: "isbn"),
    ])
}

private nonisolated func row(_ id: String) -> PageLayout.Row { PageLayout.Row(id: id, label: id, symbol: "text.alignleft") }

private let pageRows = ["#type", "#updated", "shelf", "genre", "notes", "isbn", "rating", "#tags", "#linked"].map(row)

private func defaultLayout(of type: TypeID = entry, _ placements: PagePlacements = PagePlacements()) -> PageLayout {
    PageLayout(rows: pageRows, placement: placements.placement(of: type, in: catalogue()))
}

@Suite struct FieldPlacementTests {
    private func stored(_ run: (UserDefaults) -> Void) throws -> PagePlacements {
        let suite = "FieldPlacement-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        run(defaults)
        return PagePlacements.stored(in: defaults)
    }

    private func carryOut(_ command: FieldMenu.Command, on row: String, in defaults: UserDefaults) {
        PagePlacements.update(in: defaults) { placements in
            let layout = defaultLayout(placements)
            if let moved = layout.after(command, row: row) { placements.apply(moved, of: entry, in: catalogue()) }
        }
    }

    @Test func hidingTakesTheRowOffThePageForTheType() throws {
        let placements = try stored { carryOut(.hide, on: "genre", in: $0) }
        let placement = placements.placement(of: entry, in: catalogue())
        #expect(!placement.showsOnPage("genre"))
        #expect(placement.showsOnPage("shelf"))
    }

    @Test func pinningAndUnpinningKeepTheOrderOfTheOthers() throws {
        let pinned = try stored { carryOut(.pin, on: "genre", in: $0) }
        // The type's default pin for the parent has no row on this item, so it is kept behind the pins shown.
        #expect(pinned.pins(of: entry, in: catalogue()) == ["#type", "#updated", "genre", "child-of"])
        let unpinned = try stored {
            carryOut(.pin, on: "genre", in: $0)
            carryOut(.unpin, on: "genre", in: $0)
        }
        #expect(unpinned.pins(of: entry, in: catalogue()) == ["#type", "#updated", "child-of"])
    }

    @Test func movingDownThenUpReturnsToTheDefaultOrder() throws {
        let moved = try stored { carryOut(.moveDown, on: "shelf", in: $0) }
        #expect(moved.choices[entry.rawValue]?.rowOrder?.prefix(2) == ["genre", "shelf"])
        let back = try stored {
            carryOut(.moveDown, on: "shelf", in: $0)
            carryOut(.moveUp, on: "shelf", in: $0)
        }
        #expect(back.choices[entry.rawValue]?.rowOrder == nil, "an order equal to the default is not kept")
    }
}
