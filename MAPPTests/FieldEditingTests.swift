@testable import MAPP
import MarfaAPI
import Testing

private let media = TypeID("core.media")
private let entry = TypeID("app.books.entry")
private let review = TypeID("app.books.review")

/// A shipped type, a type of the owner's below it, and one below that.
private func catalogue() -> Catalogue {
    let rating = ItemTypeInfo.Field(key: "rating", label: "Rating", kind: .choice(["good", "bad"]), declaredBy: media)
    let genre = ItemTypeInfo.Field(key: "genre", label: "Genre", kind: .choice(["fiction", "history"]), declaredBy: entry)
    let shelf = ItemTypeInfo.Field(key: "shelf", label: "Shelf", kind: .text, declaredBy: entry)
    let notes = ItemTypeInfo.Field(key: "notes", label: "Notes", kind: .text, declaredBy: entry)
    let isbn = ItemTypeInfo.Field(key: "isbn", label: "ISBN", kind: .text, declaredBy: entry)
    let reviewer = ItemTypeInfo.Field(key: "reviewer", label: "Reviewer", kind: .text, declaredBy: review)
    return Catalogue(itemTypes: [
        ItemTypeInfo(id: media, label: "Media", fields: [rating], titleField: "title", bodyField: nil, parent: nil),
        ItemTypeInfo(
            id: entry, label: "Entry", fields: [rating, genre, shelf, notes, isbn], titleField: "title", bodyField: "notes",
            parent: media, linkField: "isbn"),
        ItemTypeInfo(
            id: review, label: "Review", fields: [rating, genre, shelf, notes, isbn, reviewer], titleField: "title",
            bodyField: "notes", parent: entry, linkField: "isbn"),
    ])
}

@Suite struct FieldLockTests {
    @Test func aFieldTheTypeDeclaresItselfIsTheOwnersToChange() throws {
        let info = try #require(catalogue().itemTypes[entry])
        #expect(info.lock(of: try #require(info.fields.first { $0.key == "genre" }), in: catalogue()) == nil)
    }

    @Test func anInheritedFieldShowsTheTypeItComesFrom() throws {
        let info = try #require(catalogue().itemTypes[entry])
        #expect(info.lock(of: try #require(info.fields.first { $0.key == "rating" }), in: catalogue()) == .inherited(from: media))
    }

    @Test func aFieldComesFromTheNearestTypeAlongTheChain() throws {
        let info = try #require(catalogue().itemTypes[review])
        #expect(info.lock(of: try #require(info.fields.first { $0.key == "genre" }), in: catalogue()) == .inherited(from: entry))
        #expect(info.lock(of: try #require(info.fields.first { $0.key == "rating" }), in: catalogue()) == .inherited(from: media))
        #expect(info.lock(of: try #require(info.fields.first { $0.key == "reviewer" }), in: catalogue()) == nil)
    }

    @Test func aFieldAChildRedeclaresIsLockedToo() throws {
        // Marfa names only the nearest type that declares a field, so the child's own redeclaration of `rating`
        // (required, narrowed choices) shows the child as the declarer.
        let narrowed = ItemTypeInfo.Field(key: "rating", label: "Rating", kind: .choice(["good"]), declaredBy: entry)
        var redeclared = catalogue()
        let before = try #require(redeclared.itemTypes[entry])
        redeclared.itemTypes[entry] = ItemTypeInfo(
            id: entry, label: before.label, fields: before.fields.map { $0.key == "rating" ? narrowed : $0 },
            titleField: before.titleField, bodyField: before.bodyField, parent: media, linkField: before.linkField)
        let info = try #require(redeclared.itemTypes[entry])
        let field = try #require(info.fields.first { $0.key == "rating" })
        #expect(field.declaredBy == entry)
        #expect(info.lock(of: field, in: redeclared) == .inherited(from: media))
        #expect(throws: FieldEditRefusal.locked(.inherited(from: media))) { try info.plan(.remove(key: "rating"), in: redeclared) }
        #expect(throws: FieldEditRefusal.locked(.inherited(from: media))) {
            try info.plan(.setChoices(key: "rating", choices: ["good", "bad"]), in: redeclared)
        }
    }

    @Test func aStatusFieldAChildRedeclaresIsLockedAndNamesTheNearestAncestorThatDeclaresIt() throws {
        let words = [StatusWord(value: "open", group: .notStarted), StatusWord(value: "done", group: .completed)]
        let own = { (declaredBy: TypeID) in ItemTypeInfo.Field(key: "state", label: "State", kind: .status(words), declaredBy: declaredBy) }
        let top = ItemTypeInfo(id: media, label: "Media", fields: [own(media)], titleField: nil, bodyField: nil, parent: nil)
        let middle = ItemTypeInfo(id: entry, label: "Entry", fields: [own(entry)], titleField: nil, bodyField: nil, parent: media)
        let bottom = ItemTypeInfo(id: review, label: "Review", fields: [own(review)], titleField: nil, bodyField: nil, parent: entry)
        let chain = Catalogue(itemTypes: [top, middle, bottom])
        let field = try #require(bottom.fields.first)
        #expect(bottom.lock(of: field, in: chain) == .inherited(from: entry))
        #expect(throws: FieldEditRefusal.locked(.inherited(from: entry))) { try bottom.plan(.remove(key: "state"), in: chain) }
        #expect(middle.lock(of: try #require(middle.fields.first), in: chain) == .inherited(from: media))
    }

    @Test func everyFieldOfAShippedTypeIsLocked() throws {
        let info = try #require(catalogue().itemTypes[media])
        #expect(info.fields.allSatisfy { info.lock(of: $0, in: catalogue()) == .shipped })
        #expect(info.fields.count == 1)
    }

    @Test func theReservedRootsAreShippedAndNoOtherIs() {
        #expect(["core.task", "core.media.book", "system.view", "marfa.thing"].allSatisfy { TypeID($0).isShipped })
        #expect(["app.books.entry", "acme.deal", "corex.thing", "local.core"].allSatisfy { !TypeID($0).isShipped })
    }
}

@Suite struct FieldEditPlanTests {
    private let info = catalogue().itemTypes[entry]!

    @Test func renamingKeepsTheKeyAndTrimsTheName() throws {
        let plan = try info.plan(.rename(key: "shelf", label: "  Where it sits \n"), in: catalogue())
        #expect(plan.edit == .rename(key: "shelf", label: "Where it sits"))
        #expect(plan.shown.label == "Shelf")
    }

    @Test func aBlankNameIsRefused() {
        #expect(throws: FieldEditRefusal.blankLabel) { try info.plan(.rename(key: "shelf", label: ""), in: catalogue()) }
        #expect(throws: FieldEditRefusal.blankLabel) { try info.plan(.rename(key: "shelf", label: "   \n "), in: catalogue()) }
    }

    @Test func aNameAnotherFieldHasIsRefusedWhateverItsCase() {
        #expect(throws: FieldEditRefusal.labelInUse("genre")) { try info.plan(.rename(key: "shelf", label: "genre"), in: catalogue()) }
        // The inherited field's name counts too.
        #expect(throws: FieldEditRefusal.labelInUse("Rating")) { try info.plan(.rename(key: "shelf", label: "Rating"), in: catalogue()) }
    }

    @Test func aFieldMayTakeANewSpellingOfItsOwnName() throws {
        #expect(try info.plan(.rename(key: "shelf", label: "SHELF"), in: catalogue()).edit == .rename(key: "shelf", label: "SHELF"))
    }

    @Test func aNameOverAHundredCharactersIsRefused() {
        #expect(throws: FieldEditRefusal.labelTooLong) { try info.plan(.rename(key: "shelf", label: String(repeating: "a", count: 101)), in: catalogue()) }
    }

    @Test func aLockedFieldIsRefusedBeforeAnythingIsSent() {
        #expect(throws: FieldEditRefusal.locked(.inherited(from: media))) { try info.plan(.rename(key: "rating", label: "Mark"), in: catalogue()) }
        #expect(throws: FieldEditRefusal.locked(.inherited(from: media))) { try info.plan(.remove(key: "rating"), in: catalogue()) }
        let shipped = catalogue().itemTypes[media]!
        #expect(throws: FieldEditRefusal.locked(.shipped)) { try shipped.plan(.rename(key: "rating", label: "Mark"), in: catalogue()) }
    }

    @Test func aFieldTheTypeLacksIsRefused() {
        #expect(throws: FieldEditRefusal.unknownField) { try info.plan(.remove(key: "gone"), in: catalogue()) }
    }

    @Test func choicesKeepTheirOrderAndNameWhatIsTakenAway() throws {
        let plan = try info.plan(.setChoices(key: "genre", choices: ["poetry", " fiction ", "memoir"]), in: catalogue())
        #expect(plan.edit == .setChoices(key: "genre", choices: ["poetry", "fiction", "memoir"]))
    }

    @Test func theLastChoiceCannotBeRemoved() {
        #expect(throws: FieldEditRefusal.noChoices) { try info.plan(.setChoices(key: "genre", choices: []), in: catalogue()) }
    }

    @Test func aBlankOrRepeatedChoiceIsRefused() {
        #expect(throws: FieldEditRefusal.blankChoice) { try info.plan(.setChoices(key: "genre", choices: ["fiction", " "]), in: catalogue()) }
        #expect(throws: FieldEditRefusal.repeatedChoice("fiction")) {
            try info.plan(.setChoices(key: "genre", choices: ["fiction", "history", " fiction "]), in: catalogue())
        }
    }

    @Test func aWordTheFieldOffersGoesBackAsTheServerHoldsIt() throws {
        let stage = ItemTypeInfo.Field(key: "stage", label: "Stage", kind: .choice([" Draft", "Done", "Done"]), declaredBy: TypeID("user.stage"))
        let type = ItemTypeInfo(id: TypeID("user.stage"), label: "Stage", fields: [stage], titleField: "title", bodyField: nil, parent: nil)
        let plan = try type.plan(.setChoices(key: "stage", choices: [" Draft", "Done", "Done", " Final "]), in: catalogue())
        #expect(plan.edit == .setChoices(key: "stage", choices: [" Draft", "Done", "Done", "Final"]))
    }

    @Test func onlyAChoiceFieldTakesChoices() {
        #expect(throws: FieldEditRefusal.notAChoiceField) { try info.plan(.setChoices(key: "shelf", choices: ["a"]), in: catalogue()) }
    }

    @Test func theTitleTheTextAndTheSourceLinkCannotBeRemoved() {
        #expect(throws: FieldEditRefusal.holdsPageContent) { try info.plan(.remove(key: "notes"), in: catalogue()) }
        #expect(throws: FieldEditRefusal.holdsPageContent) { try info.plan(.remove(key: "isbn"), in: catalogue()) }
    }

    @Test func anOrdinaryFieldCanBeRemoved() throws {
        #expect(try info.plan(.remove(key: "shelf"), in: catalogue()).edit == .remove(key: "shelf"))
    }
}

@Suite struct ChoiceDraftTests {
    @Test func theWordsAFieldOffersAreNotTypedOverAndTheOnesAddedAre() {
        var draft = ChoiceDraft(existing: ["fiction", "history"])
        #expect(draft.rows.map(\.isNew) == [false, false])
        draft.add()
        #expect(draft.rows.map(\.isNew) == [false, false, true])
        #expect(draft.choices == ["fiction", "history", ""])
    }

    @Test func anExistingWordCanBeTakenOutOrMovedAndNewOnesFollow() throws {
        var draft = ChoiceDraft(existing: ["fiction", "history", "memoir"])
        draft.remove(try #require(draft.rows.first { $0.text == "history" }).id)
        draft.rows.reverse()
        draft.add()
        draft.rows[draft.rows.count - 1].text = "poetry"
        #expect(draft.choices == ["memoir", "fiction", "poetry"])
    }

    @Test func aWordThatReplacesAnotherInTheSameStepIsATakingOutAndAnAddingNeverARename() throws {
        let info = try #require(catalogue().itemTypes[entry])
        var draft = ChoiceDraft(existing: ["fiction", "history"])
        draft.remove(try #require(draft.rows.first { $0.text == "history" }).id)
        draft.add()
        draft.rows[draft.rows.count - 1].text = "story"
        let plan = try info.plan(.setChoices(key: "genre", choices: draft.choices), in: catalogue())
        #expect(plan.edit == .setChoices(key: "genre", choices: ["fiction", "story"]))
        #expect(draft.rows.filter(\.isNew).map(\.text) == ["story"], "only the added word was typed")
    }
}

@Suite struct CatalogueFieldEditTests {
    @Test func aRenameShowsInTheTypeAndEveryTypeBelowItThatInheritsTheField() throws {
        let plan = try #require(catalogue().itemTypes[entry]).plan(.rename(key: "genre", label: "Kind"), in: catalogue())
        let changed = catalogue().applying(plan)
        #expect(changed.itemTypes[entry]?.fields.first { $0.key == "genre" }?.label == "Kind")
        #expect(changed.itemTypes[review]?.fields.first { $0.key == "genre" }?.label == "Kind")
        #expect(changed.itemTypes[media]?.fields.map(\.label) == ["Rating"])
        // Nothing else moved.
        #expect(changed.itemTypes[entry]?.fields.map(\.key) == ["rating", "genre", "shelf", "notes", "isbn"])
        #expect(changed.itemTypes[entry]?.fields.first { $0.key == "rating" }?.label == "Rating")
    }

    @Test func aChoiceEditChangesOnlyThatFieldsChoices() throws {
        let plan = try #require(catalogue().itemTypes[entry]).plan(.setChoices(key: "genre", choices: ["poetry", "fiction"]), in: catalogue())
        let changed = catalogue().applying(plan)
        #expect(changed.itemTypes[review]?.fields.first { $0.key == "genre" }?.kind == .choice(["poetry", "fiction"]))
        #expect(changed.itemTypes[entry]?.fields.first { $0.key == "rating" }?.kind == .choice(["good", "bad"]))
    }

    @Test func aRemovalTakesTheFieldFromTheTypeAndItsSubtypesOnly() throws {
        let plan = try #require(catalogue().itemTypes[entry]).plan(.remove(key: "shelf"), in: catalogue())
        let changed = catalogue().applying(plan)
        #expect(changed.itemTypes[entry]?.fields.map(\.key) == ["rating", "genre", "notes", "isbn"])
        #expect(changed.itemTypes[review]?.fields.map(\.key) == ["rating", "genre", "notes", "isbn", "reviewer"])
        #expect(changed.itemTypes[media]?.fields.map(\.key) == ["rating"])
    }

    @Test func theChangeKeepsTheRestOfTheTypeAndTheFieldLabelsCatalogue() throws {
        let plan = try #require(catalogue().itemTypes[entry]).plan(.rename(key: "shelf", label: "Place"), in: catalogue())
        let changed = catalogue().applying(plan)
        #expect(changed.itemTypes[entry]?.parent == media)
        #expect(changed.itemTypes[entry]?.linkField == "isbn")
        #expect(changed.label(ofField: "shelf", for: entry) == "Place")
    }
}

@Suite struct TypeDefinitionEditTests {
    private typealias Definition = Components.Schemas.FieldDefinition

    private func listed(genre: Definition? = nil) -> TypeDefinitionEdit.Listed {
        var fields: [String: Definition] = [
            "genre": genre ?? Definition(_type: .string, label: "Genre", enumValues: ["fiction", "history"]),
            "shelf": Definition(_type: .string, label: "Shelf", description: "Where it sits", maxLength: 40),
            "notes": Definition(_type: .string),
        ]
        fields["isbn"] = Definition(_type: .string, required: true)
        let definition = Components.Schemas.TypeDefinition(
            id: entry.rawValue, label: "Entry", plural: "Entries", description: "A book", parent: media.rawValue,
            roles: [.container],
            fields: .init(additionalProperties: fields),
            tables: .init(additionalProperties: [:]), version: 7,
            displayHints: .init(titleField: "title", bodyField: "notes", icon: "lucide:book"), linkField: "isbn")
        return .init(
            value1: definition, value2: .init(provenance: .init(origin: .registered), ownRoles: [.container]))
    }

    private func plan(_ edit: FieldEdit) throws -> FieldEditPlan {
        try #require(catalogue().itemTypes[entry]).plan(edit, in: catalogue())
    }

    @Test func aRenameChangesOnlyThatFieldsLabelAndSendsEverythingElseBack() throws {
        let update = try TypeDefinitionEdit.update(listed(), for: plan(.rename(key: "genre", label: "Kind")))
        let sent = update.fields.additionalProperties
        #expect(sent["genre"]?.label == "Kind")
        #expect(sent["genre"]?.enumValues == ["fiction", "history"])
        #expect(sent["shelf"] == listed().value1.fields.additionalProperties["shelf"])
        #expect(sent["isbn"]?.required == true)
        #expect(Set(sent.keys) == ["genre", "shelf", "notes", "isbn"])
        #expect(update.parent == media.rawValue)
        #expect(update.label == "Entry" && update.plural == "Entries" && update.description == "A book")
        #expect(update.version == 7)
        #expect(update.roles == ["container"])
        #expect(update.displayHints?.icon == "lucide:book" && update.displayHints?.bodyField == "notes")
        #expect(update.linkField == "isbn")
    }

    @Test func aFieldTheParentDeclaresIsNeverWrittenIntoTheChild() throws {
        let update = try TypeDefinitionEdit.update(listed(), for: plan(.rename(key: "genre", label: "Kind")))
        #expect(update.fields.additionalProperties["rating"] == nil)
    }

    @Test func aChoiceEditReplacesTheChoicesOnly() throws {
        let update = try TypeDefinitionEdit.update(listed(), for: plan(.setChoices(key: "genre", choices: ["poetry", "fiction"])))
        #expect(update.fields.additionalProperties["genre"]?.enumValues == ["poetry", "fiction"])
        #expect(update.fields.additionalProperties["genre"]?.label == "Genre")
    }

    @Test func aRemovalDropsThatFieldAlone() throws {
        let update = try TypeDefinitionEdit.update(listed(), for: plan(.remove(key: "shelf")))
        #expect(Set(update.fields.additionalProperties.keys) == ["genre", "notes", "isbn"])
    }

    @Test func aFieldNoLongerOnTheServerRefusesTheChange() throws {
        var gone = listed()
        gone.value1.fields.additionalProperties["genre"] = nil
        #expect(throws: TypeSchemaFailure.changedOnServer) { try TypeDefinitionEdit.update(gone, for: plan(.rename(key: "genre", label: "Kind"))) }
    }

    @Test func aLabelAnotherAppChangedRefusesTheChange() throws {
        let renamed = listed(genre: Definition(_type: .string, label: "Style", enumValues: ["fiction", "history"]))
        #expect(throws: TypeSchemaFailure.changedOnServer) { try TypeDefinitionEdit.update(renamed, for: plan(.rename(key: "genre", label: "Kind"))) }
    }

    @Test func choicesAnotherAppChangedRefuseTheChange() throws {
        let changed = listed(genre: Definition(_type: .string, label: "Genre", enumValues: ["fiction", "history", "poetry"]))
        #expect(throws: TypeSchemaFailure.changedOnServer) {
            try TypeDefinitionEdit.update(changed, for: plan(.setChoices(key: "genre", choices: ["fiction"])))
        }
    }

    @Test func nothingIsReplacedWhenTheCheckRefuses() async throws {
        var replaced = 0
        let renamed = listed(genre: Definition(_type: .string, label: "Style", enumValues: ["fiction", "history"]))
        let edit = try plan(.rename(key: "genre", label: "Kind"))
        await #expect(throws: TypeSchemaFailure.changedOnServer) {
            try await TypeDefinitionEdit.run(edit, read: { [renamed] }, replace: { _ in replaced += 1 })
        }
        #expect(replaced == 0)
    }

    @Test func aFieldATypeAboveDeclaresOnTheServerRefusesTheChange() async throws {
        var replaced = 0
        let parent = Components.Schemas.TypeDefinition(
            id: media.rawValue, label: "Media", plural: "Media", description: "Media", parent: nil,
            roles: [],
            fields: .init(additionalProperties: ["genre": Definition(_type: .string, label: "Genre")]),
            tables: .init(additionalProperties: [:]), version: 1,
            displayHints: .init(titleField: "title"), linkField: nil)
        let above = TypeDefinitionEdit.Listed(value1: parent, value2: .init(provenance: .init(origin: .registered), ownRoles: []))
        let edit = try plan(.remove(key: "genre"))
        await #expect(throws: TypeSchemaFailure.changedOnServer) {
            try await TypeDefinitionEdit.run(edit, read: { [listed(), above] }, replace: { _ in replaced += 1 })
        }
        #expect(replaced == 0)
    }

    @Test func aTypeTheServerNoLongerListsRefusesTheChange() async throws {
        var replaced = 0
        let edit = try plan(.remove(key: "shelf"))
        await #expect(throws: TypeSchemaFailure.changedOnServer) {
            try await TypeDefinitionEdit.run(edit, read: { [] }, replace: { _ in replaced += 1 })
        }
        #expect(replaced == 0)
    }

    @Test func theReplacementIsSentOnceWhenTheFieldIsAsShown() async throws {
        var sent: [TypeDefinitionEdit.Update] = []
        let edit = try plan(.rename(key: "genre", label: "Kind"))
        try await TypeDefinitionEdit.run(edit, read: { [listed()] }, replace: { sent.append($0) })
        #expect(sent.count == 1)
        #expect(sent.first?.fields.additionalProperties["genre"]?.label == "Kind")
    }
}

private struct FakeTypeSchemas: TypeSchemaSource {
    var answer: TypeSchemaFailure?
    func apply(_ plan: FieldEditPlan) async throws(TypeSchemaFailure) {
        if let answer { throw answer }
    }
}

@Suite(.hangLimit)
@MainActor struct MarfaLibraryFieldEditTests {
    private func open(_ answer: TypeSchemaFailure? = nil) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices(), typeSchemas: FakeTypeSchemas(answer: answer))
        source.send(.loaded(SourceSnapshot(items: [], catalogue: catalogue())))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private func rename(_ library: MarfaLibrary) throws -> FieldEditPlan {
        try #require(library.catalogue.itemTypes[entry]).plan(.rename(key: "shelf", label: "Place"), in: library.catalogue)
    }

    @Test func aServerRefusalLeavesTheCatalogueAsItWas() async throws {
        for failure in [TypeSchemaFailure.unreachable, .notPermitted, .keyRefused, .refused("invalid_schema"), .changedOnServer, .failed("no")] {
            let (library, _) = try await open(failure)
            let before = library.catalogue
            #expect(await library.editField(try rename(library)) == failure)
            #expect(library.catalogue == before)
        }
    }

    @Test func aLibraryWithNoServerKeepsNothing() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: [], catalogue: catalogue())))
        try #require(await eventually { library.isLoaded })
        #expect(await library.editField(try rename(library)) == .unsupported)
        #expect(library.catalogue == catalogue())
    }

    @Test func theChangeShowsAtOnceAndSurvivesAStaleRead() async throws {
        let (library, source) = try await open()
        #expect(await library.editField(try rename(library)) == nil)
        #expect(library.catalogue.label(ofField: "shelf", for: entry) == "Place")
        // The working copy has not heard of the change yet.
        source.send(.catalogue(catalogue()))
        #expect(await eventually { library.catalogue.label(ofField: "shelf", for: entry) == "Place" })
        #expect(library.catalogue.label(ofField: "shelf", for: review) == "Place")
    }

    @Test func theCopyCatchingUpEndsTheHold() async throws {
        let (library, source) = try await open()
        let plan = try rename(library)
        _ = await library.editField(plan)
        let caughtUp = catalogue().applying(plan)
        source.send(.catalogue(caughtUp))
        // Another app renames it again.
        let plan2 = try #require(caughtUp.itemTypes[entry]).plan(.rename(key: "shelf", label: "Spot"), in: caughtUp)
        source.send(.catalogue(caughtUp.applying(plan2)))
        #expect(await eventually { library.catalogue.label(ofField: "shelf", for: entry) == "Spot" })
    }
}
