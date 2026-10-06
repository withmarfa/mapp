import Foundation
import Testing
@testable import MAPP

struct ItemLayerTests {
    private static let entity = TypeID("core.entity")
    private static let person = TypeID("core.entity.person")
    private static let author = TypeID("core.entity.person.author")
    private static let note = TypeID("core.note")

    private static let catalogue = Catalogue(
        itemTypes: [
            type(entity, fields: ["name"]),
            type(person, parent: entity, fields: ["name", "email"]),
            type(author, parent: person, fields: ["name", "email", "pen_name"]),
            type(note, fields: ["status", "priority"])
        ],
        edgeTypes: [
            EdgeTypeInfo(
                id: "parent-of", label: "Parent", reverseName: "child-of", cardinality: .one, writtenAt: .target,
                sourceTypes: [], targetTypes: [])
        ])

    private static func type(_ id: TypeID, parent: TypeID? = nil, fields: [String]) -> ItemTypeInfo {
        ItemTypeInfo(
            id: id, label: id.rawValue,
            fields: fields.map { .init(key: $0, label: $0, kind: .text, declaredBy: id) },
            titleField: "title", bodyField: "body", parent: parent)
    }

    private static func item(
        _ type: TypeID = note, state: ItemState = .active, tier: Tier = .library, container: ContainerID? = nil,
        tags: Set<String> = []
    ) -> Item {
        Item(
            id: .mint(), type: type, title: "Title", titleRule: .firstLine, state: state, tier: tier,
            container: container, tags: tags, version: ItemVersion(1), created: .now, modified: .now)
    }

    // MARK: Catalogue

    @Test func descendantsReachEveryLevelBelowButNotTheTypeItself() {
        #expect(Self.catalogue.descendants(of: Self.entity) == [Self.person, Self.author])
        #expect(Self.catalogue.descendants(of: Self.author).isEmpty)
        #expect(Self.catalogue.descendants(of: TypeID("unknown")).isEmpty)
    }

    @Test func aCycleInParentsEnds() {
        let a = TypeID("a"), b = TypeID("b")
        let catalogue = Catalogue(itemTypes: [Self.type(a, parent: b, fields: []), Self.type(b, parent: a, fields: [])])
        #expect(catalogue.descendants(of: a) == [b])
        #expect(!catalogue.isSubtype(a, ofAnyOf: [TypeID("c")]))
    }

    @Test func propertiesFollowTheCatalogueThenKeepTheRestAsGiven() {
        let given = [
            Property(key: "zeta", value: .string("z")),
            Property(key: "priority", value: .string("high")),
            Property(key: "alpha", value: .string("a")),
            Property(key: "status", value: .string("pending"))
        ]
        let ordered = Self.catalogue.ordered(given, for: Self.note)
        #expect(ordered.map(\.key) == ["status", "priority", "zeta", "alpha"])
    }

    @Test func unorderedPropertiesPutTheRestInKeyOrder() {
        let given: [String: PropertyValue] = ["zeta": .null, "priority": .null, "alpha": .null, "status": .null]
        #expect(Self.catalogue.ordered(given, for: Self.note).map(\.key) == ["status", "priority", "alpha", "zeta"])
        #expect(Self.catalogue.ordered(given, for: TypeID("unknown")).map(\.key) == ["alpha", "priority", "status", "zeta"])
    }

    @Test func anEdgeIsFoundByItsNameOrItsReverseName() throws {
        let forward = try #require(Self.catalogue.edgeType(named: "parent-of"))
        #expect(forward.info.id == "parent-of" && !forward.isReverse)
        let reverse = try #require(Self.catalogue.edgeType(named: "child-of"))
        #expect(reverse.info.id == "parent-of" && reverse.isReverse)
        #expect(Self.catalogue.edgeType(named: "about") == nil)
    }

    // MARK: Queries

    @Test func aTypeMatchesItsSubtypesUnlessAskedNotTo() {
        var query = ItemQuery(types: [Self.person])
        #expect(query.matches(Self.item(Self.person), catalogue: Self.catalogue))
        #expect(query.matches(Self.item(Self.author), catalogue: Self.catalogue))
        #expect(!query.matches(Self.item(Self.entity), catalogue: Self.catalogue))
        #expect(!query.matches(Self.item(Self.note), catalogue: Self.catalogue))
        query.includesSubtypes = false
        #expect(query.matches(Self.item(Self.person), catalogue: Self.catalogue))
        #expect(!query.matches(Self.item(Self.author), catalogue: Self.catalogue))
    }

    @Test func aQueryShowsActiveItemsUnlessItNamesOtherStates() {
        let trashed = Self.item(state: .trashed)
        #expect(ItemQuery().matches(Self.item(), catalogue: Self.catalogue))
        #expect(!ItemQuery().matches(trashed, catalogue: Self.catalogue))
        #expect(ItemQuery(states: [.trashed]).matches(trashed, catalogue: Self.catalogue))
        #expect(ItemQuery(states: []).matches(Self.item(state: .archived), catalogue: Self.catalogue))
    }

    @Test func everyTagNamedMustBePresent() {
        let query = ItemQuery(tags: [ItemTag.favorite, "work"])
        #expect(query.matches(Self.item(tags: [ItemTag.favorite, "work", "extra"]), catalogue: Self.catalogue))
        #expect(!query.matches(Self.item(tags: [ItemTag.favorite]), catalogue: Self.catalogue))
    }

    @Test func theInboxOfEachSourceTakesItsOwnItems() {
        let folder = ContainerID("folder")
        let filesInbox = ItemQuery(container: .root)
        #expect(filesInbox.matches(Self.item(), catalogue: Self.catalogue))
        #expect(!filesInbox.matches(Self.item(container: folder), catalogue: Self.catalogue))
        #expect(ItemQuery(container: .container(folder)).matches(Self.item(container: folder), catalogue: Self.catalogue))
        let marfaInbox = ItemQuery(tier: .feed)
        #expect(marfaInbox.matches(Self.item(tier: .feed), catalogue: Self.catalogue))
        #expect(!marfaInbox.matches(Self.item(), catalogue: Self.catalogue))
    }

    @Test func beneathTakesTheItemAndTheDescendantsGiven() {
        let project = Self.item(), child = Self.item(), other = Self.item()
        let query = ItemQuery(beneath: project.id)
        #expect(query.matches(project, catalogue: Self.catalogue))
        #expect(query.matches(child, catalogue: Self.catalogue, descendants: [child.id]))
        #expect(!query.matches(other, catalogue: Self.catalogue, descendants: [child.id]))
    }

    // MARK: Items and places

    @Test func aFavoriteIsAnItemTaggedFavorite() {
        #expect(Self.item(tags: [ItemTag.favorite]).isFavorite)
        #expect(!Self.item(tags: ["Favorite", "starred"]).isFavorite)
    }

    @Test func anItemIDEncodesAsItsString() throws {
        let id = ItemID("0198f2c4-7d1e-7a00-8000-000000000001")
        let data = try JSONEncoder().encode([id])
        #expect(String(decoding: data, as: UTF8.self) == #"["0198f2c4-7d1e-7a00-8000-000000000001"]"#)
        #expect(try JSONDecoder().decode([ItemID].self, from: data) == [id])
    }

    @Test(arguments: [
        PlaceID.inbox, .all, .favorites, .archive, .recentlyDeleted, .marfaTypes,
        .type(TypeID("core.note")), .beneath(ItemID("project")), .folder(ItemID("folder"))
    ])
    func aPlaceSurvivesEncoding(place: PlaceID) throws {
        let data = try JSONEncoder().encode(place)
        #expect(try JSONDecoder().decode(PlaceID.self, from: data) == place)
    }

    @Test func aDropWritesOnlyWhatWouldChange() {
        let folder = ContainerID("folder")
        let item = Self.item(container: folder, tags: [ItemTag.favorite])
        #expect(DropAction.move(to: folder).write(for: item) == nil)
        #expect(DropAction.move(to: nil).write(for: item) == .move(item.id, to: nil))
        #expect(DropAction.tag(ItemTag.favorite).write(for: item) == nil)
        #expect(DropAction.retier(.feed).write(for: item) == .retier(item.id, .feed, base: item.version))
        #expect(DropAction.transition(.trashed).write(for: item) == .transition(item.id, .trashed))
    }

    // MARK: Outcomes

    @Test func anOutcomeLeavesItsItemInTheMatchingState() {
        let sibling = ItemID("sibling")
        let refusal = SyncProblem(code: "validation_error", message: "Too long", fields: ["title": "too long"])
        #expect(WriteOutcome.accepted.syncState == .settled)
        #expect(WriteOutcome.merged(fields: ["title"]).syncState == .settled)
        #expect(WriteOutcome.conflicted(sibling: sibling, fields: ["body"]).syncState == .conflicted(sibling: sibling, fields: ["body"]))
        #expect(WriteOutcome.refused(refusal).syncState == .refused(refusal))
        #expect(WriteOutcome.blocked(.credentialRefused, SyncProblem(code: "unauthorized", message: "Sign in")).syncState
            == .blocked(SyncProblem(code: "credential_refused", message: "Sign in")))
        #expect(WriteOutcome.blocked(.keySpent, nil).syncState == .blocked(SyncProblem(code: "key_spent")))
        #expect(WriteOutcome.dead.syncState == .blocked(SyncProblem(code: "dead")))
    }
}

struct ItemIDTests {
    @Test func aMintedIDIsALowercaseUUIDv7InTimeOrder() throws {
        let early = ItemID.mint(at: Date(timeIntervalSince1970: 1_791_247_942.021))
        let late = ItemID.mint(at: Date(timeIntervalSince1970: 1_791_247_943))
        let text = early.rawValue
        #expect(text == text.lowercased())
        #expect(UUID(uuidString: text) != nil)
        let characters = Array(text)
        #expect(characters[14] == "7")
        #expect("89ab".contains(characters[19]))
        #expect(text.hasPrefix("01a10eb2-8185-7"))
        #expect(early.rawValue < late.rawValue)
        #expect(ItemID.mint() != ItemID.mint())
    }
}
