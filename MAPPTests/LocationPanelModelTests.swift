import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// What the Location panel holds and writes. The map itself is not drawn here: the panel's state, and what it asks the
/// library to write, are.
@MainActor struct LocationPanelModelTests {
    private let library = FakeItemLibrary()
    private let undo = UndoManager()

    private static func number(_ text: String) -> PropertyValue { .number(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!) }

    private static func point(_ latitude: Double, _ longitude: Double) -> LocationPoint { LocationPoint(latitude: latitude, longitude: longitude)! }

    init() {
        library.catalogue = LookFixture.catalogue()
        undo.groupsByEvent = false
    }

    @discardableResult
    private func add(
        _ type: String, _ values: [String: PropertyValue] = [:], name: String = "Brat", readOnly: Bool = false,
        content: Item.Content = .markdown
    ) -> Item {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var item = Item(
            id: .mint(), type: TypeID(type), title: name, name: name, titleRule: .property("title"),
            properties: values.map { Property(key: $0, value: $1) }, content: content, version: ItemVersion(1), created: date, modified: date)
        item.readOnly = readOnly
        library.items.append(item)
        return item
    }

    private func panel(for item: Item) throws -> LocationPanelModel {
        let spec = try #require(ItemLocation.of(library.catalogue.itemTypes[item.type]))
        return LocationPanelModel(spec: spec, item: item.id, library: library, undoManager: undo)
    }

    private func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    private let london: [String: PropertyValue] = ["latitude": LocationPanelModelTests.number("51.5246"), "longitude": LocationPanelModelTests.number("-0.0788")]

    // MARK: Placing

    @Test func placingThePinWritesBothNumbersInOneEdit() throws {
        let event = add("core.event")
        let model = try panel(for: event)
        #expect(model.point == nil && !model.hasLocation)
        step { model.place(Self.point(51.5246, -0.0788)) }
        #expect(library.propertiesSet.count == 1)
        #expect(library.propertiesSet[0].changes == ["latitude": Self.number("51.5246"), "longitude": Self.number("-0.0788")])
        #expect(model.point == LocationPoint(latitude: 51.5246, longitude: -0.0788))
        #expect(model.hasLocation)
    }

    @Test func aTypedNameGoesInTheSameEditAsThePoint() throws {
        let event = add("core.event")
        let model = try panel(for: event)
        model.name = "Brat, Redchurch Street"
        step { model.place(Self.point(51.5246, -0.0788)) }
        #expect(library.propertiesSet.count == 1)
        #expect(library.propertiesSet[0].changes["place"] == .some(.string("Brat, Redchurch Street")))
        #expect(model.name == "Brat, Redchurch Street")
    }

    @Test func movingThePinWritesOnlyWhatMoved() throws {
        let event = add("core.event", london)
        let model = try panel(for: event)
        step { model.place(Self.point(51.5246, -0.0789)) }
        #expect(library.propertiesSet[0].changes.keys.sorted() == ["longitude"])
        step { model.place(Self.point(51.5246, -0.0789)) }
        #expect(library.propertiesSet.count == 1)
    }

    @Test func oneStepUndoesAPlacementAndRedoesIt() throws {
        let event = add("core.event")
        let model = try panel(for: event)
        step { model.place(Self.point(51.5246, -0.0788)) }
        #expect(undo.undoActionName == "Edit Location")
        undo.undo()
        #expect(model.point == nil)
        #expect(library.item(event.id)?.value(of: "latitude") == nil)
        undo.redo()
        #expect(model.point == LocationPoint(latitude: 51.5246, longitude: -0.0788))
    }

    // MARK: Clearing

    @Test func clearingRemovesBothNumbersInOneStepAndKeepsTheName() throws {
        var values = london
        values["place"] = .string("Brat")
        let event = add("core.event", values)
        let model = try panel(for: event)
        #expect(model.hasLocation)
        step { model.clear() }
        #expect(library.propertiesSet.count == 1)
        #expect(library.propertiesSet[0].changes.keys.sorted() == ["latitude", "longitude"])
        #expect(model.point == nil && !model.hasLocation)
        #expect(library.item(event.id)?.value(of: "place") == .string("Brat"))
        undo.undo()
        #expect(model.point == LocationPoint(latitude: 51.5246, longitude: -0.0788))
        undo.redo()
        #expect(model.point == nil)
    }

    @Test func clearingWhereThereIsNothingWritesNothing() throws {
        let model = try panel(for: add("core.event"))
        step { model.clear() }
        #expect(library.propertiesSet.isEmpty)
    }

    // MARK: Names

    @Test func aNameTypedAloneIsWrittenOnCommitAndAnUnchangedOneIsNot() throws {
        let event = add("core.event", ["place": .string("Old")])
        let model = try panel(for: event)
        model.name = "New"
        model.commitName()
        #expect(library.propertiesSet.map(\.changes) == [["place": .string("New")]])
        model.name = "New"
        model.commitName()
        #expect(library.propertiesSet.count == 1)
    }

    @Test func aNameChangedUnderTheTextWaitsForThePersonToChoose() throws {
        let event = add("core.event", ["place": .string("Old")])
        let model = try panel(for: event)
        model.name = "Mine"
        _ = library.setItemProperties(event.id, changes: ["place": .string("Theirs")], actionName: "Other", undoManager: nil)
        model.commitName()
        #expect(model.hasNameConflict && model.notice != nil)
        #expect(library.item(event.id)?.value(of: "place") == .string("Theirs"))
        model.keepName()
        #expect(library.item(event.id)?.value(of: "place") == .string("Mine"))
        #expect(!model.hasNameConflict)
    }

    @Test func aPlaceAndAnImageHaveNoNameToType() throws {
        #expect(try !panel(for: add("core.entity.place", london)).hasNameField)
        #expect(try !panel(for: add("core.file.image", london, content: .file(.png, byteCount: 3))).hasNameField)
        #expect(try panel(for: add("core.event")).hasNameField)
    }

    // MARK: Cannot edit

    @Test func aReadOnlyItemShowsItsPointAndWritesNothing() throws {
        let event = add("core.event", london, readOnly: true)
        let model = try panel(for: event)
        #expect(!model.canEdit)
        #expect(model.point == LocationPoint(latitude: 51.5246, longitude: -0.0788))
        step { model.place(Self.point(1, 1)) }
        step { model.clear() }
        #expect(library.propertiesSet.isEmpty)
        #expect(model.point == LocationPoint(latitude: 51.5246, longitude: -0.0788))
    }

    @Test func anImageWithCoordinatesShowsAMapAndNoNameField() throws {
        let image = add("core.file.image", london, content: .file(.png, byteCount: 3))
        let model = try panel(for: image)
        #expect(model.point != nil)
        #expect(!model.canEdit && !model.hasNameField)
        step { model.place(Self.point(1, 1)) }
        #expect(library.propertiesSet.isEmpty)
    }

    @Test func aRefusedWriteIsToldAndLeavesThePointAlone() throws {
        let event = add("core.event", london)
        let model = try panel(for: event)
        library.acceptsProperties = false
        step { model.place(Self.point(1, 1)) }
        #expect(model.notice != nil)
        #expect(model.point == LocationPoint(latitude: 51.5246, longitude: -0.0788))
    }

    // MARK: What cannot be drawn

    @Test func aPairOffTheEarthIsNotDrawnAndThePanelSaysSo() throws {
        let event = add("core.event", ["latitude": Self.number("95"), "longitude": Self.number("10")])
        let model = try panel(for: event)
        #expect(model.point == nil)
        #expect(model.problem != nil)
        #expect(model.hasLocation)
        // The numbers can still be cleared, and the pin placed anew.
        step { model.clear() }
        #expect(!model.hasLocation)
    }

    @Test func oneNumberAloneIsNotDrawnAndThePanelSaysSo() throws {
        let model = try panel(for: add("core.event", ["longitude": Self.number("10")]))
        #expect(model.point == nil && model.problem != nil && model.hasLocation)
    }

    // MARK: Where the map opens

    @Test func withNoPointTheMapOpensOnTheWorld() throws {
        let model = try panel(for: add("core.event"))
        #expect(model.startFrame == .world)
    }

    @Test func withNoPointTheMapOpensRoundTheOtherPlacesTheLibraryHolds() throws {
        add("core.entity.place", london, name: "Elsewhere")
        let model = try panel(for: add("core.event", name: "Dinner"))
        let frame = model.startFrame
        #expect(frame != .world)
        #expect(abs(frame.latitude - 51.5246) < 0.001)
    }

    @Test func withAPointTheMapOpensOnIt() throws {
        let model = try panel(for: add("core.event", london))
        #expect(model.startFrame == .around(Self.point(51.5246, -0.0788)))
    }

    // MARK: Search

    @Test func choosingAResultOnlyMovesTheMap() throws {
        let event = add("core.event")
        let model = try panel(for: event)
        let found = LocationSearchResult(
            title: "Somewhere", subtitle: "A street", point: Self.point(40.7, -74))
        let frame = model.choose(found)
        #expect(frame.latitude == 40.7 && frame.longitude == -74)
        #expect(library.propertiesSet.isEmpty)
        #expect(model.point == nil)
        #expect(model.name.isEmpty)
    }

    // MARK: The panel

    @Test func theLocationPanelOpensOnAnItemItCannotEditOnlyWhereThereIsAPointToShow() throws {
        let empty = add("core.event", readOnly: true)
        let placed = add("core.event", london, readOnly: true)
        let spec = try #require(ItemLocation.of(library.catalogue.itemTypes[empty.type]))
        let closed = ValueEditModel(ValueEditRequest(kind: .location(spec), library: library, item: empty.id, undoManager: undo))
        let shown = ValueEditModel(ValueEditRequest(kind: .location(spec), library: library, item: placed.id, undoManager: undo))
        #expect(!closed.isEditable)
        #expect(shown.isEditable)
        #expect(shown.location != nil)
        #expect(!ValueEditKind.location(spec).closesOnChoice)
        #expect(ValueEditKind.location(spec).rowID == ItemLocation.rowID)
    }
}
