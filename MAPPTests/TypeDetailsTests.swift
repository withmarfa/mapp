import Foundation
import Testing
@testable import MAPP

struct TypeDetailsTests {
    private func detail(_ id: String) throws -> ItemTypeDetail {
        ItemTypeDetail(try #require(TypesFixtures.catalogue.itemTypes[TypeID(id)]), in: TypesFixtures.catalogue)
    }

    private func edge(_ id: String) throws -> EdgeTypeInfo {
        try #require(TypesFixtures.catalogue.edgeTypes[id])
    }

    // MARK: Item types

    @Test func inheritedFieldsAreMarkedWithTheTypeThatDeclaresThem() throws {
        let raw = try detail("core.file.image.raw")
        let byKey = Dictionary(uniqueKeysWithValues: raw.fields.map { ($0.field.key, $0) })
        #expect(byKey["exposure"]?.inheritedFrom == nil)
        #expect(byKey["width"]?.inheritedFrom?.label == "Image")
        #expect(byKey["blob_ref"]?.inheritedFrom?.id == TypeID("core.file"))
        #expect(byKey["blob_ref"]?.field.required == true)
        #expect(raw.fields.map(\.field.key) == ["blob_ref", "title", "width", "exposure"])
    }

    @Test func aTypeKeepsItsOwnFieldsUnmarked() throws {
        let file = try detail("core.file")
        #expect(file.fields.allSatisfy { $0.inheritedFrom == nil })
    }

    @Test func theParentChainRunsFromTheTopDownToTheDirectParent() throws {
        let raw = try detail("core.file.image.raw")
        #expect(raw.parents.map(\.label) == ["File", "Image"])
        #expect(raw.parents.allSatisfy { $0.isKnown })
        let file = try detail("core.file")
        #expect(file.parents.isEmpty)
    }

    @Test func aMissingParentIsNamedButNotLinked() throws {
        let bug = try detail("aic.ticket.bug")
        #expect(bug.parents.map(\.label) == ["aic.ticket"])
        #expect(bug.parents.map(\.isKnown) == [false])
    }

    @Test func aLoopOfParentsEndsTheChain() {
        let catalogue = Catalogue(itemTypes: [
            TypesFixtures.type("a.one", parent: "a.two"), TypesFixtures.type("a.two", parent: "a.one")
        ])
        let detail = ItemTypeDetail(catalogue.itemTypes[TypeID("a.one")]!, in: catalogue)
        #expect(detail.parents.map(\.id) == [TypeID("a.two")])
    }

    @Test func compatibilityReadsBothWays() throws {
        let person = try detail("core.entity.person")
        #expect(person.compatibleWith.map(\.label) == ["Contact"])
        let contact = try detail("core.contact")
        #expect(contact.compatibleFrom.map(\.label) == ["Person"])
        #expect(contact.compatibleWith.isEmpty)
    }

    @Test func titleAndBodyAreUnderTheHintsFieldsOrUnderTitleAndBody() {
        let named = ItemTypeDetail(
            TypesFixtures.type("a.x", fields: [TypesFixtures.field("name", by: "a.x")], titleField: "name"), in: Catalogue())
        #expect(named.titleProperty == "name" && named.declaresTitle)
        #expect(named.bodyProperty == nil)
        // A type naming neither hint is read under `title` and `body`, where it declares them.
        let folder = ItemTypeDetail(
            TypesFixtures.type("a.folder", fields: [
                TypesFixtures.field("title", by: "a.folder"), TypesFixtures.field("body", by: "a.folder")
            ], titleField: nil), in: Catalogue())
        #expect(folder.titleProperty == "title" && folder.declaresTitle && folder.bodyProperty == "body")
        let bare = ItemTypeDetail(TypesFixtures.type("a.bare", titleField: nil), in: Catalogue())
        #expect(bare.titleProperty == "title" && !bare.declaresTitle && bare.bodyProperty == nil)
        // A type naming only its body field is still titled by `title`.
        let message = ItemTypeDetail(
            TypesFixtures.type("a.message", fields: [TypesFixtures.field("text", by: "a.message")], titleField: nil, bodyField: "text"),
            in: Catalogue())
        #expect(message.titleProperty == "title" && message.bodyProperty == "text")
    }

    @Test func edgeTypesThatNameATypeOrOneAboveItConnectIt() throws {
        let raw = try detail("core.file.image.raw")
        #expect(raw.edgeTypes.map(\.edge.id) == ["attached-to"])
        #expect(raw.edgeTypes.first?.role == .source)
        let person = try detail("core.entity.person")
        #expect(person.edgeTypes.map(\.edge.id) == ["attached-to"])
        #expect(person.edgeTypes.first?.role == .target)
        #expect(person.edgeTypes.first?.edge.reverseName == "has-attachment")
    }

    @Test func edgeTypesThatLimitNoTypesAreNotListedForEveryType() throws {
        let contact = try detail("core.contact")
        #expect(contact.edgeTypes.isEmpty)
    }

    @Test func aTypeAtBothEndsOfAnEdgeReadsAsEither() {
        let catalogue = Catalogue(
            itemTypes: [TypesFixtures.type("a.x")],
            edgeTypes: [TypesFixtures.edge("links", from: ["a.x"], to: ["a.x"])])
        let detail = ItemTypeDetail(catalogue.itemTypes[TypeID("a.x")]!, in: catalogue)
        #expect(detail.edgeTypes.map(\.role) == [.either])
    }

    @Test func aRoleConstraintListsTheTypesThatPlayTheRole() throws {
        let album = try detail("core.media.album")
        #expect(album.edgeTypes.map(\.edge.id) == ["in-collection"])
        #expect(album.edgeTypes.first?.role == .target)
        // The role is the type's own: a subtype does not declare it.
        #expect(try detail("core.media.album.live").edgeTypes.isEmpty)
        #expect(try detail("core.contact").edgeTypes.isEmpty)
    }

    @Test func anEndConstrainedByRoleIsNotAnyType() throws {
        let inCollection = try edge("in-collection")
        #expect(!inCollection.allowsAnyTarget() && inCollection.allowsAnySource())
        let detail = EdgeTypeDetail(inCollection, in: TypesFixtures.catalogue)
        #expect(detail.targetTypes.isEmpty && detail.targetRoles == ["container"])
        #expect(detail.sourceRoles.isEmpty)
        #expect(roleWording("container") == "Types with the role container")
    }

    // MARK: Edge types

    @Test func anEdgeTypeNamesItsEndsAndLeavesAnyTypeEmpty() throws {
        let attached = EdgeTypeDetail(try edge("attached-to"), in: TypesFixtures.catalogue)
        #expect(attached.sourceTypes.map(\.label) == ["File"])
        #expect(attached.targetTypes.map(\.label) == ["Entity"])
        let parent = EdgeTypeDetail(try edge("parent-of"), in: TypesFixtures.catalogue)
        #expect(parent.sourceTypes.isEmpty && parent.targetTypes.isEmpty)
    }

    @Test func anEndNamingATypeTheCatalogueLacksKeepsItsId() {
        let edge = TypesFixtures.edge("links", to: ["gone.type"])
        let detail = EdgeTypeDetail(edge, in: Catalogue(edgeTypes: [edge]))
        #expect(detail.targetTypes.map(\.label) == ["gone.type"] && detail.targetTypes.map(\.isKnown) == [false])
    }

    @Test func cardinalityIsGivenFromSourceToTargetWhicheverEndWritesTheEdge() throws {
        // parent-of: written at the child, which holds one parent; a parent holds many children.
        let parent = try edge("parent-of")
        #expect(parent.sourcesPerTarget == .one && parent.targetsPerSource == .many)
        #expect(parent.sourceEndWording == "Each can point to many items.")
        #expect(parent.targetEndWording == "Each can be pointed to by one item at most.")
        // attached-to: written at the file, which holds one host; a host holds many files.
        let attached = try edge("attached-to")
        #expect(attached.targetsPerSource == .one && attached.sourcesPerTarget == .many)
        #expect(attached.sourceEndWording == "Each can point to one item at most.")
        #expect(attached.targetEndWording == "Each can be pointed to by many items.")
        let references = try edge("references")
        #expect(references.sourceEndWording == "Each can point to many items.")
        #expect(references.targetEndWording == "Each can be pointed to by many items.")
    }

    @Test func aOneToOneEdgeLimitsBothEnds() {
        let supersedes = TypesFixtures.edge("supersedes", held: .one, other: .one)
        #expect(supersedes.sourceEndWording == "Each can point to one item at most.")
        #expect(supersedes.targetEndWording == "Each can be pointed to by one item at most.")
    }

    @Test func whereAnEdgeIsWrittenAndWhatDeletingDoesAreInPlainWords() throws {
        let parent = try edge("parent-of")
        let references = try edge("references")
        #expect(parent.writtenAtWording == "The item it points to")
        #expect(references.writtenAtWording == "The item it points from")
        #expect(parent.cascadeWording == "Deleting the item it points from also deletes the item it points to")
        #expect(references.cascadeWording == "Deleting either item keeps the other")
        #expect(TypesFixtures.edge("x", cascade: .block).cascadeWording == "Deleting either item is refused while the connection exists")
    }

    @Test func fieldKindsReadAsPlainWords() {
        let kinds: [ItemTypeInfo.Field.Kind] = [.text, .number, .boolean, .date, .choice(["a"]), .other]
        #expect(kinds.map(\.wording) == ["Text", "Number", "Yes or no", "Date", "Choice", "Other"])
    }
}
