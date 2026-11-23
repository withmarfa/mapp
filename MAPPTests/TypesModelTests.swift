import Foundation
import Marfa
import MarfaAPI
import Synchronization
import Testing
@testable import MAPP

/// A server that lists types and takes a change, with every call scripted.
final class FakeTypeCalls: TypeCalls, @unchecked Sendable {
    struct State {
        var types: [TypeRecord] = []
        var readings: [String: TypeReading] = [:]
        var changes: [(type: String, edit: TypeEdit)] = []
        var children: [(id: String, label: String, parent: String)] = []
        var refusal: TypeFailure?
    }

    let state = Mutex(State())

    func types() async throws(TypeFailure) -> TypeListing { TypeListing(types: state.withLock { $0.types }, pluginTitles: ["tickets": "Tickets"]) }

    func reading(of type: String) async throws(TypeFailure) -> TypeReading {
        state.withLock { $0.readings[type] } ?? TypeReading(guidance: nil, ancestors: [])
    }

    func change(_ type: String, _ edit: TypeEdit) async throws(TypeFailure) {
        if let refusal = state.withLock({ $0.refusal }) { throw refusal }
        state.withLock { $0.changes.append((type, edit)) }
    }

    func addChild(id: String, label: String, below parent: String) async throws(TypeFailure) {
        if let refusal = state.withLock({ $0.refusal }) { throw refusal }
        state.withLock {
            $0.children.append((id, label, parent))
            $0.types.append(TypeRecord(id: id, label: label, parent: parent, origin: .registered, fields: [:]))
        }
    }
}

private func record(
    _ id: String, _ label: String, parent: String? = nil, origin: TypeOrigin = .registered, plural: String? = nil,
    words: [StatusWordRecord] = []
) -> TypeRecord {
    var fields: [String: TypeFieldRecord] = [:]
    if !words.isEmpty {
        fields["status"] = TypeFieldRecord(
            key: "status", label: nil, kind: "status", meaning: nil, isRequired: false, isSearchable: true, longest: nil, statusWords: words)
    }
    return TypeRecord(
        id: id, label: label, plural: plural, parent: parent, origin: origin,
        plugin: origin == .plugin ? .init(name: "tickets", version: "1.0") : nil, fields: fields)
}

private func word(_ value: String, _ group: String) -> StatusWordRecord { StatusWordRecord(value: value, group: group) }

@MainActor
@Suite(.hangLimit) struct TypesModelTests {
    private func model(_ calls: FakeTypeCalls, counts: [String: Int] = [:]) -> TypesModel {
        let access = TypeAccess(
            ownItems: { counts[$0] ?? 0 }, currentIcon: { _ in nil }, setIcon: { _, _ in nil },
            markSets: [MarfaMarkSet(id: "lucide", title: "Lucide")], marks: { _, _ in [] }, plural: { _ in nil })
        return TypesModel(context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.schemaWrite] }), calls: calls, access: access)
    }

    private func listing() -> FakeTypeCalls {
        let calls = FakeTypeCalls()
        calls.state.withLock {
            $0.types = [
                record("core.task", "Task", origin: .platform, plural: "Tasks", words: [word("not_started", "not_started"), word("completed", "completed")]),
                record("common.ticket", "Ticket", parent: "core.task", origin: .plugin, words: [word("backlog", "not_started")]),
                record("user.job", "Job", parent: "core.task", plural: "Jobs", words: [word("waiting", "not_started")]),
                record("user.rework", "Rework", parent: "user.job"),
                record("app.mapp.preferences", "MAPP Settings"),
            ]
        }
        return calls
    }

    @Test func theListSplitsTheOwnersTypesFromPluginsAndMarfasAndLeavesOutHiddenOnes() async {
        let model = model(listing())
        await model.load()
        #expect(model.yours.map(\.id) == ["user.job", "user.rework"])
        #expect(model.fromPlugins.map(\.id) == ["common.ticket"])
        #expect(model.builtIn.map(\.id) == ["core.task"])
        #expect(model.record("app.mapp.preferences") == nil)
    }

    @Test func aTypesCountIsItsOwnItemsAndThoseBelowIt() async {
        let model = model(listing(), counts: ["user.job": 18, "user.rework": 4, "core.task": 300])
        await model.load()
        #expect(model.count(of: "user.job") == 22)
        #expect(model.count(of: "core.task") == 322)
    }

    @Test func aChildShowsWhatItIsBasedOnAndAParentWhatIsBasedOnIt() async {
        let model = model(listing())
        await model.load()
        #expect(model.subtitle(of: model.record("user.job")!) == "Based on Tasks. With Rework.")
        #expect(model.subtitle(of: model.record("common.ticket")!) == "From Tickets. Based on Tasks.")
    }

    @Test func onlyTheOwnersTypeIsEditable() async {
        let model = model(listing())
        await model.load()
        #expect(model.isEditable(model.record("user.job")!))
        #expect(!model.isEditable(model.record("common.ticket")!))
        #expect(!model.isEditable(model.record("core.task")!))
    }

    @Test func theWordsAParentGivesAreLockedAndTheTypesOwnAreNot() async {
        let model = model(listing())
        await model.load()
        let words = model.words(of: "user.job", in: "not_started")
        #expect(words.map(\.id) == ["not_started", "waiting"])
        #expect(words.map(\.isLocked) == [true, false])
        #expect(model.words(of: "common.ticket", in: "not_started").allSatisfy { $0.isLocked })
        #expect(model.words(of: "user.rework", in: "not_started").map(\.isLocked) == [true, true])
    }

    @Test func aTypedWordIsNamedInLowercaseWithUnderscores() {
        #expect(TypesModel.value(ofTyped: "  On Hold ") == "on_hold")
        #expect(TypesModel.value(ofTyped: "In-Review") == "in_review")
        #expect(TypesModel.title(ofWord: "on_hold") == "On Hold")
    }

    @Test func anEmojiCountsOnceAgainstALimit() {
        #expect(TypesModel.length(of: String(repeating: "😀", count: 200)) == 200)
        #expect(TypesModel.length(of: "😀") == 1)
    }

    @Test func addingAWordSendsItWithItsGroupAndClosesTheField() async {
        let calls = listing()
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.beginWord(in: "in_progress")
        model.wordDraft = "In Review"
        await model.commitWord()
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.addWord(group: "in_progress", value: "in_review")])
        #expect(model.addingGroup == nil)
    }

    @Test func aRefusedWordStaysTypedAndIsToldOnTheWordField() async {
        let calls = listing()
        calls.state.withLock { $0.refusal = .invalid(field: "fields.status.status_values.1.value", message: "A status word starts with a letter.") }
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.beginWord(in: "in_progress")
        model.wordDraft = "2nd Fitting"
        await model.commitWord()
        #expect(model.wordDraft == "2nd Fitting")
        #expect(model.addingGroup == "in_progress")
        #expect(model.fieldErrors[.word] == "A status word starts with a letter, then letters, numbers and spaces.")
    }

    @Test func aRefusalNamesTheFieldItIsAbout() {
        #expect(TypesModel.field(named: "description") == .description)
        #expect(TypesModel.field(named: "label") == .name)
        #expect(TypesModel.field(named: "fields.status.status_values.0.description") == .meaning)
        #expect(TypesModel.field(named: "fields.status.status_values.0.value") == .word)
        #expect(TypesModel.field(named: nil) == nil)
    }

    @Test func aDescriptionTheServerRefusesIsKeptAndToldOnItsOwnField() async {
        let calls = listing()
        calls.state.withLock { $0.refusal = .invalid(field: "description", message: "Expected a string of at most 200 characters.") }
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.descriptionText = String(repeating: "x", count: 201)
        await model.commit(.description)
        #expect(model.descriptionText.count == 201)
        #expect(model.fieldErrors[.description] == "A description can be 200 characters at most.")
        #expect(model.fieldErrors[.name] == nil)
    }

    @Test func aTypeOpenedBeforeTheTypesAreReadShowsWhatTheServerHoldsOnceTheyAre() async {
        let calls = listing()
        calls.state.withLock { $0.types[2].description = "Kitchens and joinery for clients." }
        let model = model(calls)
        model.open("user.job")
        #expect(model.name.isEmpty)
        await model.load()
        #expect(model.name == "Job")
        #expect(model.plural == "Jobs")
        #expect(model.descriptionText == "Kitchens and joinery for clients.")
    }

    @Test func aDescriptionLeftAloneSendsNothing() async {
        let calls = listing()
        let model = model(calls)
        await model.load()
        model.open("user.job")
        await model.commit(.description)
        await model.commit(.name)
        #expect(calls.state.withLock { $0.changes.isEmpty })
    }

    @Test func aPluginsTypeTakesNoEdit() async {
        let calls = listing()
        let model = model(calls)
        await model.load()
        model.open("common.ticket")
        model.descriptionText = "Changed"
        await model.commit(.description)
        #expect(calls.state.withLock { $0.changes.isEmpty })
    }

    @Test func aChildTypeGetsAUserIdentifierBelowItsParentThatNoTypeHolds() async {
        let calls = listing()
        let model = model(calls)
        await model.load()
        model.beginChild(of: "common.ticket")
        model.childName = "Job"
        #expect(model.identifier(forNamed: "Job") == "user.job_2")
        model.childName = "Café Hours"
        await model.makeChild()
        #expect(calls.state.withLock { $0.children.map(\.id) } == ["user.cafe_hours"])
        #expect(calls.state.withLock { $0.children.map(\.parent) } == ["common.ticket"])
        #expect(model.made == "user.cafe_hours")
        #expect(model.identifier(forNamed: "2nd Fitting") == "user.type_2nd_fitting")
    }

    @Test func aTypeCannotBeBasedOnItselfOrAnythingBelowIt() async {
        let model = model(listing())
        await model.load()
        #expect(model.basedOnChoices(for: "user.job").map(\.id) == ["core.task", "common.ticket"])
    }

    @Test func aNameTypedInTheNewTypeSheetIsHandedBackWhenSettingsCloses() async {
        let model = model(listing())
        await model.load()
        model.beginChild(of: "core.task")
        model.childName = "Fittings"
        #expect(model.takeDrafts() == [.typed(title: "Type Name Not Kept", text: "Fittings")])
        #expect(!model.isMakingChild)
    }
}

/// What a type's replacement sends: the type as the server holds it, with the one change made.
@Suite struct TypeReplacementTests {
    private typealias Definition = Components.Schemas.FieldDefinition
    private typealias Word = Components.Schemas.StatusValue

    private func listed(
        _ id: String, parent: String? = nil, guidance: String? = nil, fields: [String: Definition] = [:], origin: Components.Schemas.TypeProvenance.OriginPayload = .registered
    ) -> TypeDefinitionEdit.Listed {
        let definition = Components.Schemas.TypeDefinition(
            id: id, label: "Job", plural: "Jobs", description: "Kitchens", guidance: guidance, parent: parent,
            fields: .init(additionalProperties: fields), tables: .init(additionalProperties: [:]), version: 3)
        return .init(value1: definition, value2: .init(provenance: .init(origin: origin), ownRoles: []))
    }

    private let task = TypeDefinitionEdit.Listed(
        value1: .init(
            id: "core.task", label: "Task", fields: .init(additionalProperties: [
                "status": Definition(_type: .status, statusValues: [Word(value: "not_started", group: .notStarted)])
            ]), version: 0),
        value2: .init(provenance: .init(origin: .platform), ownRoles: []))

    @Test func aChangeSendsTheGuidanceBackAsItWas() throws {
        let job = listed("user.job", parent: "core.task", guidance: "One job is one piece of paid work.")
        let update = try TypeDefinitionEdit.update(job, applying: .description("Kitchens and joinery"), in: [job, task])
        #expect(update.guidance == "One job is one piece of paid work.")
        #expect(update.description == "Kitchens and joinery")
        #expect(update.label == "Job" && update.plural == "Jobs" && update.parent == "core.task" && update.version == 3)
    }

    @Test func aFieldEditSendsTheGuidanceBackToo() throws {
        let job = listed(
            "user.job", guidance: "Keep it short.", fields: ["site": Definition(_type: .string, label: "Site")])
        let shown = ItemTypeInfo.Field(key: "site", label: "Site", kind: .text, declaredBy: TypeID("user.job"))
        let plan = FieldEditPlan(type: TypeID("user.job"), edit: .rename(key: "site", label: "Place"), shown: shown)
        #expect(try TypeDefinitionEdit.update(job, for: plan).guidance == "Keep it short.")
    }

    @Test func aWordIsAddedToTheTypesOwnStatusField() throws {
        let job = listed("user.job", parent: "core.task", fields: ["status": Definition(_type: .status, statusValues: [Word(value: "waiting", group: .notStarted)])])
        let update = try TypeDefinitionEdit.update(job, applying: .addWord(group: "in_progress", value: "in_review"), in: [job, task])
        #expect(update.fields.additionalProperties["status"]?.statusValues?.map(\.value) == ["waiting", "in_review"])
        #expect(update.fields.additionalProperties["status"]?.statusValues?.last?.group == .inProgress)
    }

    @Test func aChildThatDeclaresNoStatusRedeclaresTheParentsWithOnlyTheNewWord() throws {
        let job = listed("user.job", parent: "core.task")
        let update = try TypeDefinitionEdit.update(job, applying: .addWord(group: "not_started", value: "on_hold"), in: [job, task])
        #expect(update.fields.additionalProperties["status"]?._type == .status)
        #expect(update.fields.additionalProperties["status"]?.statusValues?.map(\.value) == ["on_hold"])
    }

    @Test func aTypeWithNoStatusFieldAboveItCannotTakeAWord() {
        let job = listed("user.job")
        #expect(throws: TypeSchemaFailure.changedOnServer) {
            try TypeDefinitionEdit.update(job, applying: .addWord(group: "not_started", value: "on_hold"), in: [job])
        }
    }

    @Test func aWordsMeaningIsSetAndAnEmptyOneLeavesItOut() throws {
        let job = listed("user.job", fields: ["status": Definition(_type: .status, statusValues: [Word(value: "waiting", group: .notStarted, description: "Old")])])
        let set = try TypeDefinitionEdit.update(job, applying: .wordMeaning(value: "waiting", text: "Parts ordered."), in: [job])
        #expect(set.fields.additionalProperties["status"]?.statusValues?.first?.description == "Parts ordered.")
        let cleared = try TypeDefinitionEdit.update(job, applying: .wordMeaning(value: "waiting", text: ""), in: [job])
        #expect(cleared.fields.additionalProperties["status"]?.statusValues?.first?.description == nil)
    }

    @Test func aPluginsTypeIsNeverReplaced() async {
        var replaced = 0
        let ticket = listed("common.ticket", origin: .plugin)
        await #expect(throws: TypeSchemaFailure.pluginType) {
            try await TypeDefinitionEdit.run(.description("x"), to: "common.ticket", read: { [ticket] }, replace: { _ in replaced += 1 })
        }
        #expect(replaced == 0)
    }
}

/// How the server's refusals of a type's replacement are read.
@Suite struct TypeRefusalTests {
    private func answer(_ json: String, status: UInt16 = 400, code: String) throws -> ServerAnswer {
        ServerAnswer(status: status, code: code, details: try JSONValue(json: json), requestId: nil)
    }

    @Test func aRefusalNamesItsFieldFromTheServersAnswerNotFromTheErrorsOwnDetails() throws {
        let server = try answer(#"{"errors":[{"field":"fields.status.status_values.1.value","message":"Expected a word."}]}"#, code: "invalid_schema")
        let error = MarfaError.validation(code: "invalid_schema", message: "Invalid type schema", details: nil, server: server)
        #expect(ServerTypeCalls.failure(error) == .invalid(field: "fields.status.status_values.1.value", message: "Expected a word."))
    }

    @Test func aRefusalForGuidanceAnAppMadeIsToldApartFromOneForAMissingPermission() throws {
        let server = try answer(#"{"changes":["guidance"],"required_scope":"schema.write"}"#, status: 403, code: "forbidden")
        let error = MarfaError.forbidden(code: "forbidden", message: "Forbidden", server: server)
        #expect(ServerTypeCalls.failure(error) == .guidanceByApp)
    }

    @Test func aRefusalForAMissingPermissionNamesIt() throws {
        let server = try answer(#"{"required_scope":"schema.write"}"#, status: 403, code: "forbidden")
        let error = MarfaError.forbidden(code: "forbidden", message: "Forbidden", server: server)
        #expect(ServerTypeCalls.failure(error) == .owner(.notPermitted("schema.write")))
    }
}
