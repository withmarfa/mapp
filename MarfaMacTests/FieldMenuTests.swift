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

private func menu(
    _ row: String, of type: TypeID = entry, editsValue: Bool = false, reachesServer: Bool = true,
    layout: PageLayout? = nil
) -> FieldMenu {
    let catalogue = catalogue()
    return FieldMenu(
        row: row, type: catalogue.itemTypes[type], layout: layout ?? defaultLayout(of: type), catalogue: catalogue, editsValue: editsValue,
        reachesServer: reachesServer)
}

private func commands(_ menu: FieldMenu) -> [[FieldMenu.Command]] { menu.sections.map { $0.map(\.command) } }

private func enabled(_ command: FieldMenu.Command, in menu: FieldMenu) -> Bool? {
    menu.sections.joined().first { $0.command == command }?.isEnabled
}

@Suite struct FieldMenuTests {
    @Test func aFieldOfTheOwnersTypeOffersEveryChange() {
        let menu = menu("shelf")
        #expect(commands(menu) == [[.rename], [.pin, .moveUp, .moveDown, .hide], [.remove]])
        #expect(menu.lockText == nil)
        #expect(menu.sections.joined().allSatisfy { $0.command == .moveUp ? !$0.isEnabled : $0.isEnabled })
    }

    @Test func aChoiceFieldAlsoOffersItsChoices() {
        #expect(commands(menu("genre")) == [[.rename, .editChoices], [.pin, .moveUp, .moveDown, .hide], [.remove]])
    }

    @Test func anInheritedFieldShowsWhereItComesFromAndOffersNoChange() {
        let menu = menu("rating")
        #expect(menu.lockText?.contains("Media") == true)
        #expect(commands(menu) == [[.pin, .moveUp, .moveDown, .hide]], "placement is the Mac's own, so a lock does not stop it")
    }

    @Test func everyFieldOfAShippedTypeIsLocked() {
        let menu = menu("rating", of: media)
        #expect(menu.lockText != nil)
        #expect(menu.sections.joined().allSatisfy { ![.rename, .editChoices, .remove].contains($0.command) })
    }

    @Test func withNoServerTheChangesToTheTypeAreDimmedAndPlacementIsNot() {
        let menu = menu("genre", reachesServer: false)
        #expect(enabled(.rename, in: menu) == false)
        #expect(enabled(.editChoices, in: menu) == false)
        #expect(enabled(.remove, in: menu) == false)
        #expect(enabled(.hide, in: menu) == true)
    }

    @Test func theFieldsThePageUsesAsTitleTextOrSourceLinkCannotBeRemoved() {
        #expect(enabled(.remove, in: menu("isbn")) == false)
        #expect(enabled(.remove, in: menu("notes")) == false)
        #expect(enabled(.rename, in: menu("isbn")) == true, "a name can still change")
    }

    @Test func aRowThatIsNoFieldOffersPlacementOnly() {
        let menu = menu("#tags")
        #expect(menu.lockText == nil)
        #expect(commands(menu) == [[.pin, .moveUp, .moveDown, .hide]])
    }

    @Test func theLastRowOfThePageCannotMoveDownAndTheFirstCannotMoveUp() {
        #expect(enabled(.moveDown, in: menu("#tags")) == false)
        #expect(enabled(.moveUp, in: menu("#tags")) == true)
        #expect(enabled(.moveUp, in: menu("shelf")) == false)
        #expect(enabled(.moveDown, in: menu("shelf")) == true)
    }

    @Test func aPinnedRowOffersUnpinAndAFifthPinIsDimmed() {
        let pinned = menu("#type")
        #expect(commands(pinned).first?.contains(.unpin) == true)
        #expect(commands(pinned).first?.contains(.pin) == false)
        var placements = PagePlacements()
        placements.setPins(["#type", "#updated", "shelf", "genre"], of: entry)
        let full = defaultLayout(placements)
        #expect(!full.canPin)
        #expect(enabled(.pin, in: menu("notes", layout: full)) == false)
        #expect(enabled(.unpin, in: menu("shelf", layout: full)) == true)
    }

    @Test func theValueEditorIsOfferedFirstWhereOnlyTheMenuReachesIt() {
        #expect(commands(menu("shelf", editsValue: true)).first == [.editValue])
        #expect(commands(menu("shelf")).first != [.editValue])
    }

    @Test func aFieldTheTypeLacksOffersNoChange() {
        let menu = menu("vanished")
        #expect(menu.lockText == nil)
        #expect(!menu.sections.joined().contains { [.rename, .editChoices, .remove].contains($0.command) })
    }

    @Test func renameIsOfferedWhereTwoFieldsShareALabelSoTheClashCanBeFixed() {
        var twin = catalogue()
        let before = twin.itemTypes[entry]!
        twin.itemTypes[entry] = ItemTypeInfo(
            id: entry, label: before.label,
            fields: before.fields.map { $0.key == "shelf" ? ItemTypeInfo.Field(key: "shelf", label: "Genre", kind: .text, declaredBy: entry) : $0 },
            titleField: before.titleField, bodyField: before.bodyField, parent: media, linkField: before.linkField)
        let both = ["shelf", "genre"].map {
            FieldMenu(
                row: $0, type: twin.itemTypes[entry], layout: defaultLayout(), catalogue: twin, editsValue: false, reachesServer: true)
        }
        #expect(both.allSatisfy { enabled(.rename, in: $0) == true })
        #expect(throws: FieldEditRefusal.labelInUse("Genre")) {
            try twin.itemTypes[entry]!.plan(.rename(key: "genre", label: "Genre"), in: twin).edit
        }
    }

    @Test func aFieldAChildRedeclaresIsLockedInTheMenuToo() {
        var redeclared = catalogue()
        let before = redeclared.itemTypes[entry]!
        redeclared.itemTypes[entry] = ItemTypeInfo(
            id: entry, label: before.label,
            fields: before.fields.map {
                $0.key == "rating" ? ItemTypeInfo.Field(key: "rating", label: "Rating", kind: .choice(["good"]), declaredBy: entry) : $0
            },
            titleField: before.titleField, bodyField: before.bodyField, parent: media, linkField: before.linkField)
        let menu = FieldMenu(
            row: "rating", type: redeclared.itemTypes[entry], layout: defaultLayout(), catalogue: redeclared, editsValue: false,
            reachesServer: true)
        #expect(menu.lockText?.contains("Media") == true)
        #expect(commands(menu) == [[.pin, .moveUp, .moveDown, .hide]])
    }
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

    @Test func aMoveAtTheEndChangesNothing() throws {
        let placements = try stored {
            carryOut(.moveUp, on: "shelf", in: $0)
            carryOut(.moveDown, on: "#tags", in: $0)
        }
        #expect(placements == PagePlacements())
    }

    @Test func aCommandThatIsNotPlacementChangesNothing() {
        let layout = defaultLayout()
        #expect(layout.after(.rename, row: "shelf") == nil)
        #expect(layout.after(.remove, row: "shelf") == nil)
        #expect(layout.after(.editChoices, row: "genre") == nil)
    }
}
