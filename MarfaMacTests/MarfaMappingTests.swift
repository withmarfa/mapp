import Foundation
import Marfa
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

@Suite(.hangLimit)
struct MarfaMappingTests {
    private static func field(_ name: String, _ type: String = "string", by owner: String, definition: JSONObject = [:])
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
            ItemType(id: "system.folder", label: "Folder", fields: [field("title", by: "system.folder")])
        ],
        edgeTypes: [
            EdgeType(id: "parent-of", label: "Parent of", cardinality: "one-to-many", reverseName: "child-of", writtenFrom: .to),
            EdgeType(id: "references", label: "References", cardinality: "many-to-many"),
            EdgeType(id: "supersedes", label: "Supersedes", cardinality: "one-to-one"),
            EdgeType(id: "in-folder", label: "In folder", cardinality: "many-to-many", toTypeConstraints: ["system.folder"])
        ])

    private static func row(
        _ id: String, type: String = "aic.ticket", properties: JSONObject = ["title": "Title", "body": "Body"],
        state: Marfa.ItemState = .active, tier: Marfa.Tier? = .library, version: Int64 = 3, tags: [String] = []
    ) -> Marfa.Item {
        Marfa.Item(
            id: id, type: type, properties: properties, state: state, tier: tier, version: version, schemaVersion: 1,
            source: "test", sourceId: nil, occurredAt: "2026-10-06T00:52:22.021Z", createdAt: "2026-10-06T00:52:22.021Z",
            updatedAt: "2026-10-06T01:00:00Z", tags: tags)
    }

    private static func edge(_ id: String, _ type: String, from source: String, to target: String) -> Marfa.Edge {
        Marfa.Edge(
            id: id, fromId: source, toId: target, edgeType: type, properties: [:], version: 1,
            createdAt: "2026-10-06T00:00:00Z", updatedAt: "2026-10-06T00:00:00Z")
    }

    /// `display` stands for what the core answers for the row's name and preview.
    private static func item(
        _ row: Marfa.Item, edges: [Marfa.Edge] = [], held: Set<String> = [], display: ItemDisplay? = nil
    ) -> MarfaMac.Item {
        MarfaMapping.item(
            row, edges: edges, catalogue: catalogue, display: display ?? SampleLibrary.display(ItemDisplayInput(type: row.type, properties: row.properties)),
            isHeld: { held.contains($0) })
    }

    // MARK: Rows the copy could not read

    @Test func aRowTheCopyCouldNotReadIsShownAsDamagedNotAsEmpty() {
        var damaged = Self.row("d", properties: [:], version: 7, tags: ["favorite"])
        damaged.unreadableProperties = "stored properties are not a JSON object"
        let shown = Self.item(damaged)

        #expect(shown.problem == ItemProblem(message: MarfaProblems.unreadableMessage, withholdsText: true))
        #expect(shown.preview == MarfaProblems.unreadableMessage, "the list says why, rather than showing a blank row")
        #expect(!shown.allows(.fields), "nothing is written from a row that shows none of what it holds")
        #expect(!shown.allows(.text), "and nothing typed over its empty page is written")
        #expect(shown.version == ItemVersion(7) && shown.tags == ["favorite"] && shown.state == .active)
        #expect(shown.properties.isEmpty)
    }

    @Test func aRowTheCopyReadsHasNoProblem() {
        let shown = Self.item(Self.row("r"))
        #expect(shown.problem == nil)
        #expect(shown.preview == "Body")
        #expect(shown.allows(.fields) && shown.allows(.text))
    }

    // MARK: Read only

    @Test func theServersAdviceThatAConnectorKeepsAnItemIsKept() {
        var kept = Self.row("k")
        kept.readOnly = true
        let shown = Self.item(kept)
        #expect(shown.readOnly)
        #expect(shown.obstacle(to: .fields) == .readOnly && shown.obstacle(to: .text) == .readOnly && shown.allows(.tags))
        #expect(shown.problem == nil, "it is advice, not a fault, so nothing is flagged as wrong")
        #expect(shown.state == .active && shown.preview == "Body", "and it is read as any other row")
        #expect(!Self.item(Self.row("w")).readOnly)
    }

    // MARK: The core's name and preview

    @Test func anItemIsNamedAndPreviewedAsTheCoreSays() {
        let row = Self.row("n", properties: ["title": "Stored", "body": "Stored body"])
        let shown = Self.item(row, display: ItemDisplay(name: "From the core", preview: "A line from the core"))
        #expect(shown.displayTitle == "From the core")
        #expect(shown.preview == "A line from the core")
        #expect(shown.title == "Stored", "the stored title is what an edit starts from and is untouched")
        #expect(!shown.isUntitled)
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
        #expect(task.fields.map(\.kind) == [.text, .date(includesTime: true), .choice(["open", "done"]), .text])
        #expect(task.fields.map(\.label) == ["Body", "Due At", "Status", "Title"])
    }

    @Test func anEdgeIsHeldAsManyTimesAsTheOtherEndAllows() throws {
        let parent = try #require(Self.catalogue.edgeTypes["parent-of"])
        #expect(parent.reverseName == "child-of")
        #expect(parent.writtenFrom == .to)
        #expect(parent.cardinality == .one)
        #expect(parent.fromTypes.isEmpty && parent.toTypes.isEmpty)
        #expect(Self.catalogue.edgeTypes["references"]?.cardinality == .many)
        #expect(Self.catalogue.edgeTypes["supersedes"]?.cardinality == .one)
        #expect(Self.catalogue.edgeTypes["in-folder"]?.toTypes == [TypeID("system.folder")])
        #expect(Self.catalogue.edgeType(named: "child-of")?.isReverse == true)
    }

    /// A move replaces an end only where the end that stays holds one edge of the type (`edges/move-to`,
    /// `edges/move-from`): the to item for `parent-of` (each child has one parent), the from item for a type where
    /// each from item holds one.
    @Test func eachEndSaysHowManyEdgesOfATypeItHolds() throws {
        let parent = try #require(Self.catalogue.edgeTypes["parent-of"])
        #expect(parent.cardinality(atTo: true) == .one)
        #expect(parent.cardinality(atTo: false) == .many)
        let supersedes = try #require(Self.catalogue.edgeTypes["supersedes"])
        #expect(supersedes.cardinality(atTo: true) == .one)
        #expect(supersedes.cardinality(atTo: false) == .one)
        let references = try #require(Self.catalogue.edgeTypes["references"])
        #expect(references.cardinality(atTo: true) == .many)
        #expect(references.cardinality(atTo: false) == .many)
        let thread = MarfaMapping.edgeType(EdgeType(id: MarfaMapping.threadEdge, label: "In thread", cardinality: "many-to-one"))
        #expect(thread.cardinality(atTo: false) == .one)
        #expect(thread.cardinality(atTo: true) == .many)
    }

    @Test func typesCarryTheRestOfTheirDefinition() throws {
        let catalogue = MarfaMapping.catalogue(
            itemTypes: [
                ItemType(
                    id: "core.contact", label: "Contact", description: "A person.", version: 4,
                    fields: [TypeField(name: "name", type: "string", required: true, description: "Full name", declaredBy: "core.contact")],
                    roles: ["person"])
            ],
            edgeTypes: [
                EdgeType(
                    id: "knows", label: "Knows", description: "Two people know each other.", cardinality: "one-to-many",
                    reverseName: "known-by", writtenFrom: .to, cascadeOnDelete: "block",
                    properties: [TypeField(name: "since", type: "date", declaredBy: "knows")]),
                EdgeType(id: "owns", label: "Owns", cardinality: "many-to-one", cascadeOnDelete: "cascade"),
                EdgeType(id: "next", label: "Next", cardinality: "one-to-one", cascadeOnDelete: "unknown")
            ])
        let contact = try #require(catalogue.itemTypes[TypeID("core.contact")])
        #expect(contact.description == "A person." && contact.version == 4)
        #expect(contact.roles == ["person"])
        #expect(contact.fields.first?.required == true && contact.fields.first?.description == "Full name")
        let knows = try #require(catalogue.edgeTypes["knows"])
        #expect(knows.description == "Two people know each other.")
        // One source per target, many targets per source, written at the target: the target holds one.
        #expect(knows.cardinality == .one && knows.reverseCardinality == .many)
        #expect(knows.cascadeOnDelete == .block)
        #expect(knows.properties.map(\.key) == ["since"] && knows.properties.first?.kind == .date(includesTime: false))
        let owns = try #require(catalogue.edgeTypes["owns"])
        #expect(owns.cardinality == .one && owns.reverseCardinality == .many && owns.cascadeOnDelete == .cascade)
        #expect(catalogue.edgeTypes["next"]?.cascadeOnDelete == .orphan)
    }

    @Test func titleAndBodyFallBackToTitleAndBodyWhereTheTypeDeclaresThem() {
        func type(_ id: String, _ fields: [String], title: String? = nil, body: String? = nil) -> ItemTypeInfo {
            MarfaMapping.itemType(ItemType(
                id: id, fields: fields.map { Self.field($0, by: id) }, titleField: title, bodyField: body))
        }
        // A type naming neither hint, as a folder does, is read under `title` and `body`.
        let folder = type("system.folder", ["title", "body", "path"])
        #expect(MarfaMapping.titleField(of: folder) == "title" && MarfaMapping.bodyField(of: folder) == "body")
        // A type naming only its body, as a message does, keeps its title under `title` where it has one.
        let message = type("core.message", ["text"], body: "text")
        #expect(MarfaMapping.titleField(of: message) == nil && MarfaMapping.bodyField(of: message) == "text")
        let titled = type("core.note", ["title", "text"], body: "text")
        #expect(MarfaMapping.titleField(of: titled) == "title")
        // A title hint alone leaves the body to `body` only where declared.
        let entity = type("core.entity", ["name"], title: "name")
        #expect(MarfaMapping.titleField(of: entity) == "name" && MarfaMapping.bodyField(of: entity) == nil)
        let aic = type("aic.project", ["title", "body"], title: "title", body: "body")
        #expect(MarfaMapping.titleField(of: aic) == "title" && MarfaMapping.bodyField(of: aic) == "body")
        // A type with neither hint nor fields has neither.
        let bare = type("system.connection", [])
        #expect(MarfaMapping.titleField(of: bare) == nil && MarfaMapping.bodyField(of: bare) == nil)
        // A type the catalogue lacks is titled by `title` and has no body.
        #expect(MarfaMapping.titleField(of: nil) == "title" && MarfaMapping.bodyField(of: nil) == nil)
    }

    @Test func anItemOfATypeWithoutHintsReadsItsTitleAndBodyUnderTitleAndBody() {
        let catalogue = MarfaMapping.catalogue(
            itemTypes: [ItemType(id: "system.folder", fields: [Self.field("title", by: "system.folder"), Self.field("body", by: "system.folder")])],
            edgeTypes: [])
        let row = Self.row("f1", type: "system.folder", properties: ["title": "Inbox", "body": "Everything unsorted."])
        let item = MarfaMapping.item(
            row, edges: [], catalogue: catalogue, display: SampleLibrary.display(ItemDisplayInput(type: row.type, properties: row.properties)), isHeld: { _ in false })
        #expect(item.title == "Inbox")
        #expect(item.titleRule == .property("title"))
        #expect(item.preview == "Everything unsorted.")
        #expect(!item.properties.contains { $0.key == "body" })
    }

    @Test func aRoleConstraintIsARoleAndNotAType() throws {
        let catalogue = MarfaMapping.catalogue(
            itemTypes: [],
            edgeTypes: [
                EdgeType(id: "in-collection", label: "In collection", cardinality: "many-to-many", toTypeConstraints: ["role:container"]),
                EdgeType(id: "mixed", label: "Mixed", cardinality: "many-to-many", fromTypeConstraints: ["core.note", "role:container"]),
                EdgeType(id: "open", label: "Open", cardinality: "many-to-many", fromTypeConstraints: ["*"], toTypeConstraints: ["*", "role:x"])
            ])
        let inCollection = try #require(catalogue.edgeTypes["in-collection"])
        #expect(inCollection.toTypes.isEmpty && inCollection.toRoles == ["container"])
        #expect(inCollection.fromTypes.isEmpty && inCollection.fromRoles.isEmpty)
        let mixed = try #require(catalogue.edgeTypes["mixed"])
        #expect(mixed.fromTypes == [TypeID("core.note")] && mixed.fromRoles == ["container"])
        let open = try #require(catalogue.edgeTypes["open"])
        #expect(open.fromTypes.isEmpty && open.fromRoles.isEmpty && open.toTypes.isEmpty && open.toRoles.isEmpty)
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

    @Test func propertiesKeepTheOrderTheServerGivesThemLeavingOutTheBody() {
        let ticket = Self.item(Self.row("t", properties: [
            "zeta": "z", "title": "Fix it", "body": "Long text", "assignee": "agent", "alpha": 2
        ]))
        #expect(ticket.properties.map(\.key) == ["zeta", "title", "assignee", "alpha"])
        #expect(ticket.value(of: "alpha") == .number(2))
        #expect(ticket.preview == "Long text")
        let reversed = Self.item(Self.row("t", properties: ["alpha": 2, "assignee": "agent", "title": "Fix it", "zeta": "z"]))
        #expect(reversed.properties.map(\.key) == ["alpha", "assignee", "title", "zeta"])
    }

    @Test func nestedObjectsKeepTheirKeysWhenWrittenBack() throws {
        let object: PropertyValue = .object(["b": .number(1), "a": .string("x")])
        let json = MarfaMapping.json(object)
        #expect(json.object?.keys == ["a", "b"])
        #expect(MarfaMapping.value(json) == object)
    }

    @Test func theRowsStateTierTagsVersionAndDatesCarryOver() {
        var row = Self.row("t", state: .trashed, tier: .feed, version: 7, tags: ["favorite", "work"])
        row.trashedAt = "2026-10-07T09:30:00Z"
        let item = Self.item(row)
        #expect(item.id == ItemID("t"))
        #expect(item.type == TypeID("aic.ticket"))
        #expect(item.state == .trashed)
        #expect(item.tier == .feed)
        #expect(item.tags == ["favorite", "work"])
        #expect(item.isFavorite)
        #expect(item.version == ItemVersion(7))
        #expect(abs(item.created.timeIntervalSince1970 - 1_791_247_942.021) < 0.001)
        #expect(item.modified == Date(timeIntervalSince1970: 1_791_248_400))
        #expect(item.trashed == Date(timeIntervalSince1970: 1_791_365_400))
        #expect(Self.item(Self.row("a")).trashed == nil)
        #expect(Self.item(Self.row("u", tier: nil)).tier == .library)
        #expect(Self.item(Self.row("r", state: .revoked)).state == .archived)
    }

    @Test func linksAndEmbedsThatNameNoItemAreShownAsEdgesOfTheText() {
        let links = BodyLinks(
            links: [
                BodyName(text: "[[Plan]]", name: "Plan", target: .item(id: "plan")),
                BodyName(text: "[[Plan|again]]", name: "Plan", target: .missing),
                BodyName(text: "[[Later]]", name: "Later", target: .pending),
                BodyName(text: "[[Nowhere]]", name: "Nowhere", target: .missing),
                BodyName(text: "[[Twin]]", name: "Twin", target: .ambiguous),
                BodyName(text: "[[Banned]]", name: "Banned", target: .refused(reason: "forbidden"))
            ],
            embeds: [
                BodyName(text: "![[cat.png]]", name: "cat.png", target: .item(id: "file")),
                BodyName(text: "![[dog.png]]", name: "dog.png", target: .missing)
            ])
        let item = MarfaMapping.item(
            Self.row("n"), edges: [Self.edge("e", "references", from: "n", to: "plan")], catalogue: Self.catalogue,
            bodyLinks: links, isHeld: { $0 == "plan" })
        // Those that name an item are the copy's own edges; the rest are the package's word that none is there.
        #expect(item.edgesOut.map(\.to) == [
            .item(ItemID("plan")), .unresolved(spelling: "Plan", ambiguous: false), .pending(spelling: "Later"), .unresolved(spelling: "Nowhere", ambiguous: false),
            .unresolved(spelling: "Twin", ambiguous: true), .refused(spelling: "Banned", reason: "forbidden"),
            .unresolved(spelling: "dog.png", ambiguous: false)
        ])
        #expect(item.edgesOut.map(\.type) == ["references", "references", "references", "references", "references", "references", "attached-to"])
        #expect(item.edgesOut.allSatisfy { $0.origin == .body })
        #expect(Set(item.edgesOut.map(\.id)).count == item.edgesOut.count)
        #expect(MarfaMapping.unresolvedLinks(of: "n", in: nil).isEmpty)
        // Each embed is kept, as written, with the file item the package bound it to, which is what the page shows.
        #expect(item.boundEmbeds == [
            BoundEmbed(text: "![[cat.png]]", resolution: .resolved(ItemID("file"))),
            BoundEmbed(text: "![[dog.png]]", resolution: .missing)
        ])
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
            MarfaMac.Edge(id: EdgeID("e1"), type: "child-of", from: ItemID("ticket"), to: .item(ItemID("project")),
                 origin: .property("child-of")),
            MarfaMac.Edge(id: EdgeID("e2"), type: "references", from: ItemID("ticket"), to: .item(ItemID("decision")),
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

    /// NSDecimalNumber's doubleValue lands an ulp off for many decimals, so -0.0788 would be stored as -0.07880000000000001.
    @Test func aDecimalGoesOutAsTheNearestDouble() {
        for text in ["-0.0788", "-0.054289", "-74.005974", "51.5246", "0.1"] {
            #expect(MarfaMapping.json(.number(Decimal(string: text)!)) == .number(Double(text)!), "\(text)")
        }
    }

    @Test func aLargeIntegerGoesBackAsTheSameInteger() {
        // 2^53 + 1 is the first integer a Double cannot hold, so a list edit that rewrote it through one would change it.
        for integer in [Int64(9_007_199_254_740_993), .max, .min, -9_007_199_254_740_993] {
            #expect(MarfaMapping.json(MarfaMapping.value(.integer(integer))) == .integer(integer), "\(integer)")
        }
        let entry: JSONValue = .array([.object(JSONObject([("count", .integer(9_007_199_254_740_993))]))])
        #expect(MarfaMapping.json(MarfaMapping.value(entry)) == entry)
        #expect(MarfaMapping.json(.number(Decimal(string: "9223372036854775808")!)) != .integer(.max))
    }

    @Test func aNumberBeyondDecimalsRangeGoesBackAsStored() {
        // Decimal holds no number above about 1e165 or nearer zero than about 1e-128; read through one, these were NaN.
        for number in [1e200, -1e200, 1e-200, 5e-324, Double.greatestFiniteMagnitude] {
            #expect(MarfaMapping.value(.number(number)) == .double(number), "\(number)")
            #expect(MarfaMapping.json(MarfaMapping.value(.number(number))) == .number(number), "\(number)")
        }
        let entry: JSONValue = .array([.object(JSONObject([("reading", .number(1e200))]))])
        #expect(MarfaMapping.json(MarfaMapping.value(entry)) == entry)
        #expect(MarfaMapping.value(.number(123.456)) == .number(Decimal(string: "123.456")!))
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
        #expect(MarfaMapping.outcome(.refused(unsent), afterRefusal: true) == .refused(SyncProblem(
            code: "refused_with_dependency", message: Words.unsent(.afterRefusal), unsent: .afterRefusal)))
        #expect(MarfaMapping.outcome(.conflicted(siblingId: "s", fields: ["body"])) ==
            .conflicted(sibling: ItemID("s"), fields: ["body"]))
        #expect(MarfaMapping.outcome(.blocked(reason: .keySpent)) == .blocked(.keySpent, nil))
        #expect(MarfaMapping.outcome(.blocked(reason: .failingAlone)) == .blocked(.failingAlone, nil))
        #expect(MarfaMapping.outcome(.blocked(reason: .instanceChanged)) == .blocked(.instanceChanged, nil))
        #expect(MarfaMapping.outcome(.blocked(reason: .recordUnread)) == .blocked(.recordUnread, nil))
        #expect(MarfaMapping.outcome(.blocked(reason: .serverRestored)) == .blocked(.serverRestored, nil))
        #expect(MarfaMapping.outcome(.dead) == .dead)
    }

    /// The copy also refuses writes unsent for reasons of their own, such as a delete with no confirmed version,
    /// with no code. Without a refused write it waited on, it is told only that it wasn't sent, never that an
    /// earlier change took it down.
    @Test func aRefusalWithNoCodeIsNotToldAsAfterAnother() {
        let reason = "the delete has no confirmed server version to remove; read the item before deleting it"
        let problem = MarfaMapping.problem(Refusal(reason: reason))
        #expect(problem.unsent == .notSent(reason: reason))
        #expect(problem.code == "refused_unsent")
        #expect(problem.message == Words.unsent(.notSent(reason: reason)))
        #expect(problem.message?.contains("earlier change") == false)
        // A code wins over the queue's say: the server refused it for itself.
        let server = MarfaMapping.problem(Refusal(reason: "validation_error", code: "validation_error"), afterRefusal: true)
        #expect(server.unsent == nil)
    }

    /// The server's answer with no `error.code` is stored with a one-word reason, and was sent: the server refused it.
    @Test func aServerAnswerWithNoCodeIsTheServersRefusal() {
        let problem = MarfaMapping.problem(Refusal(reason: "unknown", message: "Not allowed here."))
        #expect(problem.unsent == nil)
        #expect(problem.code == "unknown")
        #expect(problem.message == "Not allowed here.")
    }

    /// The copy refuses a write larger than the server takes before sending it, with no code and its reason in
    /// English. The person is told the sizes in the app's words, wherever the refusal is shown.
    @Test func aWriteTooLargeToSendIsToldWithItsSizes() throws {
        let refusal = Refusal(
            reason: "This write is 3,145,729 bytes as a request, and this server takes 3,145,728. Make it smaller to send it.",
            requestLimit: RequestLimit(size: 3_145_729, limit: 3_145_728))
        guard case .refused(let problem) = MarfaMapping.outcome(.refused(refusal)) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(problem.unsent == .tooLarge(size: 3_145_729, limit: 3_145_728))
        #expect(problem.code == "over_request_limit")
        let message = try #require(problem.message)
        let (size, limit) = Words.sizes(3_145_729, 3_145_728)
        #expect(size != limit, "sizes that would read the same carry their bytes")
        #expect(message.contains(size) && message.contains(limit))
        #expect(!message.localizedCaseInsensitiveContains("write"), "the queue's word is not the person's")

        let entry = SyncProblemEntry(
            id: .write("w"), itemID: ItemID("item"), kind: .refused, change: .edit, reason: problem,
            content: SyncContent(title: "Plan", body: "A very long note"), actions: MarfaProblems.actions(for: .refused))
        let wording = ProblemWording(entry) { _ in nil }
        #expect(wording.explanation.hasPrefix(message), "Settings says why, not only that it was refused")
        #expect(!wording.explanation.contains("The server refused it"), "the copy refused it, not the server")
    }

    /// Only a table row's conflict names no copy, and the app writes no rows, so such an answer leaves the item as
    /// merged rather than pointing at a copy that does not exist.
    @Test func aConflictNamingNoCopyIsReadAsMerged() {
        #expect(MarfaMapping.outcome(.conflicted(siblingId: nil, fields: ["title"])) == .merged(fields: ["title"]))
        #expect(MarfaMapping.outcome(.conflicted(siblingId: nil, fields: [])).syncState == .settled)
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
            Self.write("8", on: "e")
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

    /// The hub keeps what each change left, so a reader that starts late is told it as one `.loaded`, text too.
    @Test func aLateReaderStartsFromWhatEveryChangeLeft() async {
        let hub = MarfaHub()
        let first = Self.item(Self.row("1")), second = Self.item(Self.row("2"))
        hub.publish(.loaded(SourceSnapshot(items: [first], catalogue: Catalogue())))
        var edited = first
        edited.title = "Edited"
        let text = ItemBody(id: second.id, text: "Text", version: second.version)
        hub.publish(.changed(ItemChanges(upserted: [edited, second], bodies: [text])))
        hub.publish(.catalogue(Self.catalogue))
        let late = await Self.loaded(from: hub)
        #expect(Set(late?.items.map(\.title) ?? []) == ["Edited", "Title"])
        #expect(late?.bodies[second.id] == text)
        #expect(late?.catalogue == Self.catalogue)

        hub.publish(.changed(ItemChanges(removed: [second.id])))
        let later = await Self.loaded(from: hub)
        #expect(later?.items.map(\.id) == [first.id])
        #expect(later?.bodies[second.id] == nil)
    }

    /// What a reader starting now is told first.
    private static func loaded(from hub: MarfaHub) async -> SourceSnapshot? {
        var changes = hub.changes().makeAsyncIterator()
        guard case .loaded(let snapshot) = await changes.next() else { return nil }
        return snapshot
    }
}
