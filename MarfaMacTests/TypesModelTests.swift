import Foundation
import Marfa
import MarfaAPI
import Synchronization
import Testing
@testable import MarfaMac

/// Holds a call until the test lets it go.
actor TypeCallGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// The drafts a model hands over after Settings has closed.
final class LateDrafts: Sendable {
    let drafts = Mutex<[OwnerDraft]>([])
}

/// A server that lists types and takes a change, with every call scripted.
final class FakeTypeCalls: TypeCalls, @unchecked Sendable {
    struct State {
        var types: [TypeRecord] = []
        /// Each plugin's title, by its name. The Tickets plugin is the one the older tests install.
        var pluginTitles: [String: String] = ["tickets": "Tickets"]
        var readings: [String: TypeReading] = [:]
        var changes: [(type: String, edit: TypeEdit)] = []
        var made: [NewTypeRecord] = []
        var started: [TypeEdit] = []
        var deleted: [(type: String, force: Bool)] = []
        var moves: [(type: String, target: String)] = []
        var preview = TypeMovePreview(items: 0, settings: [])
        var moveResult = TypeMoveResult(remaining: 0, remainingHidden: false)
        var refusal: TypeFailure?
        /// A refusal of the type list itself, as a server that does not answer or a sign-in that may not read it.
        var typesFailure: TypeFailure?
        var deleteRefusal: TypeFailure?
        var gate: TypeCallGate?
        /// A refusal of the move's preview, as the server answers a move a setting stops.
        var previewRefusal: TypeFailure?
    }

    let state = Mutex(State())

    func types() async throws(TypeFailure) -> TypeListing {
        let snapshot = state.withLock { (failure: $0.typesFailure, types: $0.types, pluginTitles: $0.pluginTitles) }
        if let failure = snapshot.failure { throw failure }
        return TypeListing(types: snapshot.types, pluginTitles: snapshot.pluginTitles)
    }

    func reading(of type: String) async throws(TypeFailure) -> TypeReading {
        state.withLock { $0.readings[type] } ?? TypeReading(guidance: nil, ancestors: [])
    }

    func change(_ type: String, _ edit: TypeEdit) async throws(TypeFailure) {
        state.withLock { $0.started.append(edit) }
        if let gate = state.withLock({ $0.gate }) { await gate.wait() }
        if let refusal = state.withLock({ $0.refusal }) { throw refusal }
        // Like the server's replacement: a change the type already holds sends nothing, and the rest is made on the type as it is now.
        state.withLock { state in
            guard let index = state.types.firstIndex(where: { $0.id == type }) else { return }
            var record = state.types[index]
            switch edit {
            case .label(let text):
                guard record.label != text else { return }
                record.label = text
            case .plural(let text):
                guard record.plural != (text.isEmpty ? nil : text) else { return }
                record.plural = text.isEmpty ? nil : text
            case .description(let text):
                guard record.description != (text.isEmpty ? nil : text) else { return }
                record.description = text.isEmpty ? nil : text
            case .guidance(let text):
                guard record.guidance != (text.isEmpty ? nil : text) else { return }
                record.guidance = text.isEmpty ? nil : text
            case .parent(let parent):
                guard record.parent != parent else { return }
                record.parent = parent
            case .addWord(let group, let value):
                let held = record.fields.values.flatMap(\.statusWords).contains { $0.value == value && $0.group == group }
                guard !held, let key = record.fields.first(where: { $0.value.kind == "status" })?.key else { return }
                record.fields[key]?.statusWords.append(StatusWordRecord(value: value, group: group))
            case .field(let key, .addChoice(let word)):
                guard var field = record.fields[key], !field.choices.contains(word) else { return }
                field.choices.append(word)
                record.fields[key] = field
            case .field(let key, .removeChoice(let word)):
                guard var field = record.fields[key], field.choices.contains(word), field.choices.count > 1 else { return }
                field.choices.removeAll { $0 == word }
                record.fields[key] = field
            case .versionWindow(let days):
                record.versionWindow = days.map(VersionWindow.days)
            default:
                break
            }
            state.types[index] = record
            state.changes.append((type, edit))
        }
    }

    func delete(_ type: String, force: Bool) async throws(TypeFailure) {
        if !force, let refusal = state.withLock({ $0.deleteRefusal }) { throw refusal }
        state.withLock {
            $0.deleted.append((type, force))
            $0.types.removeAll { $0.id == type }
        }
    }

    func addType(_ type: NewTypeRecord) async throws(TypeFailure) {
        if let refusal = state.withLock({ $0.refusal }) { throw refusal }
        state.withLock {
            $0.made.append(type)
            $0.types.append(
                TypeRecord(id: type.id, label: type.label, plural: type.plural.isEmpty ? nil : type.plural, parent: type.parent, origin: .registered, icon: type.icon, fields: [:]))
        }
    }

    func previewMove(of type: String, to target: String) async throws(TypeFailure) -> TypeMovePreview {
        if let refusal = state.withLock({ $0.previewRefusal }) { throw refusal }
        return state.withLock { $0.preview }
    }

    func move(_ type: String, to target: String) async throws(TypeFailure) -> TypeMoveResult {
        state.withLock { state in
            state.moves.append((type, target))
            if state.moveResult.isDone { state.deleteRefusal = nil }
            return state.moveResult
        }
    }

}

private func record(
    _ id: String, _ label: String, parent: String? = nil, origin: MarfaMac.TypeOrigin = .registered, plural: String? = nil,
    words: [StatusWordRecord] = [], creator: TypeCreator? = nil
) -> TypeRecord {
    var fields: [String: TypeFieldRecord] = [:]
    if !words.isEmpty {
        fields["status"] = TypeFieldRecord(
            key: "status", label: nil, kind: "status", meaning: nil, isRequired: false, isSearchable: true, longest: nil, statusWords: words)
    }
    return TypeRecord(
        id: id, label: label, plural: plural, parent: parent, origin: origin,
        plugin: origin == .plugin ? .init(name: "tickets", version: "1.0") : nil, creator: creator, fields: fields)
}

private func word(_ value: String, _ group: String) -> StatusWordRecord { StatusWordRecord(value: value, group: group) }

@MainActor
@Suite(.hangLimit) struct TypesModelTests {
    private func model(
        _ calls: FakeTypeCalls, counts: [String: Int] = [:], late: LateDrafts = LateDrafts(),
        grants: Set<InstancePermission> = [.schemaWrite], holds: @escaping (String) -> Bool = { $0 == "*:write" },
        owner: FakeOwnerCalls = FakeOwnerCalls(),
        setIcon: @escaping (String?, String) async -> OwnerFailure? = { _, _ in nil }, ownVendor: String? = "app.marfa-mac"
    ) -> TypesModel {
        let access = TypeAccess(
            ownItems: { counts[$0] ?? 0 }, currentIcon: { _ in nil }, setIcon: setIcon,
            markSets: [MarfaMarkSet(id: "lucide", title: "Lucide")], marks: { _, _ in [] }, plural: { _ in nil })
        let context = OwnerContext(
            calls: owner, grants: { grants }, holds: holds, lateDraft: { draft in late.drafts.withLock { $0.append(draft) } })
        return TypesModel(context: context, calls: calls, access: access, ownVendor: ownVendor)
    }

    private func listing() -> FakeTypeCalls {
        let calls = FakeTypeCalls()
        calls.state.withLock {
            $0.types = [
                record("core.task", "Task", origin: .platform, plural: "Tasks", words: [word("not_started", "not_started"), word("completed", "completed")]),
                record("common.ticket", "Ticket", parent: "core.task", origin: .plugin, words: [word("backlog", "not_started")]),
                record("user.job", "Job", parent: "core.task", plural: "Jobs", words: [word("waiting", "not_started")]),
                record("user.rework", "Rework", parent: "user.job"),
                record("app.marfa-mac.preferences", "Marfa for Mac Settings"),
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
        #expect(model.record("app.marfa-mac.preferences") == nil)
        #expect(!model.showsFromApps)
        #expect(model.count(in: .all) == 4)
        #expect(model.count(in: .yours) == 2)
        #expect(model.count(in: .builtIn) == 1)
        #expect(model.count(in: .fromPlugins) == 1)
        #expect(model.count(in: .fromApps) == 0)
    }

    @Test func anAppNamespaceIsFromAppsAndARegisteredUserTypeStaysYours() async {
        let calls = listing()
        calls.state.withLock {
            $0.types.append(record(
                "app.raycast.snippets", "Snippet", origin: .registered, plural: "Snippets",
                creator: TypeCreator(kind: .app, id: "raycast", name: "Raycast")))
            $0.types.append(record(
                "user.capture", "Capture", creator: TypeCreator(kind: .app, id: "raycast", name: "Raycast")))
            $0.types.append(record("app.raycast", "Raycast"))
            $0.types.append(record("publisher.widget", "Widget"))
        }
        let model = model(calls)
        await model.load()
        #expect(model.fromApps.map(\.id) == ["app.raycast.snippets"])
        #expect(model.showsFromApps)
        #expect(!model.fromApps.map(\.id).contains("app.raycast"))
        #expect(!model.yours.map(\.id).contains("publisher.widget"))
        #expect(!model.yours.map(\.id).contains("app.raycast"))
        #expect(model.rows(in: .all, sortedBy: .type(ascending: true)).map(\.id).contains("publisher.widget"))
        #expect(model.yours.map(\.id).contains("user.capture"))
        #expect(model.sourceTitle(of: model.record("app.raycast.snippets")!) == "Raycast")
        #expect(model.sourceTitle(of: model.record("user.job")!) == "You")
        #expect(model.sourceTitle(of: model.record("core.task")!) == "Marfa")
        #expect(model.sourceTitle(of: model.record("common.ticket")!) == "Tickets")
        #expect(!model.isEditable(model.record("app.raycast.snippets")!))
    }

    @Test func anUnknownOriginIsListedOnlyUnderAll() async {
        let calls = listing()
        calls.state.withLock {
            $0.types.append(record("core.note", "Note", origin: .unknown, plural: "Notes"))
            $0.types.append(record("user.lost", "Lost", origin: .unknown))
            $0.types.append(record("user.shipped", "Shipped", origin: .platform))
        }
        let model = model(calls)
        await model.load()
        #expect(!model.yours.map(\.id).contains("core.note"))
        #expect(!model.builtIn.map(\.id).contains("core.note"))
        #expect(model.yours.map(\.id).contains("user.lost"))
        #expect(model.builtIn.map(\.id).contains("user.shipped"))
        #expect(!model.yours.map(\.id).contains("user.shipped"))
        #expect(model.rows(in: .all, sortedBy: .type(ascending: true)).map(\.id).contains("core.note"))
        #expect(model.sourceTitle(of: model.record("core.note")!) == "Unknown")
        #expect(!model.isEditable(model.record("core.note")!))
        #expect(!model.isEditable(model.record("user.lost")!))
        #expect(model.count(in: .all) == model.count(in: .yours) + model.count(in: .builtIn) + model.count(in: .fromPlugins) + 1)
    }

    @Test func aMissingAppNameFallsBackToTheVendorInTheId() async {
        let calls = FakeTypeCalls()
        calls.state.withLock { $0.types = [record("app.raycast.snippets", "Snippet", origin: .registered)] }
        let model = model(calls)
        await model.load()
        #expect(model.sourceTitle(of: model.record("app.raycast.snippets")!) == "Raycast")
    }

    @Test func switchingTabsKeepsATypeOnlyWhileTheTabStillListsIt() async {
        let model = model(listing())
        await model.load()
        let builtIn = model.rows(in: .builtIn, sortedBy: .type(ascending: true))
        #expect(model.keptSelection("core.task", in: builtIn) == "core.task")
        #expect(model.keptSelection("user.job", in: builtIn) == nil)
        let plugins = model.rows(in: .fromPlugins, sortedBy: .type(ascending: true))
        #expect(plugins.map(\.depth) == [0], "a parent outside the tab leaves the type as a root")
        #expect(plugins.map(\.id) == ["common.ticket"])
    }

    @Test func theTypeColumnKeepsChildrenUnderParentsAndALongNameStaysWhole() async {
        let calls = listing()
        let long = String(repeating: "Extraordinary ", count: 12) + "Specification"
        calls.state.withLock { $0.types.append(record("user.specification", long, parent: "user.job")) }
        let model = model(calls)
        await model.load()
        let rows = model.rows(in: .all, sortedBy: .type(ascending: true))
        #expect(rows.map(\.id) == ["core.task", "user.job", "user.specification", "user.rework", "common.ticket"])
        #expect(rows.map(\.depth) == [0, 1, 2, 2, 1])
        #expect(model.title(of: "user.specification") == long)
        #expect(model.rows(in: .yours, sortedBy: .type(ascending: false)).map(\.id) == ["user.job", "user.rework", "user.specification"])
    }

    @Test func theServerNotAnsweringAndAMissingPermissionLeaveTheListUnread() async {
        let silent = FakeTypeCalls()
        silent.state.withLock { $0.typesFailure = .owner(.unreachable) }
        let unanswered = model(silent)
        await unanswered.load()
        #expect(unanswered.failure == .unreachable)
        #expect(unanswered.records.isEmpty)

        let refused = FakeTypeCalls()
        refused.state.withLock { $0.typesFailure = .owner(.notPermitted("schema.write")) }
        let blocked = model(refused, grants: [])
        await blocked.load()
        #expect(blocked.failure == .notPermitted("schema.write"))
    }

    @Test func aTypesCountIsItsOwnItems() async {
        let model = model(listing(), counts: ["user.job": 18, "user.rework": 4, "core.task": 300])
        await model.load()
        #expect(model.count(of: "user.job") == 18)
        #expect(model.count(of: "user.rework") == 4)
        #expect(model.count(of: "core.task") == 300)
    }

    @Test func itemsSortUsesATypesOwnCount() async {
        let calls = listing()
        calls.state.withLock {
            $0.types.append(record("core.bookmark", "Bookmark", origin: .platform, plural: "Bookmarks"))
            $0.types.append(record("rss.entry", "RSS Entry", parent: "core.bookmark", origin: .plugin, plural: "RSS Entries"))
        }
        let model = model(calls, counts: ["core.bookmark": 17, "rss.entry": 151, "user.job": 4, "user.rework": 18, "core.task": 1])
        await model.load()
        let ids = model.rows(in: .all, sortedBy: .items(ascending: true)).map(\.id)
        #expect(ids.firstIndex(of: "core.bookmark")! < ids.firstIndex(of: "rss.entry")!)
        #expect(ids.firstIndex(of: "user.job")! < ids.firstIndex(of: "user.rework")!)
    }

    @Test func aChildShowsWhatItIsBasedOnAndAParentWhatIsBasedOnIt() async {
        let model = model(listing())
        await model.load()
        #expect(model.subtitle(of: model.record("user.job")!) == "Based on Tasks. With Rework.")
        #expect(model.subtitle(of: model.record("common.ticket")!) == "From Tickets. Based on Tasks.")
    }

    @Test func aRegisteredTypeIsEditableOnlyWithSchemaWriteAndWriteAccess() async {
        let calls = listing()
        calls.state.withLock {
            $0.types.append(record("publisher.widget", "Widget"))
            $0.types.append(record(
                "app.raycast.snippets", "Snippet", creator: TypeCreator(kind: .app, id: "raycast", name: "Raycast")))
        }
        let writable = model(calls)
        await writable.load()
        #expect(writable.isEditable(writable.record("user.job")!))
        #expect(writable.isEditable(writable.record("publisher.widget")!))
        #expect(!writable.yours.map(\.id).contains("publisher.widget"))
        #expect(!writable.isEditable(writable.record("app.raycast.snippets")!))
        #expect(!writable.isEditable(writable.record("common.ticket")!))
        #expect(!writable.isEditable(writable.record("core.task")!))

        let noGrant = model(calls, grants: [])
        await noGrant.load()
        #expect(!noGrant.isEditable(noGrant.record("user.job")!))

        let noWrite = model(calls, holds: { _ in false })
        await noWrite.load()
        #expect(!noWrite.isEditable(noWrite.record("user.job")!))

        let appWrite = model(calls, holds: { $0 == "app.raycast.*:write" })
        await appWrite.load()
        #expect(appWrite.isEditable(appWrite.record("app.raycast.snippets")!))
        #expect(!appWrite.isEditable(appWrite.record("user.job")!))

        let exact = model(calls, holds: { $0 == "app.raycast.snippets:write" })
        await exact.load()
        #expect(exact.isEditable(exact.record("app.raycast.snippets")!))

        let content = model(calls, holds: { $0 == "content:write" })
        await content.load()
        #expect(content.isEditable(content.record("user.job")!))
        #expect(content.isEditable(content.record("publisher.widget")!))
        #expect(!content.isEditable(content.record("app.raycast.snippets")!))
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
        #expect(model.fieldErrors[.word] == "A status word starts with a letter.")
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
        #expect(calls.state.withLock { $0.made.map(\.id) } == ["user.cafe_hours"])
        #expect(calls.state.withLock { $0.made.map(\.parent) } == ["common.ticket"])
        #expect(model.made == "user.cafe_hours")
        #expect(model.identifier(forNamed: "2nd Fitting") == "user.type_2nd_fitting")
    }

    @Test func aTypeCannotBeBasedOnItselfOrAnythingBelowIt() async {
        let model = model(listing())
        await model.load()
        #expect(model.basedOnChoices(for: "user.job").map(\.id) == ["core.task", "common.ticket"])
    }

    @Test func changesRunOneAtATimeSoALaterOneIsBuiltFromTheTypeTheEarlierOneLeft() async {
        let calls = listing()
        let gate = TypeCallGate()
        calls.state.withLock { $0.gate = gate }
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.descriptionText = "Kitchens and joinery"
        let description = Task { await model.commit(.description) }
        #expect(await eventually { calls.state.withLock { $0.started.count } == 1 })
        let parent = Task { await model.setParent("common.ticket", of: "user.job") }
        model.plural = "Fittings"
        let plural = Task { await model.commit(.plural) }
        // The first call has not landed, so the others have not started.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(calls.state.withLock { $0.started } == [.description("Kitchens and joinery")])
        await gate.open()
        await description.value
        await parent.value
        await plural.value
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.description("Kitchens and joinery"), .parent("common.ticket"), .plural("Fittings")])
    }

    @Test func aPluralCommittedDuringANameSaveIsStillSent() async {
        let calls = listing()
        let gate = TypeCallGate()
        calls.state.withLock { $0.gate = gate }
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.name = "Piece of Work"
        let name = Task { await model.commit(.name) }
        #expect(await eventually { calls.state.withLock { $0.started.count } == 1 })
        model.plural = "Pieces of Work"
        let plural = Task { await model.commit(.plural) }
        await gate.open()
        await name.value
        await plural.value
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.label("Piece of Work"), .plural("Pieces of Work")])
    }

    @Test func aNameAPluralAndAMeaningTypedAndNotKeptAreHandedBackWhenSettingsCloses() async {
        let model = model(listing())
        await model.load()
        model.open("user.job")
        model.name = "Piece of Work"
        model.plural = "Pieces of Work"
        model.beginMeaning(of: "waiting", in: "user.job")
        model.meaningDraft = "Parts ordered."
        #expect(model.takeDrafts() == [
            .typed(title: "Type Name Change Not Kept", text: "Piece of Work"), .typed(title: "Type Plural Not Kept", text: "Pieces of Work"),
            .typed(title: "Word Meaning Not Kept", text: "Parts ordered."),
        ])
        #expect(model.name == "Job" && model.plural == "Jobs" && model.meaningWord == nil)
    }

    @Test func aWordCommittedByReturnAndAgainByLeavingTheFieldIsAddedOnceWithNoRefusal() async {
        let calls = listing()
        calls.state.withLock { $0.gate = TypeCallGate() }
        let gate = calls.state.withLock { $0.gate! }
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.beginWord(in: "in_progress")
        model.wordDraft = "In Review"
        let returned = Task { await model.commitWord() }
        #expect(await eventually { calls.state.withLock { $0.started.count } == 1 })
        let left = Task { await model.commitWord() }
        await gate.open()
        await returned.value
        await left.value
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.addWord(group: "in_progress", value: "in_review")])
        #expect(model.fieldErrors[.word] == nil)
        #expect(model.addingGroup == nil && model.wordDraft.isEmpty)
    }

    @Test func aNameChangedAndChangedBackWhileTheFirstIsSavingIsSentBackToo() async {
        let calls = listing()
        let gate = TypeCallGate()
        calls.state.withLock { $0.gate = gate }
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.name = "Piece of Work"
        let first = Task { await model.commit(.name) }
        #expect(await eventually { calls.state.withLock { $0.started.count } == 1 })
        model.name = "Job"
        let back = Task { await model.commit(.name) }
        await gate.open()
        await first.value
        await back.value
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.label("Piece of Work"), .label("Job")])
        #expect(model.record("user.job")?.label == "Job")
    }

    @Test func aParentChosenAndChosenBackWhileTheFirstIsSavingIsSentBackToo() async {
        let calls = listing()
        let gate = TypeCallGate()
        calls.state.withLock { $0.gate = gate }
        let model = model(calls)
        await model.load()
        model.open("user.job")
        let first = Task { await model.setParent("common.ticket", of: "user.job") }
        #expect(await eventually { calls.state.withLock { $0.started.count } == 1 })
        let back = Task { await model.setParent("core.task", of: "user.job") }
        await gate.open()
        await first.value
        await back.value
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.parent("common.ticket"), .parent("core.task")])
        #expect(model.record("user.job")?.parent == "core.task")
    }

    @Test func anIconChosenWhileAChangeIsSavingWaitsForIt() async {
        let calls = listing()
        let gate = TypeCallGate()
        calls.state.withLock { $0.gate = gate }
        let order = Mutex<[String]>([])
        let model = model(calls, setIcon: { _, _ in
            order.withLock { $0.append("icon after \(calls.state.withLock { $0.changes.count }) changes") }
            return nil
        })
        await model.load()
        model.open("user.job")
        model.descriptionText = "Kitchens"
        let description = Task { await model.commit(.description) }
        #expect(await eventually { calls.state.withLock { $0.started.count } == 1 })
        model.beginIcon(of: "user.job")
        let icon = Task { await model.chooseIcon("lucide:hammer") }
        // Nothing to wait for: gives the icon change time to run ahead of the description's save, if it is going to.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(order.withLock { $0 }.isEmpty)
        await gate.open()
        await description.value
        await icon.value
        #expect(order.withLock { $0 } == ["icon after 1 changes"])
        #expect(model.iconTarget == nil)
    }

    @Test func aChangeStillSavingWhenSettingsClosesIsNotHandedBackIfItLands() async {
        let calls = listing()
        let gate = TypeCallGate()
        calls.state.withLock { $0.gate = gate }
        let late = LateDrafts()
        let model = model(calls, late: late)
        await model.load()
        model.open("user.job")
        model.name = "Piece of Work"
        let saving = Task { await model.commit(.name) }
        #expect(await eventually { calls.state.withLock { $0.started.count } == 1 })
        #expect(model.takeDrafts().isEmpty)
        await gate.open()
        await saving.value
        #expect(late.drafts.withLock { $0 }.isEmpty)
    }

    @Test func aMeaningStillSavingWhenSettingsClosesIsHandedBackIfTheServerRefusesIt() async {
        let calls = listing()
        let gate = TypeCallGate()
        calls.state.withLock { $0.gate = gate }
        let late = LateDrafts()
        let model = model(calls, late: late)
        await model.load()
        model.open("user.job")
        model.beginMeaning(of: "waiting", in: "user.job")
        model.meaningDraft = "Parts ordered."
        let saving = Task { await model.saveMeaning() }
        #expect(await eventually { calls.state.withLock { $0.started.count } == 1 })
        #expect(model.takeDrafts().isEmpty)
        calls.state.withLock { $0.refusal = .invalid(field: "fields.status.status_values.0.description", message: "Too long.") }
        await gate.open()
        await saving.value
        #expect(late.drafts.withLock { $0 } == [.typed(title: "Word Meaning Not Kept", text: "Parts ordered.")])
    }

    @Test func aRefusalShowsTheServersReasonUnlessItIsTheLengthRule() {
        #expect(TypesModel.isLengthRule("Expected a string of at most 100 characters."))
        #expect(!TypesModel.isLengthRule("Status word \"waiting\" is already used."))
    }

    @Test func aRepeatedWordShowsTheServersReasonOnTheWordField() async {
        let calls = listing()
        calls.state.withLock { $0.refusal = .invalid(field: "fields.status.status_values.1.value", message: "The word waiting is already used.") }
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.beginWord(in: "in_progress")
        model.wordDraft = "Waiting"
        await model.commitWord()
        #expect(model.fieldErrors[.word] == "The word waiting is already used.")
    }

    @Test func aClearedPluralShowsTheOneTheServerNowReadsForTheType() async {
        let calls = listing()
        calls.state.withLock { $0.readings["user.job"] = TypeReading(guidance: nil, plural: "Jobs", ancestors: []) }
        let model = model(calls)
        await model.load()
        calls.state.withLock { $0.types[2].plural = nil; $0.readings["user.job"] = TypeReading(guidance: nil, plural: "Jobs", ancestors: []) }
        model.open("user.job")
        model.plural = ""
        await model.commit(.plural)
        #expect(model.title(of: "user.job") == "Jobs")
    }

    /// Jobs with no type based on it, so it can be deleted.
    private func deletable() -> FakeTypeCalls {
        let calls = withFields()
        calls.state.withLock { $0.types.removeAll { $0.id == "user.rework" } }
        return calls
    }

    private func withFields() -> FakeTypeCalls {
        let calls = listing()
        calls.state.withLock {
            $0.types[2].fields["client"] = TypeFieldRecord(
                key: "client", label: "Client", kind: "string", meaning: "Who the job is for.", isRequired: false, isSearchable: true,
                longest: 200, statusWords: [])
            $0.types[2].fields["kind"] = TypeFieldRecord(
                key: "kind", label: nil, kind: "enum", meaning: nil, isRequired: true, isSearchable: true, longest: nil,
                choices: ["kitchen", "stairs"], statusWords: [])
        }
        return calls
    }

    @Test func aTypesOwnFieldsAreEditableAndWhatAParentGivesIsLocked() async {
        let model = model(withFields())
        await model.load()
        #expect(model.ownFields(of: "user.job").map(\.key) == ["client", "kind"])
        // The status field the job redeclares to add a word is the parent's, so it is not offered as the job's own.
        #expect(model.inheritedFields(of: "user.job").map(\.key) == ["status"])
        #expect(model.ownFields(of: "common.ticket").isEmpty)
        #expect(model.ownFields(of: "core.task").isEmpty)
    }

    @Test func aFieldIsAddedWithANameMadeFromItsLabelThatNoFieldHolds() async {
        let calls = withFields()
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.beginField()
        model.newFieldName = "Client"
        model.newFieldKind = .choice
        model.newFieldChoices = " Gold, Silver ,, Gold"
        #expect(model.typedChoices == ["Gold", "Silver"])
        await model.makeField()
        // A field of that label is there, so nothing is sent and the sheet says so.
        #expect(calls.state.withLock { $0.changes.isEmpty })
        #expect(model.fieldErrors[.newField] != nil)
        model.newFieldName = "Site Address"
        await model.makeField()
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.addField(NewFieldRecord(key: "site_address", label: "Site Address", kind: .choice, choices: ["Gold", "Silver"]))])
        #expect(!model.isAddingField)
    }

    @Test func aChoiceFieldNeedsAChoiceBeforeItCanBeAdded() async {
        let model = model(withFields())
        await model.load()
        model.open("user.job")
        model.beginField()
        model.newFieldName = "Tier"
        model.newFieldKind = .choice
        #expect(!model.canMakeField)
        model.newFieldChoices = "Gold"
        #expect(model.canMakeField)
    }

    @Test func aMeaningOverTheLimitIsKeptAndToldOnTheField() async {
        let calls = withFields()
        calls.state.withLock { $0.refusal = .invalid(field: "fields.client.description", message: "Expected at most 300.") }
        let model = model(calls)
        await model.load()
        model.openField("client", of: "user.job")
        #expect(model.fieldMeaning == "Who the job is for.")
        model.fieldMeaning = String(repeating: "x", count: 301)
        await model.commitFieldMeaning()
        #expect(model.fieldMeaning.count == 301)
        #expect(model.fieldErrors[.fieldMeaning] == "What a field means can be 300 characters at most.")
        #expect(TypesModel.field(named: "fields.client.max_length") == .fieldLongest)
    }

    @Test func aFieldIsRenamedByLabelAndTheRuleSwitchesSendTheirOwnChange() async {
        let calls = withFields()
        let model = model(calls)
        await model.load()
        model.openField("client", of: "user.job")
        model.beginRename()
        model.fieldNameDraft = "Customer"
        await model.commitRename()
        await model.setRequired(true)
        await model.setSearchable(false)
        model.fieldLongest = "80"
        await model.commitLongest()
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [
            .field(key: "client", .label("Customer")), .field(key: "client", .required(true)),
            .field(key: "client", .searchable(false)), .field(key: "client", .longest(80)),
        ])
        #expect(!model.isRenamingField)
    }

    @Test func aLongestThatIsNotAWholeNumberIsRefusedBeforeItIsSent() async {
        let calls = withFields()
        let model = model(calls)
        await model.load()
        model.openField("client", of: "user.job")
        model.fieldLongest = "0"
        await model.commitLongest()
        #expect(model.fieldErrors[.fieldLongest] != nil)
        #expect(calls.state.withLock { $0.changes.isEmpty })
    }

    @Test func aChoiceIsAddedAfterTheOthersAndTheLastCannotBeTakenOut() async {
        let calls = withFields()
        calls.state.withLock { $0.types[2].fields["kind"]?.choices = ["kitchen"] }
        let model = model(calls)
        await model.load()
        model.openField("kind", of: "user.job")
        await model.removeChoice("kitchen")
        #expect(model.fieldErrors[.choice] == "A choice field needs at least one choice.")
        #expect(calls.state.withLock { $0.changes.isEmpty })
        model.beginChoice()
        model.choiceDraft = "garden"
        await model.commitChoice()
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.field(key: "kind", .addChoice("garden"))])
        #expect(model.ownField("kind", of: "user.job")?.choices == ["kitchen", "garden"])
    }

    @Test func aChoiceAddedAndAnotherTakenOutWhileTheFirstIsSavingEachKeepTheOthersEdit() async {
        let calls = withFields()
        let gate = TypeCallGate()
        calls.state.withLock { $0.gate = gate }
        let model = model(calls)
        await model.load()
        model.openField("kind", of: "user.job")
        model.beginChoice()
        model.choiceDraft = "garden"
        let added = Task { await model.commitChoice() }
        #expect(await eventually { calls.state.withLock { $0.started.count } == 1 })
        let removed = Task { await model.removeChoice("kitchen") }
        await gate.open()
        await added.value
        await removed.value
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.field(key: "kind", .addChoice("garden")), .field(key: "kind", .removeChoice("kitchen"))])
        #expect(calls.state.withLock { $0.types[2].fields["kind"]?.choices } == ["stairs", "garden"])
    }

    @Test func aRefusedSearchableAndARefusedRemoveAreToldOnTheirOwnRows() async {
        let calls = withFields()
        calls.state.withLock { $0.refusal = .invalid(field: nil, message: "Not now.") }
        let model = model(calls)
        await model.load()
        model.openField("client", of: "user.job")
        await model.setSearchable(false)
        #expect(model.fieldErrors[.fieldSearchable] == "Not now." && model.fieldErrors[.fieldRule] == nil)
        await model.removeField()
        #expect(model.fieldErrors[.fieldRemove] == "Not now." && model.fieldErrors[.fieldRule] == nil)
        #expect(model.openFieldKey == "client")
    }

    @Test func aRenameALongestAChoiceAndNewFieldChoicesTypedAndNotKeptAreHandedBackWhenSettingsCloses() async {
        let calls = withFields()
        let model = model(calls)
        await model.load()
        model.openField("client", of: "user.job")
        model.beginRename()
        model.fieldNameDraft = "Customer"
        model.fieldLongest = "80"
        model.beginChoice()
        model.choiceDraft = "garden"
        model.beginField()
        model.newFieldChoices = "red, green"
        #expect(model.takeDrafts() == [
            .typed(title: "New Field Choices Not Kept", text: "red, green"), .typed(title: "Field Longest Not Kept", text: "80"),
            .typed(title: "Field Name Change Not Kept", text: "Customer"), .typed(title: "Choice Not Kept", text: "garden"),
        ])
        #expect(!model.isRenamingField && !model.isAddingField && !model.isAddingChoice && model.fieldLongest == "200")
    }

    @Test func aFieldIsOnlyOpenedOnATypeTheOwnerCanChange() async {
        let model = model(listing())
        await model.load()
        model.openField("status", of: "common.ticket")
        #expect(model.ownField("status", of: "common.ticket") == nil)
    }

    @Test func theFeedAndMergeRulesShowTheTypesOwnOrLeaveItToTheTypeAbove() async {
        let calls = withFields()
        calls.state.withLock { $0.types[2].feedWindow = .days(45) }
        let model = model(calls)
        await model.load()
        #expect(model.feedSelection(of: "user.job") == .days(45))
        #expect(model.feedWindows(for: "user.job") == [.never, .days(7), .days(30), .days(45), .days(90), .days(365)])
        #expect(model.feedSelection(of: "user.rework") == nil)
        #expect(model.mergeSelection(of: "user.rework") == nil)
        await model.setFeedWindow(.never, of: "user.job")
        await model.setMergeStrategy("keep_both_copies", of: "user.job")
        await model.setFeedWindow(nil, of: "user.rework")
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.feedWindow(.never), .mergeStrategy("keep_both_copies")])
    }

    @Test func deletingATypeLeavesItsPageAndTellsAServerRefusalInWords() async {
        let calls = withFields()
        let model = model(calls)
        await model.load()
        model.open("user.job")
        // Rework is based on Jobs, so neither way of deleting is offered and the row says why.
        model.beginDelete()
        #expect(!model.isConfirmingDelete)
        #expect(model.deleteFailure == "Types are based on Jobs: Rework. Change or delete those first.")
        calls.state.withLock {
            $0.types.removeAll { $0.id == "user.rework" }
            $0.deleteRefusal = .inUse(items: 2, settings: 1)
        }
        await model.reread()
        await model.deleteType()
        // Something uses it, in the bin or a setting, so the sheet asks what happens to it, and nothing is deleted yet.
        #expect(model.isConfirmingDelete)
        #expect(model.refusedUse?.items == 2)
        #expect(model.deleted == nil)
        #expect(calls.state.withLock { $0.deleted.isEmpty })
        model.cancelDelete()
        calls.state.withLock { $0.deleteRefusal = nil }
        await model.deleteType()
        #expect(model.deleted == "user.job")
        #expect(model.record("user.job") == nil)
        #expect(model.deleteFailure == nil)
    }

    @Test func aPluginsOrBuiltInTypeIsNeverDeleted() async {
        let calls = withFields()
        let model = model(calls)
        await model.load()
        model.open("common.ticket")
        await model.deleteType()
        model.open("core.task")
        await model.deleteType()
        #expect(calls.state.withLock { $0.deleted.isEmpty })
    }

    @Test func aMoveThatLeavesItemsBehindKeepsTheTypeAndSaysWhy() async {
        let calls = deletable()
        calls.state.withLock {
            $0.deleteRefusal = .inUse(items: 18, settings: 0)
            $0.preview = TypeMovePreview(items: 18, settings: [])
            $0.moveResult = TypeMoveResult(moved: 15, failed: 3, remaining: 3, remainingHidden: false)
        }
        let model = model(calls, counts: ["user.job": 18])
        await model.load()
        model.open("user.job")
        model.beginDelete()
        #expect(model.moveTarget == "core.task")
        #expect(await eventually { model.movePreview != nil })
        await model.confirmDelete()
        #expect(calls.state.withLock { $0.moves.map(\.target) } == ["core.task"])
        #expect(calls.state.withLock { $0.deleted.isEmpty })
        #expect(model.deleted == nil)
        #expect(model.isConfirmingDelete)
        #expect(model.deleteSheetFailure == "15 items moved. 3 items couldn’t move, so Jobs was kept.")
    }

    /// A job with any failed item is partial, even where none is left of the type.
    @Test func aMoveWithFailuresAndNothingLeftStillKeepsTheType() async {
        let calls = deletable()
        calls.state.withLock {
            $0.preview = TypeMovePreview(items: 18, settings: [])
            $0.moveResult = TypeMoveResult(moved: 16, failed: 2, remaining: 0, remainingHidden: false)
        }
        let model = model(calls, counts: ["user.job": 18])
        await model.load()
        model.open("user.job")
        model.beginDelete()
        #expect(await eventually { model.movePreview != nil })
        await model.confirmDelete()
        #expect(calls.state.withLock { $0.deleted.isEmpty })
        #expect(model.deleted == nil && model.isConfirmingDelete)
        #expect(model.deleteSheetFailure == "16 items moved. 2 items couldn’t move, so Jobs was kept.")
    }

    @Test func itemsMadeWhileTheMoveRanAreNotToldAsFailures() async {
        let calls = deletable()
        calls.state.withLock {
            $0.preview = TypeMovePreview(items: 18, settings: [])
            $0.moveResult = TypeMoveResult(moved: 18, failed: 0, remaining: 2, remainingHidden: false)
        }
        let model = model(calls, counts: ["user.job": 18])
        await model.load()
        model.open("user.job")
        model.beginDelete()
        #expect(await eventually { model.movePreview != nil })
        await model.confirmDelete()
        #expect(calls.state.withLock { $0.deleted.isEmpty })
        #expect(model.deleteSheetFailure == "18 items moved. Jobs got 2 new items while they moved, so it was kept. Delete again to move them too.")
    }

    /// The server takes no precondition on a move, so the move is previewed again just before it starts: other items with the
    /// same count, or a webhook made since the person agreed, are shown and agreed to before anything moves.
    @Test func aMoveWhosePreviewChangedSinceTheOwnerAgreedAsksAgain() async {
        let calls = deletable()
        calls.state.withLock { $0.preview = TypeMovePreview(items: 2, ids: ["i1", "i2"], settings: []) }
        let model = model(calls, counts: ["user.job": 2])
        await model.load()
        model.open("user.job")
        model.beginDelete()
        #expect(await eventually { model.movePreview != nil })
        calls.state.withLock { $0.preview = TypeMovePreview(items: 2, ids: ["i1", "i3"], settings: []) }
        await model.confirmDelete()
        #expect(calls.state.withLock { $0.moves.isEmpty && $0.deleted.isEmpty })
        #expect(model.movePreview?.ids == ["i1", "i3"])
        let webhook = TypeSettingRecord(kind: .webhook, id: "w1", field: "type_filter")
        calls.state.withLock { $0.preview = TypeMovePreview(items: 2, ids: ["i1", "i3"], settings: [webhook]) }
        await model.confirmDelete()
        #expect(calls.state.withLock { $0.moves.isEmpty && $0.deleted.isEmpty })
        #expect(model.movePreview?.settings == [webhook])
        #expect(model.deleteSheetFailure != nil)
        #expect(model.isConfirmingDelete)
        await model.confirmDelete()
        #expect(calls.state.withLock { $0.moves.count } == 1)
        #expect(model.deleted == "user.job")
    }

    @Test func aTypeIsDeletedUnforcedOnlyOnceItsItemsHaveMoved() async {
        let calls = deletable()
        calls.state.withLock {
            $0.deleteRefusal = .inUse(items: 18, settings: 1)
            $0.preview = TypeMovePreview(items: 18, settings: [TypeSettingRecord(kind: .view, id: "v1")])
        }
        let model = model(calls, counts: ["user.job": 18])
        await model.load()
        model.open("user.job")
        model.beginDelete()
        #expect(await eventually { model.movePreview != nil })
        await model.confirmDelete()
        #expect(calls.state.withLock { $0.moves.count } == 1)
        #expect(calls.state.withLock { $0.deleted.map(\.force) } == [false])
        #expect(model.deleted == "user.job")
        #expect(!model.isConfirmingDelete)
    }

    @Test func leavingTheItemsDeletesTheTypeForcedAndMovesNothing() async {
        let calls = deletable()
        calls.state.withLock { $0.preview = TypeMovePreview(items: 18, settings: []) }
        let model = model(calls, counts: ["user.job": 18])
        await model.load()
        model.open("user.job")
        model.beginDelete()
        model.deleteChoice = .leave
        await model.confirmDelete()
        #expect(calls.state.withLock { $0.moves.isEmpty })
        #expect(calls.state.withLock { $0.deleted.map(\.force) } == [true])
        #expect(model.deleted == "user.job")
    }

    @Test func aSettingAMoveCannotChangeHoldsTheMoveBack() async {
        let calls = deletable()
        // The server refuses the preview itself, naming the setting and why (`types/move-blocked`).
        let folder = TypeSettingRecord(kind: .folder, id: "f1", field: "query.filter", blocked: .filterTerm)
        calls.state.withLock { $0.previewRefusal = .moveBlocked(settings: [folder], tables: []) }
        let model = model(calls, counts: ["user.job": 18])
        await model.load()
        model.open("user.job")
        model.beginDelete()
        #expect(await eventually { model.movePreview != nil })
        #expect(model.blockedSettings == [folder])
        #expect(model.movePreviewFailure == nil)
        #expect(!model.canConfirmDelete)
        await model.confirmDelete()
        #expect(calls.state.withLock { $0.moves.isEmpty && $0.deleted.isEmpty })
    }

    @Test func aNewTypeBasedOnNothingIsSentWithItsPluralAndIcon() async {
        let calls = listing()
        let model = model(calls)
        await model.load()
        model.beginChild(of: nil)
        #expect(model.childParent == nil)
        model.childName = "Quote"
        model.childPlural = " Quotes "
        model.beginChildIcon()
        await model.chooseIcon("lucide:quote")
        #expect(!model.isChoosingChildIcon && model.isMakingChild)
        await model.makeChild()
        #expect(calls.state.withLock { $0.made } == [NewTypeRecord(id: "user.quote", label: "Quote", plural: "Quotes", icon: "lucide:quote", parent: nil)])
        #expect(model.made == "user.quote")
        #expect(TypesModel.regularPlural(of: "Story") == "Stories")
        #expect(TypesModel.regularPlural(of: "Day") == "Days")
        #expect(TypesModel.regularPlural(of: "Box") == "Boxes")
        #expect(TypesModel.regularPlural(of: "URL") == "URLs")
    }

    @Test func aFieldIsAddedRequiredAndNotSearchableAsChosen() async {
        let calls = withFields()
        let model = model(calls)
        await model.load()
        model.open("user.job")
        model.beginField()
        model.newFieldName = "Site"
        model.newFieldRequired = true
        model.newFieldSearchable = false
        await model.makeField()
        #expect(
            calls.state.withLock { $0.changes.map(\.edit) }
                == [.addField(NewFieldRecord(key: "site", label: "Site", kind: .text, isRequired: true, isSearchable: false))])
    }

    /// Any change to how long versions stay can let the server delete versions, longer or shorter, so every one asks first
    /// and is sent only once agreed.
    @Test func everyChangeToKeepVersionsAsksFirst() async {
        let calls = withFields()
        let model = model(calls)
        await model.load()
        var asked: [[VersionWindow?]] = []
        await model.setVersionWindow(.days(90), of: "user.job") { asked.append([$0, $1]); return false }
        #expect(calls.state.withLock { $0.changes.isEmpty })
        await model.setVersionWindow(.days(90), of: "user.job") { asked.append([$0, $1]); return true }
        await model.setVersionWindow(.days(7), of: "user.job") { asked.append([$0, $1]); return true }
        await model.setVersionWindow(nil, of: "user.job") { asked.append([$0, $1]); return true }
        #expect(asked == [[nil, .days(90)], [nil, .days(90)], [.days(90), .days(7)], [.days(7), nil]])
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.versionWindow(90), .versionWindow(7), .versionWindow(nil)])
    }

    @Test func aStrictSwitchTheServerRefusesShowsWhatTheServerHolds() async {
        let calls = listing()
        let owner = FakeOwnerCalls()
        owner.state.withLock { $0.sourceLimit.strictTypes = ["user.job"] }
        let model = model(calls, grants: [.schemaWrite, .configManage], owner: owner)
        await model.load()
        #expect(model.isStrict("user.job"))
        owner.fail("setSourceLimit", with: .refused("No."))
        await model.setStrict(false, of: "user.job")
        #expect(model.isStrict("user.job"))
        #expect(model.fieldErrors[.strict] != nil)
        let unread = self.model(calls, owner: owner)
        await unread.load()
        #expect(unread.strictTypes == nil)
    }

    /// Strict changes only this type's place in strict mode: a source limit or allow-list set elsewhere since the page read
    /// it goes back as the server holds it.
    @Test func strictChangesOnlyItsOwnTypeAndKeepsTheOtherLevers() async {
        let calls = listing()
        let owner = FakeOwnerCalls()
        owner.state.withLock { $0.sourceLimit.strictTypes = ["user.quote"] }
        let model = model(calls, grants: [.schemaWrite, .configManage], owner: owner)
        await model.load()
        owner.state.withLock {
            $0.sourceLimit.isOn = true
            $0.sourceLimit.types = ["core.highlight"]
            $0.sourceLimit.sources = ["readwise"]
            $0.sourceLimit.allowlist = (["core.task"], ["github"])
            $0.sourceLimit.strictTypes = ["user.quote", "user.rework"]
        }
        await model.setStrict(true, of: "user.job")
        let held = owner.state.withLock { $0.sourceLimit }
        #expect(owner.state.withLock { $0.leversSent.count } == 1)
        #expect(held.isOn && held.types == ["core.highlight"] && held.sources == ["readwise"])
        #expect(held.allowlist?.types == ["core.task"] && held.allowlist?.sources == ["github"])
        #expect(held.strictTypes == ["user.quote", "user.rework", "user.job"])
        #expect(model.strictTypes == ["user.quote", "user.rework", "user.job"])
    }

    /// The switch is sent only while the type's place in strict mode is as the switch showed it.
    @Test func aStrictSwitchChangedElsewhereIsToldAndSendsNothing() async {
        let calls = listing()
        let owner = FakeOwnerCalls()
        let model = model(calls, grants: [.schemaWrite, .configManage], owner: owner)
        await model.load()
        #expect(!model.isStrict("user.job"))
        owner.state.withLock { $0.sourceLimit.strictTypes = ["user.job"] }
        await model.setStrict(true, of: "user.job")
        #expect(owner.state.withLock { $0.leversSent.isEmpty })
        #expect(model.fieldErrors[.strict] == "Strict was changed somewhere else. Nothing was sent.")
        #expect(model.isStrict("user.job"))
    }

    /// Who May Write and a type's Strict switch saved at once share the one enforcement writer: the second reads the levers
    /// only once the first has written, so it carries the first's change and both are held.
    @Test func whoMayWriteAndStrictSavedAtOnceAreBothHeld() async {
        let owner = FakeOwnerCalls()
        owner.state.withLock {
            $0.sources = [OwnerSource(code: "rss", name: "RSS")]
            $0.keys = [KeyInfo(id: "key-rss", label: "RSS", source: "rss", permissions: [], tier: .library, types: ["*": .write], expires: nil, claims: [])]
        }
        let access = TypeAccess(
            ownItems: { _ in 0 }, currentIcon: { _ in nil }, setIcon: { _, _ in nil }, markSets: [], marks: { _, _ in [] }, plural: { _ in nil })
        let context = OwnerContext(calls: owner, grants: { [.schemaWrite, .configManage, .keysManage] }, holds: { $0 == "*:write" })
        let types = TypesModel(context: context, calls: listing(), access: access)
        let writers = SourceLimitModel(rule: .allowlist, context: context)
        await types.load()
        await writers.load()
        writers.types = ["core.note"]
        writers.checkedSources = ["rss"]
        let gate = owner.hold("setSourceLimit")
        let allowlist = Task { await writers.save() }
        #expect(await eventually { owner.calls.contains("setSourceLimit") })
        let strict = Task { await types.setStrict(true, of: "user.job") }
        gate.open()
        await allowlist.value
        gate.open()
        await strict.value

        let held = owner.state.withLock { $0.sourceLimit }
        #expect(owner.state.withLock { $0.leversSent.count } == 2)
        #expect(held.allowlist?.types == ["core.note"] && held.allowlist?.sources == ["rss"])
        #expect(held.strictTypes == ["user.job"])
        #expect(writers.line == nil)
        #expect(types.fieldErrors[.strict] == nil)
        #expect(types.isStrict("user.job"))
    }

    @Test func aSignInThatNoLongerHoldsConfigManageSendsNoStrictSwitch() async {
        let calls = listing()
        let owner = FakeOwnerCalls()
        var grants: Set<InstancePermission> = [.schemaWrite, .configManage]
        let access = TypeAccess(
            ownItems: { _ in 0 }, currentIcon: { _ in nil }, setIcon: { _, _ in nil }, markSets: [], marks: { _, _ in [] }, plural: { _ in nil })
        let model = TypesModel(
            context: OwnerContext(calls: owner, grants: { grants }, holds: { $0 == "*:write" }), calls: calls, access: access)
        await model.load()
        grants = [.schemaWrite]
        await model.setStrict(true, of: "user.job")
        #expect(owner.state.withLock { $0.leversSent.isEmpty })
        #expect(model.fieldErrors[.strict] == OwnerWording.line(.notPermitted("config.manage"), on: .types))
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
@Suite(.hangLimit) struct TypeReplacementTests {
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

    @Test func aChangeTheTypeAlreadyHoldsIsNotSent() async throws {
        let job = listed("user.job", fields: ["status": Definition(_type: .status, statusValues: [Word(value: "waiting", group: .notStarted, description: "Parts ordered.")])])
        var replaced = 0
        for change: TypeDefinitionEdit.TypeChange in [
            .label("Job"), .plural("Jobs"), .description("Kitchens"), .addWord(group: "not_started", value: "waiting"),
            .wordMeaning(value: "waiting", text: "Parts ordered."),
        ] {
            try await TypeDefinitionEdit.run(change, to: "user.job", read: { [job] }, replace: { _ in replaced += 1 })
        }
        #expect(replaced == 0)
        for change: TypeDefinitionEdit.TypeChange in [
            .label("Work"), .plural(""), .description(""), .parent("core.task"), .addWord(group: "in_progress", value: "waiting"),
            .wordMeaning(value: "waiting", text: ""),
        ] {
            try await TypeDefinitionEdit.run(change, to: "user.job", read: { [job, task] }, replace: { _ in replaced += 1 })
        }
        #expect(replaced == 6)
    }

    @Test func aChoiceIsAddedToAndTakenOutOfTheChoicesTheFieldOffersNow() throws {
        let job = listed("user.job", fields: ["kind": Definition(_type: .string, enumValues: ["kitchen", "stairs"])])
        let added = try TypeDefinitionEdit.update(job, applying: .field(key: "kind", .addChoice("garden")), in: [job])
        #expect(added.fields.additionalProperties["kind"]?.enumValues == ["kitchen", "stairs", "garden"])
        let removed = try TypeDefinitionEdit.update(job, applying: .field(key: "kind", .removeChoice("kitchen")), in: [job])
        #expect(removed.fields.additionalProperties["kind"]?.enumValues == ["stairs"])
        let last = listed("user.job", fields: ["kind": Definition(_type: .string, enumValues: ["stairs"])])
        #expect(throws: TypeSchemaFailure.refused("A choice field needs at least one choice.")) {
            try TypeDefinitionEdit.update(last, applying: .field(key: "kind", .removeChoice("stairs")), in: [last])
        }
    }

    @Test func aChoiceTheFieldAlreadyOffersOrLacksIsNotSent() async throws {
        let job = listed("user.job", fields: ["kind": Definition(_type: .string, enumValues: ["kitchen", "stairs"])])
        var replaced = 0
        for change: TypeDefinitionEdit.TypeChange in [.field(key: "kind", .addChoice("stairs")), .field(key: "kind", .removeChoice("garden"))] {
            try await TypeDefinitionEdit.run(change, to: "user.job", read: { [job] }, replace: { _ in replaced += 1 })
        }
        #expect(replaced == 0)
    }

    @Test func aPluginsTypeIsNeverReplaced() async {
        var replaced = 0
        let ticket = listed("common.ticket", origin: .plugin)
        await #expect(throws: TypeSchemaFailure.pluginType) {
            try await TypeDefinitionEdit.run(.description("x"), to: "common.ticket", read: { [ticket] }, replace: { _ in replaced += 1 })
        }
        #expect(replaced == 0)
    }

    @Test func aFieldIsAddedAndAChoiceFieldCarriesItsChoices() throws {
        let job = listed("user.job", parent: "core.task")
        let text = try TypeDefinitionEdit.update(job, applying: .addField(NewFieldRecord(key: "client", label: "Client", kind: .text)), in: [job, task])
        #expect(text.fields.additionalProperties["client"]?._type == .string)
        #expect(text.fields.additionalProperties["client"]?.label == "Client")
        #expect(text.fields.additionalProperties["client"]?.enumValues == nil)
        let choice = try TypeDefinitionEdit.update(job, applying: .addField(NewFieldRecord(key: "tier", label: "Tier", kind: .choice, choices: ["gold"])), in: [job, task])
        #expect(choice.fields.additionalProperties["tier"]?._type == ._enum)
        #expect(choice.fields.additionalProperties["tier"]?.enumValues == ["gold"])
    }

    @Test func aFieldAParentDeclaresCannotBeAddedOrChangedHere() {
        let job = listed("user.job", parent: "core.task")
        #expect(throws: TypeSchemaFailure.self) {
            try TypeDefinitionEdit.update(job, applying: .addField(NewFieldRecord(key: "status", label: "Status", kind: .text)), in: [job, task])
        }
        #expect(throws: TypeSchemaFailure.changedOnServer) {
            try TypeDefinitionEdit.update(job, applying: .field(key: "status", .required(true)), in: [job, task])
        }
        #expect(throws: TypeSchemaFailure.changedOnServer) {
            try TypeDefinitionEdit.update(job, applying: .removeField(key: "status"), in: [job, task])
        }
    }

    @Test func aFieldsRulesChangeOnlyThatFieldAndSendTheGuidanceBack() throws {
        let job = listed(
            "user.job", guidance: "Keep it short.", fields: [
                "client": Definition(_type: .string, label: "Client", description: "Old", searchable: false),
                "site": Definition(_type: .string, label: "Site"),
            ])
        let required = try TypeDefinitionEdit.update(job, applying: .field(key: "client", .required(true)), in: [job])
        #expect(required.fields.additionalProperties["client"]?.required == true)
        #expect(required.fields.additionalProperties["client"]?.searchable == false)
        #expect(required.fields.additionalProperties["site"] == job.value1.fields.additionalProperties["site"])
        #expect(required.guidance == "Keep it short.")
        let searchable = try TypeDefinitionEdit.update(job, applying: .field(key: "client", .searchable(true)), in: [job])
        #expect(searchable.fields.additionalProperties["client"]?.searchable == nil)
        let meaning = try TypeDefinitionEdit.update(job, applying: .field(key: "client", .meaning("")), in: [job])
        #expect(meaning.fields.additionalProperties["client"]?.description == nil)
        let removed = try TypeDefinitionEdit.update(job, applying: .removeField(key: "client"), in: [job])
        #expect(Set(removed.fields.additionalProperties.keys) == ["site"])
    }

    @Test func addingAFieldOrSettingVersionsSendsTheRestOfTheTypeBackAsItWas() throws {
        let job = listed(
            "user.job", parent: "core.task", guidance: "One job is one piece of paid work.", fields: [
                "status": Definition(_type: .status, statusValues: [Word(value: "waiting", group: .notStarted, description: "Parts ordered.")]),
                "client": Definition(_type: .string, label: "Client", required: true, searchable: false),
            ])
        let added = try TypeDefinitionEdit.update(
            job, applying: .addField(NewFieldRecord(key: "site", label: "Site", kind: .text, isRequired: true, isSearchable: false)), in: [job, task])
        #expect(added.fields.additionalProperties["site"] == Definition(_type: .string, label: "Site", required: true, searchable: false))
        var versioned = job
        versioned.value1.versionPolicy = .init(maxVersions: 200)
        let windows = try TypeDefinitionEdit.update(versioned, applying: .versionWindow(90), in: [versioned, task])
        #expect(windows.versionPolicy == .init(recentDays: 90, dailySnapshotDays: 90, weeklySnapshotDays: 90, maxVersions: 200))
        let back = try TypeDefinitionEdit.update(versioned, applying: .versionWindow(nil), in: [versioned, task])
        #expect(back.versionPolicy == .init(maxVersions: 200))
        for update in [added, windows, back] {
            #expect(update.fields.additionalProperties["status"] == job.value1.fields.additionalProperties["status"])
            #expect(update.fields.additionalProperties["client"] == job.value1.fields.additionalProperties["client"])
            #expect(update.guidance == "One job is one piece of paid work.")
            #expect(update.label == "Job" && update.plural == "Jobs" && update.description == "Kitchens" && update.parent == "core.task")
            #expect(update.version == 3)
        }
        #expect(try TypeDefinitionEdit.update(job, applying: .versionWindow(nil), in: [job, task]).versionPolicy == nil)
        #expect(ServerTypeCalls.versionWindow(.init(recentDays: 30, dailySnapshotDays: 30, weeklySnapshotDays: 30)) == .days(30))
        #expect(ServerTypeCalls.versionWindow(.init(recentDays: 30, dailySnapshotDays: 90, weeklySnapshotDays: 365)) == .custom)
        #expect(ServerTypeCalls.versionWindow(.init(maxVersions: 10)) == nil)
    }

    @Test func aFeedWindowAndAMergeStrategyAreSetNeverAndLeftToTheTypeAbove() throws {
        let job = listed("user.job")
        let days = try TypeDefinitionEdit.update(job, applying: .feedWindow(.days(30)), in: [job])
        #expect(days.retentionPolicy?.feedDays == .value(30))
        let never = try TypeDefinitionEdit.update(job, applying: .feedWindow(.never), in: [job])
        #expect(never.retentionPolicy?.feedDays == .null)
        let above = try TypeDefinitionEdit.update(job, applying: .feedWindow(nil), in: [job])
        #expect(above.retentionPolicy == nil)
        let merge = try TypeDefinitionEdit.update(job, applying: .mergeStrategy("keep_both_copies"), in: [job])
        #expect(merge.mergePolicy?._default == .keepBothCopies)
        #expect(try TypeDefinitionEdit.update(job, applying: .mergeStrategy(nil), in: [job]).mergePolicy == nil)
    }
}

/// The one writer of the instance's enforcement.
@MainActor
@Suite(.hangLimit) struct EnforcementSettingsTests {
    /// Two writes of different levers at once: the second reads only once the first has written, so it sends the first's
    /// lever back as the server then holds it, never as it was before.
    @Test func writesRunOneAtATimeSoNoneUndoesAnother() async throws {
        let bench = OwnerBench(grants: [.configManage])
        let context = bench.context
        let gate = bench.calls.hold("setSourceLimit")
        let strict = Task {
            try await context.writeEnforcement(readFrom: "instance-1", unchangedSince: { _ in true }) { $0.strictTypes = ["user.job"] }
        }
        #expect(await eventually { bench.calls.calls.contains("setSourceLimit") })
        let filter = Task {
            try await context.writeEnforcement(readFrom: "instance-1", unchangedSince: { _ in true }) {
                $0.isOn = true
                $0.types = ["core.note"]
                $0.sources = ["rss"]
            }
        }
        // Given time to run, the second write still waits for the first rather than reading under it.
        let readUnder = await eventually(within: .milliseconds(300)) { bench.calls.calls.filter { $0 == "sourceLimit" }.count > 1 }
        #expect(!readUnder)
        gate.open()
        _ = try await strict.value
        gate.open()
        let last = try await filter.value
        #expect(last.strictTypes == ["user.job"])
        #expect(last.isOn && last.types == ["core.note"] && last.sources == ["rss"])
    }

    @Test func anotherMarfaAnsweringIsToldAndNothingIsSent() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock { $0.sourceLimit.instanceID = "instance-2" }
        await #expect(throws: EnforcementSettings.Failure.anotherMarfa) {
            try await bench.context.writeEnforcement(readFrom: "instance-1", unchangedSince: { _ in true }) { $0.strictTypes = ["user.job"] }
        }
        #expect(bench.calls.state.withLock { $0.leversSent.isEmpty })
    }
}

/// How the server's refusals of a type's replacement are read.
@Suite(.hangLimit) struct TypeRefusalTests {
    private func answer(_ json: String, status: UInt16 = 400, code: String) throws -> ServerAnswer {
        ServerAnswer(status: status, code: code, details: try JSONValue(json: json), requestId: nil)
    }

    @Test func aRefusalNamesItsFieldFromTheServersAnswerNotFromTheErrorsOwnDetails() throws {
        let server = try answer(#"{"errors":[{"field":"fields.status.status_values.1.value","message":"Expected a word."}]}"#, code: "invalid_schema")
        let error = MarfaError.validation(code: "invalid_schema", message: "Invalid type schema", details: nil, server: server)
        #expect(ServerTypeCalls.failure(error) == .invalid(field: "fields.status.status_values.1.value", message: "Expected a word."))
    }

    @Test func aRefusalForGuidanceAnAppMadeIsToldApartFromOneForAMissingPermission() throws {
        let app = try answer(#"{"changes":["guidance"]}"#, status: 403, code: "forbidden")
        #expect(ServerTypeCalls.failure(MarfaError.forbidden(code: "forbidden", message: "Forbidden", server: app)) == .guidanceByApp)
        let missing = try answer(#"{"changes":["guidance"],"required_scope":"schema.write"}"#, status: 403, code: "forbidden")
        #expect(
            ServerTypeCalls.failure(MarfaError.forbidden(code: "forbidden", message: "Forbidden", server: missing))
                == .owner(.notPermitted("schema.write")), "a missing permission shows Allow More…, not the command")
    }

    @Test func aSignInSheetTheOwnerClosedIsNotAFailure() {
        #expect(ServerTypeCalls.failure(MarfaError.canceled(message: "closed")) == .canceled)
        #expect(ServerTypeCalls.failure(MarfaError.forbidden(code: "access_denied", message: "no", server: nil)) == .owner(.notConfirmed))
    }

    @Test func aRefusalForAMissingPermissionNamesIt() throws {
        let server = try answer(#"{"required_scope":"schema.write"}"#, status: 403, code: "forbidden")
        let error = MarfaError.forbidden(code: "forbidden", message: "Forbidden", server: server)
        #expect(ServerTypeCalls.failure(error) == .owner(.notPermitted("schema.write")))
    }

    @Test func aTypeInUseAndATypeWithChildrenAreToldApart() throws {
        let inUse = try answer(#"{"item_count":18,"settings":[{"kind":"folder"}]}"#, status: 409, code: "type_in_use")
        let items = MarfaError.server(status: 409, code: "type_in_use", message: "In use", details: nil, server: inUse)
        #expect(ServerTypeCalls.failure(items) == .inUse(items: 18, settings: 1))
        let below = try answer(#"{"subtype_ids":["user.rework"]}"#, status: 409, code: "type_has_subtypes")
        let children = MarfaError.server(status: 409, code: "type_has_subtypes", message: "Has subtypes", details: nil, server: below)
        #expect(ServerTypeCalls.failure(children) == .hasSubtypes(["user.rework"]))
    }

    /// Hidden settings have no ID in the refusal (`types/move-settings-authority`).
    @Test func aBlockedMoveNamesEachSettingAndWhy() throws {
        let blocked = try answer(
            """
            {"settings":[
              {"kind":"view","id":"v1","field":"query.filter","reason":"filter_term",
               "message":"Its filter tests the type in a way a move can't rewrite. Change the filter, then move."},
              {"kind":"webhook","field":"type_filter","reason":"not_permitted",
               "message":"This credential can't change this setting. Change it with a credential that can, then move."}
            ]}
            """,
            status: 409, code: "type_move_blocked")
        let error = MarfaError.server(
            status: 409, code: "type_move_blocked",
            message: #"A folder, view or webhook names "user.job" in a way the move can't rewrite. Change each setting listed, then move."#,
            details: nil, server: blocked)
        #expect(
            ServerTypeCalls.failure(error)
                == .moveBlocked(
                    settings: [
                        TypeSettingRecord(kind: .view, id: "v1", field: "query.filter", blocked: .filterTerm),
                        TypeSettingRecord(kind: .webhook, id: nil, field: "type_filter", blocked: .notPermitted),
                    ], tables: []))
    }

    @Test func aBlockedMoveNamesTheTablesTheTargetLacks() throws {
        let blocked = try answer(#"{"tables":["rooms"]}"#, status: 409, code: "type_move_blocked")
        let error = MarfaError.server(
            status: 409, code: "type_move_blocked",
            message: "The target type does not declare rooms, which items hold rows in. Declare them on the target first.",
            details: nil, server: blocked)
        #expect(ServerTypeCalls.failure(error) == .moveBlocked(settings: [], tables: ["rooms"]))
    }
}

extension TypesModelTests {
    private func guidanceOpen(_ calls: FakeTypeCalls) async -> TypesModel {
        calls.state.withLock { $0.types[2].guidance = "One job is one piece of paid work." }
        let model = model(calls)
        await model.load()
        model.open("user.job")
        return model
    }

    @Test func guidanceTypedAndLeftIsSentAsTheSameQueuedChangeAndShownAsTheServerHoldsIt() async {
        let calls = listing()
        let model = await guidanceOpen(calls)
        #expect(model.guidanceText == "One job is one piece of paid work.")
        model.guidanceText = "  One job is one piece of paid work.\n\nPut the client on it.\n"
        await model.commit(.guidance)
        #expect(calls.state.withLock { $0.changes.map(\.edit) } == [.guidance("One job is one piece of paid work.\n\nPut the client on it.")])
        #expect(model.guidanceText == "One job is one piece of paid work.\n\nPut the client on it.")
        #expect(!model.guidanceNeedsCommand && model.fieldErrors[.guidance] == nil)
    }

    @Test func guidanceLeftAloneSendsNothingEvenWhereTheTypeHoldsTrailingLines() async {
        let calls = listing()
        let model = await guidanceOpen(calls)
        calls.state.withLock { $0.types[2].guidance = "One job.\n\n" }
        await model.load()
        model.guidanceText = "One job.\n\n"
        await model.commit(.guidance)
        #expect(calls.state.withLock { $0.started }.isEmpty)
    }

    @Test func guidanceIsCountedInCodePointsAndOneOverTheLimitIsNotSent() async {
        let calls = listing()
        let model = await guidanceOpen(calls)
        model.guidanceText = String(repeating: "🛠", count: TypesModel.guidanceLimit)
        await model.commit(.guidance)
        #expect(calls.state.withLock { $0.started }.count == 1, "1,000 emoji are 1,000 characters")
        model.guidanceText = String(repeating: "x", count: TypesModel.guidanceLimit + 1)
        await model.commit(.guidance)
        #expect(calls.state.withLock { $0.started }.count == 1)
        #expect(model.fieldErrors[.guidance] == TypesModel.line(for: .guidance))
        #expect(model.fieldErrors[.guidance]?.contains("characters at most") == true)
        #expect(model.guidanceText.count == TypesModel.guidanceLimit + 1, "what was typed stays")
    }

    @Test func aRefusalOfGuidanceFromAnAppKeepsTheTextAndGivesTheCommandOnce() async {
        let calls = listing()
        let model = await guidanceOpen(calls)
        calls.state.withLock { $0.refusal = .guidanceByApp }
        model.guidanceText = "Put the client on every job."
        await model.commit(.guidance)
        #expect(model.guidanceNeedsCommand)
        #expect(model.guidanceText == "Put the client on every job.")
        #expect(model.pageFailure == nil, "it is told on the field, not above the page")
        #expect(TypesModel.guidanceCommand(for: "user.job") == "marfa types replace user.job --file user.job.json")
        await model.commit(.guidance)
        #expect(calls.state.withLock { $0.started }.count == 1, "leaving the field again sends the same text again to no purpose")
        model.guidanceText = "Put the client on every job, and the site."
        calls.state.withLock { $0.refusal = nil }
        await model.commit(.guidance)
        #expect(!model.guidanceNeedsCommand, "a text the server takes ends the command")
        #expect(calls.state.withLock { $0.types[2].guidance } == "Put the client on every job, and the site.")
    }

    @Test func aSignInSheetTheOwnerClosedSavesNothingAndSaysNothing() async {
        let calls = listing()
        let model = await guidanceOpen(calls)
        calls.state.withLock { $0.refusal = .canceled }
        model.guidanceText = "Changed."
        await model.commit(.guidance)
        #expect(model.pageFailure == nil && model.fieldErrors[.guidance] == nil && !model.guidanceNeedsCommand)
        #expect(model.guidanceText == "Changed.", "the text stays to be saved again")
        #expect(calls.state.withLock { $0.types[2].guidance } == "One job is one piece of paid work.")
    }

    @Test func aDeclinedSignInIsToldAsNotChanged() async {
        let calls = listing()
        let model = await guidanceOpen(calls)
        calls.state.withLock { $0.refusal = .owner(.notConfirmed) }
        model.guidanceText = "Changed."
        await model.commit(.guidance)
        #expect(model.pageFailure == .notConfirmed)
        #expect(model.guidanceText == "Changed.")
    }

    @Test func guidanceTypedAndNotKeptIsHandedBackWhenSettingsCloses() async {
        let calls = listing()
        let model = await guidanceOpen(calls)
        model.guidanceText = "Put the client on every job."
        let drafts = model.takeDrafts()
        #expect(drafts.count == 1)
        #expect(model.guidanceText == "One job is one piece of paid work.")
    }

    @Test func guidanceClearedAndNotKeptIsToldWhenSettingsCloses() async {
        let calls = listing()
        let model = await guidanceOpen(calls)
        model.guidanceText = ""
        let drafts = model.takeDrafts()
        #expect(drafts.count == 1)
        #expect(model.guidanceText == "One job is one piece of paid work.")
    }

    @Test func aPluginsTypeSendsNoGuidance() async {
        let calls = listing()
        let model = model(calls)
        await model.load()
        model.open("common.ticket")
        model.guidanceText = "Changed."
        await model.commit(.guidance)
        #expect(calls.state.withLock { $0.started }.isEmpty)
    }
}
