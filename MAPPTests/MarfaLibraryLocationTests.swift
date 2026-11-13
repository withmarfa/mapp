import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// A Location written through the library: both numbers and the name in one queued edit, one undo step, and a refusal
/// told rather than half done.
@MainActor
@Suite(.hangLimit) struct MarfaLibraryLocationTests {
    private static let event = TypeID("core.event")
    private static let id = ItemID("ev1")
    private static let imageID = ItemID("im1")

    private static func field(_ key: String, _ kind: ItemTypeInfo.Field.Kind) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(key: key, label: key, kind: kind, declaredBy: event)
    }

    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(
            id: event, label: "Event", fields: [
                field("title", .text), field("body", .text), field("place", .text), field("latitude", .number), field("longitude", .number),
            ], titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: MarfaMapping.fileType, label: "File", fields: [], titleField: nil, bodyField: nil, parent: nil),
    ])

    private static func number(_ text: String) -> PropertyValue { .number(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!) }

    private static func loaded(readOnly: Bool = false) async throws -> (MarfaLibrary, FakeItemSource) {
        let date = Date(timeIntervalSince1970: 1_000_000)
        var item = Item(
            id: id, type: event, title: "Dinner", name: "Dinner", titleRule: .property("title"), version: ItemVersion(1), created: date,
            modified: date)
        item.readOnly = readOnly
        let image = Item(
            id: imageID, type: MarfaMapping.fileType, title: "Photo", name: "Photo", titleRule: .firstLine, content: .file(.png, byteCount: 0),
            version: ItemVersion(1), created: date, modified: date)
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: [item, image], catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private let both: [String: PropertyValue?] = ["latitude": number("51.5246"), "longitude": number("-0.0788")]
    private func number(_ text: String) -> PropertyValue { Self.number(text) }

    @Test func bothNumbersAndTheNameGoInOneQueuedEdit() async throws {
        let (library, source) = try await Self.loaded()
        var changes = both
        changes["place"] = .string("Brat")
        #expect(library.setItemProperties(Self.id, changes: changes, actionName: "Edit Location", undoManager: nil))
        #expect(source.writes == [.editProperties(Self.id, changes, base: ItemVersion(1), undoing: nil)])
    }

    @Test func oneUndoStepTakesBackBothNumbersAndRedoPutsThemBack() async throws {
        let (library, source) = try await Self.loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(library.setItemProperties(Self.id, changes: both, actionName: "Edit Location", undoManager: undo))
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Edit Location")
        undo.undo()
        #expect(source.writes.last == .editProperties(Self.id, ["latitude": nil, "longitude": nil], base: ItemVersion(1), undoing: nil))
        #expect(!undo.canUndo)
        undo.redo()
        #expect(source.writes.last == .editProperties(Self.id, both, base: ItemVersion(1), undoing: nil))
        #expect(undo.canUndo)
    }

    @Test func clearingIsOneEditThatRemovesBothKeys() async throws {
        let (library, source) = try await Self.loaded()
        #expect(library.setItemProperties(Self.id, changes: both, actionName: "Edit Location", undoManager: nil))
        var held = try #require(library.item(Self.id))
        held.properties = [Property(key: "latitude", value: number("51.5246")), Property(key: "longitude", value: number("-0.0788"))]
        source.send(.upserted([held]))
        #expect(await eventually { library.item(Self.id)?.value(of: "latitude") != nil })
        source.clearWrites()
        #expect(library.setItemProperties(Self.id, changes: ["latitude": nil, "longitude": nil], actionName: "Edit Location", undoManager: nil))
        #expect(source.writes.count == 1)
    }

    @Test func aValueThatIsNotANumberIsRefusedAndNothingIsWritten() async throws {
        let (library, source) = try await Self.loaded()
        #expect(!library.setItemProperties(Self.id, changes: ["latitude": .string("north"), "longitude": number("1")], actionName: "x", undoManager: nil))
        #expect(source.writes.isEmpty)
    }

    @Test func aKeyTheTypeLacksOrTheBodyIsRefusedAsAWhole() async throws {
        let (library, source) = try await Self.loaded()
        #expect(!library.setItemProperties(Self.id, changes: ["latitude": number("1"), "nope": .string("x")], actionName: "x", undoManager: nil))
        #expect(!library.setItemProperties(Self.id, changes: ["latitude": number("1"), "body": .string("x")], actionName: "x", undoManager: nil))
        #expect(source.writes.isEmpty)
    }

    @Test func aFileAndAReadOnlyItemTakeNoChange() async throws {
        let (library, source) = try await Self.loaded()
        #expect(!library.setItemProperties(Self.imageID, changes: both, actionName: "x", undoManager: nil))
        let (guarded, guardedSource) = try await Self.loaded(readOnly: true)
        #expect(!guarded.setItemProperties(Self.id, changes: both, actionName: "x", undoManager: nil))
        #expect(source.writes.isEmpty && guardedSource.writes.isEmpty)
    }

    @Test func aChangeThatChangesNothingWritesNothing() async throws {
        let (library, source) = try await Self.loaded()
        #expect(library.setItemProperties(Self.id, changes: [:], actionName: "x", undoManager: nil))
        #expect(library.setItemProperties(Self.id, changes: ["place": nil], actionName: "x", undoManager: nil))
        #expect(source.writes.isEmpty)
    }
}
