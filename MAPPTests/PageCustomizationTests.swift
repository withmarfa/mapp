import Foundation
import UniformTypeIdentifiers
import Marfa
import Testing
@testable import MAPP

/// What the Customize Page sheet and the inspector's Show on Page offer, which is only what the page can change.
struct PageCustomizationTests {
    private static func field(_ name: String) -> TypeField {
        TypeField(name: name, type: "string", declaredBy: "x")
    }

    private static let catalogue = Catalogue(itemTypes: [
        MarfaMapping.itemType(ItemType(
            id: "core.event", label: "Event", fields: ["title", "starts_at", "location", "status"].map { field($0) }, titleField: "title")),
        MarfaMapping.itemType(ItemType(
            id: "core.entity.person", label: "Person", fields: ["title", "job_title", "email"].map { field($0) }, titleField: "title")),
        MarfaMapping.itemType(ItemType(id: "aic.note", label: "Note", fields: ["title", "topic"].map { field($0) }, titleField: "title")),
    ])

    private static func item(_ type: String, _ properties: [String: PropertyValue] = [:], content: MAPP.Item.Content = .markdown) -> MAPP.Item {
        MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID(type), title: "Title", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, content: content, version: ItemVersion(1), created: .distantPast,
            modified: .distantPast)
    }

    @Test func anEventsPageDrawsItsOwnTimeAndStatus() {
        let event = Self.item("core.event", ["starts_at": .string("2026-10-30T10:00:00Z")])
        let type = Self.catalogue.itemTypes[event.type]
        #expect(PageCustomization.fields(of: event, type: type, hidden: ["title"], catalogue: Self.catalogue).map(\.key) == ["location"])
    }

    @Test func anEventThePageCannotPlaceKeepsItsFieldsToChoose() {
        let event = Self.item("core.event")
        let type = Self.catalogue.itemTypes[event.type]
        #expect(PageCustomization.fields(of: event, type: type, hidden: ["title"], catalogue: Self.catalogue).map(\.key) == ["starts_at", "location", "status"])
    }

    @Test func aPersonsPageDrawsTheJobTitle() {
        let person = Self.item("core.entity.person")
        let type = Self.catalogue.itemTypes[person.type]
        #expect(PageCustomization.fields(of: person, type: type, hidden: ["title"], catalogue: Self.catalogue).map(\.key) == ["email"])
    }

    @Test func anOrdinaryItemOffersEveryFieldTheLibraryDoesNotKeep() {
        let note = Self.item("aic.note")
        let type = Self.catalogue.itemTypes[note.type]
        #expect(PageCustomization.fields(of: note, type: type, hidden: ["title"], catalogue: Self.catalogue).map(\.key) == ["topic"])
    }

    @Test func aFileHasNoPageToCustomize() {
        #expect(PageCustomization.isAvailable(for: Self.item("aic.note")))
        #expect(!PageCustomization.isAvailable(for: Self.item("aic.note", content: .file(.png, byteCount: 10))))
        #expect(!PageCustomization.isAvailable(for: nil))
    }
}
