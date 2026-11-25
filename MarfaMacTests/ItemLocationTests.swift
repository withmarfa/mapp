import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

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

    @Test func aTypeWithOneOfTheTwoNumbersHasNoLocationAndTheOneStaysANumber() {
        #expect(ItemLocation.of(Self.typeInfo("core.file.video")) == nil)
        #expect(ItemLocation.of(Self.typeInfo("core.note")) == nil)
        #expect(ItemLocation.of(nil) == nil)
    }

    // MARK: Names

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

    @Test func aFilesLocationIsAFieldAPersonMayChange() throws {
        let spec = try Self.spec("core.file.image")
        let image = Self.item("core.file.image", Self.london, content: .file(.png, byteCount: 4))
        #expect(image.allows(.fields))
        #expect(spec.row(of: image).editable == true)
        #expect(spec.row(of: Self.item("core.file.image", content: .file(.png, byteCount: 4))).editable == true)
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
}
