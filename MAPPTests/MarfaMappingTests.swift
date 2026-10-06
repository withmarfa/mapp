import Foundation
import Marfa
import Testing
import UniformTypeIdentifiers
@testable import MAPP

struct MarfaMappingTests {
    private static func field(_ name: String, _ type: String = "string", by owner: String, definition: [String: JSONValue] = [:])
        -> TypeField
    {
        TypeField(name: name, type: type, declaredBy: owner, definition: definition)
    }

    private static let catalogue = MarfaMapping.catalogue(
        itemTypes: [
            ItemType(
                id: "core.task", label: "Task",
                fields: [
                    field("body", by: "core.task"),
                    field("due_at", "datetime", by: "core.task"),
                    field("status", "enum", by: "core.task", definition: ["enum_values": ["open", "done"]]),
                    field("title", by: "core.task")
                ],
                titleField: "title", bodyField: "body"),
            ItemType(
                id: "aic.ticket", label: "Ticket", parent: "core.task",
                fields: [
                    field("assignee", by: "aic.ticket"),
                    field("body", by: "core.task"),
                    field("title", by: "core.task")
                ],
                titleField: "title", bodyField: "body"),
            ItemType(id: "aic.project", label: "Project", titleField: "title", bodyField: "body"),
            ItemType(id: "core.entity", label: "Entity", fields: [field("name", by: "core.entity")], titleField: "name"),
            ItemType(id: "core.message", label: "Message", fields: [field("text", by: "core.message")], bodyField: "text"),
            ItemType(id: "core.file", label: "File", titleField: "title"),
            ItemType(id: "core.file.image", label: "Image", parent: "core.file", titleField: "title"),
            ItemType(id: "system.folder", label: "Folder")
        ],
        edgeTypes: [
            EdgeType(id: "parent-of", label: "Parent of", cardinality: "one-to-many", reverseName: "child-of", writtenAt: .target),
            EdgeType(id: "references", label: "References", cardinality: "many-to-many"),
            EdgeType(id: "supersedes", cardinality: "one-to-one"),
            EdgeType(id: "in-folder", cardinality: "many-to-many", targetTypeConstraints: ["system.folder"])
        ])

    private static func row(
        _ id: String, type: String = "aic.ticket", properties: [String: JSONValue] = ["title": "Title", "body": "Body"],
        state: Marfa.ItemState = .active, tier: Marfa.Tier? = .library, version: Int64 = 3, tags: [String] = []
    ) -> Marfa.Item {
        Marfa.Item(
            id: id, type: type, properties: properties, state: state, tier: tier, version: version, schemaVersion: 1,
            source: "test", sourceId: nil, occurredAt: "2026-10-06T00:52:22.021Z", createdAt: "2026-10-06T00:52:22.021Z",
            updatedAt: "2026-10-06T01:00:00Z", tags: tags)
    }

    private static func edge(_ id: String, _ type: String, from source: String, to target: String) -> Marfa.Edge {
        Marfa.Edge(
            id: id, sourceId: source, targetId: target, edgeType: type, properties: [:], version: 1,
            createdAt: "2026-10-06T00:00:00Z", updatedAt: "2026-10-06T00:00:00Z")
    }

    private static func item(_ row: Marfa.Item, edges: [Marfa.Edge] = [], held: Set<String> = []) -> MAPP.Item {
        MarfaMapping.item(row, edges: edges, catalogue: catalogue, isHeld: { held.contains($0) })
    }

    // MARK: Catalogue

    @Test func typesKeepTheirInheritedFieldsAndHints() throws {
        let ticket = try #require(Self.catalogue.itemTypes[TypeID("aic.ticket")])
        #expect(ticket.label == "Ticket")
        #expect(ticket.parent == TypeID("core.task"))
        #expect(ticket.titleField == "title" && ticket.bodyField == "body")
        #expect(ticket.fields.map(\.key) == ["assignee", "body", "title"])
        #expect(ticket.fields.map(\.declaredBy) == [TypeID("aic.ticket"), TypeID("core.task"), TypeID("core.task")])
        let task = try #require(Self.catalogue.itemTypes[TypeID("core.task")])
        #expect(task.fields.map(\.kind) == [.text, .date, .choice(["open", "done"]), .text])
        #expect(task.fields.map(\.label) == ["Body", "Due at", "Status", "Title"])
    }

    @Test func anEdgeIsHeldAsManyTimesAsTheOtherEndAllows() throws {
        let parent = try #require(Self.catalogue.edgeTypes["parent-of"])
        #expect(parent.reverseName == "child-of")
        #expect(parent.writtenAt == .target)
        #expect(parent.cardinality == .one)
        #expect(parent.sourceTypes.isEmpty && parent.targetTypes.isEmpty)
        #expect(Self.catalogue.edgeTypes["references"]?.cardinality == .many)
        #expect(Self.catalogue.edgeTypes["supersedes"]?.cardinality == .one)
        #expect(Self.catalogue.edgeTypes["in-folder"]?.targetTypes == [TypeID("system.folder")])
        #expect(Self.catalogue.edgeType(named: "child-of")?.isReverse == true)
    }

    @Test func typesCarryTheRestOfTheirDefinition() throws {
        let catalogue = MarfaMapping.catalogue(
            itemTypes: [
                ItemType(
                    id: "core.contact", label: "Contact", description: "A person.", version: 4,
                    fields: [TypeField(name: "name", type: "string", required: true, description: "Full name", declaredBy: "core.contact")],
                    roles: ["person"], compatibleWith: ["core.entity"])
            ],
            edgeTypes: [
                EdgeType(
                    id: "knows", label: "Knows", description: "Two people know each other.", cardinality: "one-to-many",
                    reverseName: "known-by", writtenAt: .target, cascadeOnDelete: "block",
                    properties: [TypeField(name: "since", type: "date", declaredBy: "knows")]),
                EdgeType(id: "owns", cardinality: "many-to-one", cascadeOnDelete: "cascade"),
                EdgeType(id: "next", cardinality: "one-to-one", cascadeOnDelete: "unknown")
            ])
        let contact = try #require(catalogue.itemTypes[TypeID("core.contact")])
        #expect(contact.description == "A person." && contact.version == 4)
        #expect(contact.roles == ["person"] && contact.compatibleWith == [TypeID("core.entity")])
        #expect(contact.fields.first?.required == true && contact.fields.first?.description == "Full name")
        let knows = try #require(catalogue.edgeTypes["knows"])
        #expect(knows.description == "Two people know each other.")
        // One source per target, many targets per source, written at the target: the target holds one.
        #expect(knows.cardinality == .one && knows.reverseCardinality == .many)
        #expect(knows.cascadeOnDelete == .block)
        #expect(knows.properties.map(\.key) == ["since"] && knows.properties.first?.kind == .date)
        let owns = try #require(catalogue.edgeTypes["owns"])
        #expect(owns.cardinality == .one && owns.reverseCardinality == .many && owns.cascadeOnDelete == .cascade)
        #expect(catalogue.edgeTypes["next"]?.cascadeOnDelete == .orphan)
    }

    @Test func theSliceNamesEveryNamespaceButTheServersOwn() {
        #expect(MarfaMapping.namespaces(of: Self.catalogue) == ["aic.*", "core.*"])
        #expect(MarfaMapping.namespaces(of: Catalogue()).isEmpty)
    }

    // MARK: Items

    @Test func titleAndBodyComeFromTheTypesFields() {
        let entity = Self.item(Self.row("e", type: "core.entity", properties: ["name": "Ada", "title": "Not this"]))
        #expect(entity.title == "Ada")
        #expect(entity.titleRule == .property("name"))
        let message = Self.item(Self.row("m", type: "core.message", properties: ["text": "First line\nSecond"]))
        #expect(message.title == "First line")
        #expect(message.titleRule == .firstLine)
        #expect(message.properties.isEmpty)
        #expect(MarfaMapping.body(of: Self.row("m", type: "core.message", properties: ["text": "Hi"]), catalogue: Self.catalogue) == "Hi")
        let folder = Self.item(Self.row("f", type: "system.folder", properties: ["title": "Notes"]))
        #expect(folder.title == "Notes")
        #expect(folder.titleRule == .property("title"))
    }

    @Test func propertiesFollowTheCatalogueThenTheRestByKeyLeavingOutTheBodyAndClearedValues() {
        let ticket = Self.item(Self.row("t", properties: [
            "zeta": "z", "title": "Fix it", "body": "Long text", "assignee": "agent", "alpha": 2, "gone": nil
        ]))
        #expect(ticket.properties.map(\.key) == ["assignee", "title", "alpha", "zeta"])
        #expect(ticket.value(of: "alpha") == .number(2))
        #expect(ticket.preview == "Long text")
    }

    @Test func theRowsStateTierTagsVersionAndDatesCarryOver() {
        let item = Self.item(Self.row("t", state: .trashed, tier: .feed, version: 7, tags: ["favorite", "work"]))
        #expect(item.id == ItemID("t"))
        #expect(item.type == TypeID("aic.ticket"))
        #expect(item.state == .trashed)
        #expect(item.tier == .feed)
        #expect(item.tags == ["favorite", "work"])
        #expect(item.isFavorite)
        #expect(item.version == ItemVersion(7))
        #expect(abs(item.created.timeIntervalSince1970 - 1_791_247_942.021) < 0.001)
        #expect(item.modified == Date(timeIntervalSince1970: 1_791_248_400))
        #expect(item.trashed == item.modified)
        #expect(item.container == nil)
        #expect(Self.item(Self.row("u", tier: nil)).tier == .library)
        #expect(Self.item(Self.row("r", state: .revoked)).state == .archived)
    }

    @Test func aFileItemIsReadAsItsKindOfFile() {
        let image = Self.item(Self.row("i", type: "core.file.image", properties: ["title": "Cat", "mime_type": "image/png"]))
        #expect(image.content == .file(.png, byteCount: 0))
        let unknown = Self.item(Self.row("f", type: "core.file", properties: ["title": "Blob"]))
        #expect(unknown.content == .file(.data, byteCount: 0))
        #expect(Self.item(Self.row("n")).content == .markdown)
    }

    @Test func aChildHoldsItsParentUnderTheReverseName() {
        let edges = [
            Self.edge("e1", "parent-of", from: "project", to: "ticket"),
            Self.edge("e2", "references", from: "ticket", to: "decision"),
            Self.edge("e3", "in-folder", from: "ticket", to: "folder"),
            Self.edge("e4", "supersedes", from: "decision", to: "ticket")
        ]
        let held: Set<String> = ["project", "ticket", "decision"]
        let ticket = Self.item(Self.row("ticket"), edges: edges, held: held)
        #expect(ticket.edgesOut == [
            MAPP.Edge(id: EdgeID("e1"), type: "child-of", source: ItemID("ticket"), target: .item(ItemID("project")),
                 origin: .property("child-of")),
            MAPP.Edge(id: EdgeID("e2"), type: "references", source: ItemID("ticket"), target: .item(ItemID("decision")),
                 origin: .body)
        ])
        let project = Self.item(Self.row("project", type: "aic.project"), edges: edges, held: held)
        #expect(project.edgesOut.isEmpty)
        let decision = Self.item(Self.row("decision"), edges: edges, held: held)
        #expect(decision.edgesOut.map(\.type) == ["supersedes"])
    }

    @Test func valuesSurviveTheTripThroughJSON() {
        #expect(MarfaMapping.value(0.1) == .number(Decimal(string: "0.1")!))
        #expect(MarfaMapping.json(.number(3)) == .integer(3))
        #expect(MarfaMapping.json(.number(Decimal(string: "2.5")!)) == .number(2.5))
        let nested: PropertyValue = .object(["list": .array([.string("a"), .bool(true), .null])])
        #expect(MarfaMapping.value(MarfaMapping.json(nested)) == nested)
    }

    // MARK: Verdicts and sync

    @Test func aRefusalIsReadIntoItsParts() {
        let refusal = Refusal(
            reason: "validation_error", code: "validation_error", message: "Bad status",
            fields: [FieldRefusal(field: "status", message: "not one of open, done")], trashed: true)
        #expect(MarfaMapping.outcome(.refused(refusal)) == .refused(SyncProblem(
            code: "validation_error", message: "Bad status", fields: ["status": "not one of open, done"],
            isTrashed: true)))
        let unsent = Refusal(reason: "the create_item it waits for was refused")
        #expect(MarfaMapping.outcome(.refused(unsent)) == .refused(SyncProblem(
            code: "the create_item it waits for was refused", message: nil)))
        #expect(MarfaMapping.outcome(.conflicted(siblingId: "s", fields: ["body"])) ==
            .conflicted(sibling: ItemID("s"), fields: ["body"]))
        #expect(MarfaMapping.outcome(.blocked(reason: .keySpent)) == .blocked(.keySpent, nil))
        #expect(MarfaMapping.outcome(.blocked(reason: .awaitingDependency)) == nil)
        #expect(MarfaMapping.outcome(.dead) == .dead)
    }

    private static func write(_ id: String, on item: String, _ verdict: Verdict? = nil) -> QueuedWrite {
        QueuedWrite(
            id: id, kind: .updateItem, itemId: item, idempotencyKey: id, verdict: verdict,
            queuedAt: "2026-10-06T00:00:00Z")
    }

    @Test func eachItemShowsWhatMostNeedsThePerson() {
        let refusal = Refusal(reason: "type_not_permitted", code: "type_not_permitted")
        let queue = [
            Self.write("1", on: "a"), Self.write("2", on: "a"),
            Self.write("3", on: "b"), Self.write("4", on: "b", .refused(refusal)),
            Self.write("5", on: "c", .accepted),
            Self.write("6", on: "d", .blocked(reason: .credentialRefused)), Self.write("7", on: "d", .refused(refusal)),
            Self.write("8", on: "e", .blocked(reason: .awaitingDependency))
        ]
        let conflict = SyncState.conflicted(sibling: ItemID("copy"), fields: ["body"])
        let states = MarfaMapping.syncStates(queue: queue, remembered: [ItemID("f"): conflict])
        #expect(states[ItemID("a")] == .waiting(writes: 2))
        #expect(states[ItemID("b")] == .refused(SyncProblem(code: "type_not_permitted")))
        #expect(states[ItemID("c")] == nil)
        #expect(states[ItemID("d")] == .blocked(SyncProblem(code: "credential_refused")))
        #expect(states[ItemID("e")] == .waiting(writes: 1))
        #expect(states[ItemID("f")] == conflict)
    }

    // MARK: Places

    @Test func placesFollowTheCatalogueAndTheItemsHeld() {
        let items = [
            Self.item(Self.row("p2", type: "aic.project", properties: ["title": "Beta"])),
            Self.item(Self.row("p1", type: "aic.project", properties: ["title": "Alpha"])),
            Self.item(Self.row("old", type: "aic.project", properties: ["title": "Gone"], state: .trashed)),
            Self.item(Self.row("t")),
            Self.item(Self.row("e", type: "core.entity", properties: ["name": "Ada"]))
        ]
        let places = MarfaMapping.places(items: items, catalogue: Self.catalogue)
        #expect(places.map(\.id) == [
            .inbox, .all, .favorites, .archive, .type(TypeID("aic.project")), .beneath(ItemID("p1")),
            .beneath(ItemID("p2")), .type(TypeID("core.entity")), .type(TypeID("aic.ticket")), .recentlyDeleted,
            .marfaTypes
        ])
        #expect(places.first { $0.id == .inbox }?.query == ItemQuery(tier: .feed))
        #expect(places.first { $0.id == .favorites }?.drop == .tag(ItemTag.favorite))
        #expect(places.first { $0.id == .recentlyDeleted }?.query == ItemQuery(states: [.trashed]))
        #expect(places.first { $0.id == .marfaTypes }?.query == nil)
        #expect(places.first { $0.id == .beneath(ItemID("p1")) }?.title == "Alpha")

        let noProjects = Catalogue(itemTypes: Self.catalogue.itemTypes.values.filter { $0.id != TypeID("aic.project") })
        #expect(!MarfaMapping.places(items: [], catalogue: noProjects).contains { $0.section == .projects })
    }

    @Test func aSnapshotTakesEachChangeInTurn() {
        let first = Self.item(Self.row("1")), second = Self.item(Self.row("2"))
        var snapshot = SourceSnapshot(items: [first], catalogue: Catalogue(), places: [])
        var edited = first
        edited.title = "Edited"
        snapshot.apply(.upserted([edited, second]))
        #expect(snapshot.items.map(\.title) == ["Edited", "Title"])
        snapshot.apply(.removed([first.id]))
        #expect(snapshot.items.map(\.id) == [second.id])
        snapshot.apply(.catalogue(Self.catalogue))
        #expect(snapshot.catalogue == Self.catalogue)
    }
}
