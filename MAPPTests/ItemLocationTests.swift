import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// An item's Location: which types have one, what the two numbers say, what its row reads and what an edit writes.
struct ItemLocationTests {
    private static let catalogue = LookFixture.catalogue()

    private static func typeInfo(_ id: String) -> ItemTypeInfo? { catalogue.itemTypes[TypeID(id)] }

    private static func item(
        _ type: String, _ values: [String: PropertyValue] = [:], name: String? = "Brat", content: Item.Content = .markdown
    ) -> Item {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID(type), title: name ?? "", name: name, titleRule: .property("title"),
            properties: values.map { Property(key: $0, value: $1) }, content: content, version: ItemVersion(1), created: date, modified: date)
    }

    private static func number(_ text: String) -> PropertyValue { .number(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!) }

    private static func spec(_ type: String) throws -> ItemLocation { try #require(ItemLocation.of(typeInfo(type))) }

    private static let london: [String: PropertyValue] = ["latitude": number("51.5246"), "longitude": number("-0.0788")]

    // MARK: Which types have one

    @Test func aTypeWithBothNumbersHasALocationAndNameItsOwnWay() throws {
        #expect(try Self.spec("core.event").name == .typed(#require(Self.typeInfo("core.event")?.fields.first { $0.key == "place" })))
        #expect(try Self.spec("core.entity.place").name == .itemName)
        #expect(try Self.spec("core.file.image").name == .none)
    }

    @Test func aTypeWithOneOfTheTwoNumbersHasNoLocationAndTheOneStaysANumber() {
        #expect(ItemLocation.of(Self.typeInfo("core.file.video")) == nil)
        #expect(ItemLocation.of(Self.typeInfo("core.note")) == nil)
        #expect(ItemLocation.of(nil) == nil)
    }

    @Test func aNumberFieldIsNeededNotJustTheName() {
        let specs = LookFixture.specs.map { spec in
            var copy = spec
            if spec.id == "core.event" { copy.fields = spec.fields.map { $0.key == "latitude" ? LookFixture.field("latitude") : $0 } }
            return copy
        }
        #expect(ItemLocation.of(LookFixture.catalogue(specs).itemTypes[TypeID("core.event")]) == nil)
    }

    // MARK: Reading

    @Test func neitherNumberIsNoLocation() throws {
        let spec = try Self.spec("core.event")
        #expect(spec.reading(of: Self.item("core.event")) == .none)
        #expect(spec.summary(of: Self.item("core.event")) == nil)
    }

    @Test func oneNumberAloneIsNoPointAndIsShownAsStored() throws {
        let spec = try Self.spec("core.event")
        let item = Self.item("core.event", ["latitude": Self.number("51.5")])
        #expect(spec.reading(of: item) == .partial("51.5, –"))
        #expect(spec.summary(of: item) == "51.5, –")
        #expect(spec.problem(of: item) != nil)
        #expect(!spec.hasPoint(item))
    }

    @Test func aPairOffTheEarthIsShownAsStoredAndNotDrawn() throws {
        let spec = try Self.spec("core.event")
        for pair in [("91", "10"), ("-90.5", "10"), ("10", "181"), ("10", "-180.1")] {
            let item = Self.item("core.event", ["latitude": Self.number(pair.0), "longitude": Self.number(pair.1)])
            #expect(spec.reading(of: item) == .unplaceable("\(pair.0), \(pair.1)"), "\(pair)")
            #expect(spec.summary(of: item) == "\(pair.0), \(pair.1)")
            #expect(spec.problem(of: item) != nil)
            #expect(!spec.hasPoint(item))
        }
    }

    @Test func theEdgesOfTheEarthAreAPoint() throws {
        let spec = try Self.spec("core.event")
        for pair in [("90", "180"), ("-90", "-180"), ("0", "0")] {
            let item = Self.item("core.event", ["latitude": Self.number(pair.0), "longitude": Self.number(pair.1)])
            #expect(spec.hasPoint(item), "\(pair)")
        }
    }

    @Test func aNumberThatIsNotANumberIsShownAsStoredAndNotDrawn() throws {
        let spec = try Self.spec("core.event")
        let item = Self.item("core.event", ["latitude": .string("north"), "longitude": Self.number("1")])
        #expect(spec.reading(of: item) == .unplaceable("north, 1"))
    }

    // MARK: Names

    @Test func anEventShowsItsPlaceAndAnImageShowsMapOnly() throws {
        var values = Self.london
        values["place"] = .string("Brat\nsecond line")
        #expect(try Self.spec("core.event").summary(of: Self.item("core.event", values)) == "Brat")
        #expect(try Self.spec("core.event").summary(of: Self.item("core.event", Self.london)) == String(localized: "Map"))
        let image = Self.item("core.file.image", Self.london, content: .file(.png, byteCount: 4))
        #expect(try Self.spec("core.file.image").summary(of: image) == String(localized: "Map"))
        #expect(try !Self.spec("core.file.image").hasNameField)
    }

    @Test func aPlaceShowsItsOwnNameOnceItHasAPoint() throws {
        let spec = try Self.spec("core.entity.place")
        #expect(spec.summary(of: Self.item("core.entity.place", Self.london)) == "Brat")
        // A name with nowhere to point is the page's title, not a place.
        #expect(spec.summary(of: Self.item("core.entity.place")) == nil)
        #expect(spec.naming("Other", in: Self.item("core.entity.place", Self.london)) == nil)
        #expect(!spec.hasNameField)
    }

    // MARK: Writing

    @Test func placingWritesBothNumbersToSixPlacesAndTheNameTypedInOneEdit() throws {
        let spec = try Self.spec("core.event")
        let point = try #require(LocationPoint(latitude: 51.52461234567, longitude: -0.07881234567))
        let changes = spec.placing(point, name: " Brat ", in: Self.item("core.event"))
        #expect(changes == ["latitude": Self.number("51.524612"), "longitude": Self.number("-0.078812"), "place": .string("Brat")])
    }

    @Test func placingWhereTheItemAlreadyIsWritesNothing() throws {
        let spec = try Self.spec("core.event")
        let point = try #require(LocationPoint(latitude: 51.5246, longitude: -0.0788))
        #expect(spec.placing(point, in: Self.item("core.event", Self.london)).isEmpty)
        let moved = try #require(LocationPoint(latitude: 51.5246, longitude: -0.0789))
        #expect(spec.placing(moved, in: Self.item("core.event", Self.london)).keys.sorted() == ["longitude"])
    }

    @Test func aPlaceIsNeverRenamedByPlacing() throws {
        let spec = try Self.spec("core.entity.place")
        let point = try #require(LocationPoint(latitude: 1, longitude: 2))
        let changes = spec.placing(point, name: "Renamed", in: Self.item("core.entity.place"))
        #expect(changes.keys.sorted() == ["latitude", "longitude"])
    }

    @Test func anEmptyNameTakesThePlaceAwayAndAnUnchangedOneWritesNothing() throws {
        let spec = try Self.spec("core.event")
        let named = Self.item("core.event", ["place": .string("Brat")])
        #expect(spec.naming("  ", in: named) == ["place": nil])
        #expect(spec.naming("Brat", in: named) == nil)
        #expect(spec.naming("", in: Self.item("core.event")) == nil)
    }

    @Test func clearingTakesBothNumbersAwayAndLeavesTheName() throws {
        let spec = try Self.spec("core.event")
        var values = Self.london
        values["place"] = .string("Brat")
        let changes = spec.clearing(Self.item("core.event", values))
        #expect(changes.count == 2)
        #expect(changes.keys.sorted() == ["latitude", "longitude"])
        #expect(changes.values.allSatisfy { $0 == nil })
        #expect(spec.clearing(Self.item("core.event")).isEmpty)
        let partial = spec.clearing(Self.item("core.event", ["latitude": Self.number("1")]))
        #expect(partial.keys.sorted() == ["latitude"])
    }

    // MARK: Rows and listing

    @Test func theRowOpensWhereThereIsAPointEvenOnAnItemThatCannotBeEdited() throws {
        let spec = try Self.spec("core.event")
        var item = Self.item("core.event", Self.london)
        item.readOnly = true
        let row = try #require(spec.row(of: item, offersEmpty: false))
        #expect(row.id == "#location")
        #expect(row.editable)
        #expect(spec.row(of: Self.item("core.event"), offersEmpty: false) == nil)
        #expect(spec.row(of: Self.item("core.event"), offersEmpty: true)?.editable == true)
        var empty = Self.item("core.event")
        empty.readOnly = true
        #expect(spec.row(of: empty, offersEmpty: true) == nil)
    }

    @Test func aFileHasAMapToLookAtAndNothingToEdit() throws {
        let spec = try Self.spec("core.file.image")
        let image = Self.item("core.file.image", Self.london, content: .file(.png, byteCount: 4))
        #expect(!image.isEditable)
        #expect(spec.hasPoint(image))
        #expect(spec.row(of: image, offersEmpty: true)?.editable == true)
        #expect(spec.row(of: Self.item("core.file.image", content: .file(.png, byteCount: 4)), offersEmpty: true) == nil)
    }

    @Test func locationStandsInForTheFieldsItOwnsWhereTheFirstOfThemWas() throws {
        let spec = try Self.spec("core.event")
        let fields = try #require(Self.typeInfo("core.event")).fields
        let hidden = spec.folding(fields, showingCoordinates: false, listsLocation: true)
        let keys = hidden.map(\.id)
        #expect(!keys.contains("latitude") && !keys.contains("longitude") && !keys.contains("place"))
        #expect(keys.filter { $0 == "#location" }.count == 1)
        let shown = spec.folding(fields, showingCoordinates: true, listsLocation: true).map(\.id)
        #expect(shown.contains("latitude") && shown.contains("longitude") && !shown.contains("place"))
        let unlisted = spec.folding(fields, showingCoordinates: false, listsLocation: false).map(\.id)
        #expect(!unlisted.contains("#location"))
    }

    // MARK: Points and frames

    @Test func aClickBeyondTheDateLineIsBroughtBack() {
        #expect(LocationPoint(clicked: 10, longitude: 190)?.longitude == -170)
        #expect(LocationPoint(clicked: 10, longitude: -190)?.longitude == 170)
        #expect(LocationPoint(clicked: 10, longitude: 540)?.longitude == 180 || LocationPoint(clicked: 10, longitude: 540)?.longitude == -180)
        #expect(LocationPoint(clicked: 91, longitude: 0) == nil)
        #expect(LocationPoint(clicked: 0, longitude: .nan) == nil)
        #expect(LocationPoint(latitude: .infinity, longitude: 0) == nil)
    }

    @Test func aMapOpensOnTheItemsPointElseItsOwnersPlacesElseTheWorld() throws {
        let point = try #require(LocationPoint(latitude: 51.5, longitude: -0.1))
        #expect(LocationFrame.start(point: point, others: []) == .around(point))
        let near = try #require(LocationPoint(latitude: 51.6, longitude: -0.2))
        let frame = LocationFrame.start(point: nil, others: [point, near])
        #expect(abs(frame.latitude - 51.55) < 0.001)
        #expect(frame.latitudeSpan > 0.05 && frame.latitudeSpan < 1)
        #expect(LocationFrame.start(point: nil, others: []) == .world)
        let far = try #require(LocationPoint(latitude: -40, longitude: 170))
        #expect(LocationFrame.start(point: nil, others: [point, far]) == .world)
        #expect(LocationFrame.covering([point])?.latitudeSpan == 0.05)
    }
}
