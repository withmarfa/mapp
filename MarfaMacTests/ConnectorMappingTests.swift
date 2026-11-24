import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

@MainActor
@Suite(.hangLimit) struct ConnectorMappingTests {
    private static func field(
        _ name: String, _ kind: MappingFieldKind = .string, required: Bool = false, words: [(String, String)] = []
    ) -> MappingTypeField {
        MappingTypeField(
            name: name, label: nil, kind: kind, required: required, choices: [],
            statusWords: words.map { MappingStatusWord(value: $0.0, group: $0.1) })
    }

    private static let source = MappingTypeInfo(
        id: "feed.entry", label: "Entry", plural: "Entries",
        fields: [
            field("entry_id", required: true), field("title"), field("body"), field("published_at", .datetime),
            field("state", .status, words: [("open", "not_started"), ("closed", "completed")]),
        ])

    private static let task = MappingTypeInfo(
        id: "core.task", label: "Task", plural: "Tasks",
        fields: [
            field("title", required: true), field("body"), field("due_at", .datetime), field("estimate", .integer),
            field("status", .status, words: [("not_started", "not_started"), ("done", "completed"), ("dropped", "canceled")]),
        ])

    private static let job = MappingTypeInfo(
        id: "user.job", label: "Job", plural: "Jobs", fields: [field("title", required: true), field("client", required: true), field("due_at", .datetime)])

    private static let entryMapping = KindMapping(
        enabled: true, targetType: "feed.entry", tier: .feed, statusOverrides: [:],
        fields: [
            "entry_id": .field("entry_id"), "title": .field("title"), "body": .field("body"),
            "published_at": .field("published_at"), "state": .field("state"),
        ])

    private static let summary = PluginConnectorSummary(
        name: "feed", title: "Feed", description: "Entries.", mark: "lucide:rss", source: "feed", version: "1", hostID: "h1",
        kinds: [ConnectorKind(name: "entry", type: "feed.entry", direction: .into)], signIn: nil)

    private func model(_ bench: OwnerBench, version: Int = 3, count: Int = 40) -> ConnectorMappingModel {
        bench.calls.state.withLock {
            $0.mappings["feed"] = ConnectorMappingReading(version: version, kinds: ["entry": Self.entryMapping], rewrites: [])
            for type in [Self.source, Self.task, Self.job] { $0.mappingTypes[type.id] = type }
            $0.rewriteCounts["entry"] = count
        }
        return ConnectorMappingModel(context: bench.context, plugin: Self.summary)
    }

    private func loaded(_ bench: OwnerBench = OwnerBench(grants: [.connectorsManage]), count: Int = 40) async -> (ConnectorMappingModel, OwnerBench) {
        let model = model(bench, count: count)
        await model.load()
        return (model, bench)
    }

    // MARK: Saving

    @Test func theMappingIsReadWithTheTypesItNames() async {
        let (model, _) = await loaded()
        #expect(model.version == 3)
        #expect(model.kinds["entry"]?.draft == Self.entryMapping)
        #expect(model.type("feed.entry")?.plural == "Entries")
        #expect(model.counts["entry"] == 40)
        #expect(model.targetChoices(for: "entry").first?.id == "feed.entry")
    }

    @Test func aChangeIsSavedAtOnceOnTheVersionRead() async {
        let (model, bench) = await loaded()
        await model.setTier(.library, for: "entry")
        let sent = bench.calls.state.withLock { $0.mappingSaves }
        #expect(sent.count == 1)
        #expect(sent[0].version == 3)
        #expect(sent[0].kinds["entry"]?.tier == .library)
        #expect(model.version == 4)
        #expect(model.kinds["entry"]?.saved.tier == .library)
        #expect(!model.isUnsaved("entry"))
    }

    @Test func aMappingTheTypeRefusesKeepsTheDraftNamesTheFieldAndLeavesTheStoredOneAlone() async {
        let (model, bench) = await loaded()
        await model.setTarget("user.job", for: "entry")
        let job = Self.job
        // The fields both types hold are filled from the kind's own; Job's client has none to come from.
        #expect(model.kinds["entry"]?.draft.targetType == "user.job")
        #expect(model.kinds["entry"]?.draft.fields["title"] == .field("title"))
        #expect(model.kinds["entry"]?.draft.fields["client"] == nil)
        #expect(model.kinds["entry"]?.saved.targetType == "feed.entry")
        #expect(model.version == 3)
        #expect(model.isRefused("entry"))
        #expect(model.error(for: job.field("client")!, in: "entry") == "Job needs Client. Choose a field or a fixed value.")
        #expect(model.error(for: job.field("title")!, in: "entry") == nil)
        #expect(bench.calls.state.withLock { $0.mappings["feed"]?.kinds["entry"]?.targetType } == "feed.entry")
    }

    @Test func aFixedValueFillsTheFieldAndTheRefusalGoes() async {
        let (model, bench) = await loaded()
        await model.setTarget("user.job", for: "entry")
        let client = Self.job.field("client")!
        await model.setChoice(.fixed, for: client, in: "entry")
        // An empty value fills nothing, so the save is refused again and the choice stays on the page.
        #expect(model.choice(of: "client", in: "entry") == .fixed)
        #expect(model.isRefused("entry"))
        model.type("Castell Studio", into: client, in: "entry")
        await model.commit("entry")
        #expect(!model.isRefused("entry"))
        #expect(model.version == 4)
        #expect(bench.calls.state.withLock { $0.mappings["feed"]?.kinds["entry"]?.fields["client"] } == .fixed(.text("Castell Studio")))
    }

    @Test func aStaleSaveKeepsTheDraftAndReloadCarriesItOntoWhatIsThereNow() async {
        let (model, bench) = await loaded()
        bench.calls.state.withLock { $0.mappings["feed"]?.version = 9 }
        await model.setTier(.library, for: "entry")
        #expect(model.isStale)
        #expect(model.kinds["entry"]?.draft.tier == .library)
        #expect(model.kinds["entry"]?.saved.tier == .feed)
        #expect(model.version == 3)
        await model.reload()
        #expect(!model.isStale)
        #expect(model.version == 10)
        #expect(bench.calls.state.withLock { $0.mappings["feed"]?.kinds["entry"]?.tier } == .library)
    }

    @Test func aReadingOlderThanTheOneHeldDoesNotReplaceTheDraft() async {
        let (model, bench) = await loaded()
        await model.setTier(.library, for: "entry")
        bench.calls.state.withLock {
            $0.mappings["feed"] = ConnectorMappingReading(version: 3, kinds: ["entry": Self.entryMapping], rewrites: [])
        }
        await model.load()
        #expect(model.version == 4)
        #expect(model.kinds["entry"]?.draft.tier == .library)
        #expect(model.kinds["entry"]?.saved.tier == .library)
    }

    @Test func aReadWhileASaveRunsIsNotTaken() async {
        let (model, bench) = await loaded()
        let gate = bench.calls.hold("saveConnectorMapping")
        let saving = Task { await model.setTier(.library, for: "entry") }
        #expect(await eventually { bench.calls.calls.contains("saveConnectorMapping") })
        bench.calls.state.withLock { $0.mappings["feed"]?.version = 9 }
        await model.load()
        #expect(model.version == 3)
        #expect(model.kinds["entry"]?.draft.tier == .library)
        gate.open()
        await saving.value
        #expect(model.isStale)
        #expect(model.version == 3)
        #expect(model.kinds["entry"]?.draft.tier == .library)
        #expect(model.kinds["entry"]?.saved.tier == .feed)
    }

    @Test func aChangeMadeWhileASaveRunsIsSavedAfterIt() async {
        let (model, bench) = await loaded()
        let gate = bench.calls.hold("saveConnectorMapping")
        let first = Task { await model.setTier(.library, for: "entry") }
        #expect(await eventually { bench.calls.calls.contains("saveConnectorMapping") })
        let second = Task { await model.setEnabled(false, for: "entry") }
        gate.open()
        // The change made meanwhile is saved by a second call, which the gate holds in turn.
        #expect(await eventually { bench.calls.calls.filter { $0 == "saveConnectorMapping" }.count == 2 })
        gate.open()
        await first.value
        await second.value
        let sent = bench.calls.state.withLock { $0.mappingSaves }
        #expect(sent.count == 2)
        #expect(sent[1].version == 4)
        #expect(sent[1].kinds["entry"]?.enabled == false)
        #expect(sent[1].kinds["entry"]?.tier == .library)
    }

    @Test func aSaveTheServerCannotAnswerKeepsTheDraftAndSaysSo() async {
        let (model, bench) = await loaded()
        bench.calls.fail("saveConnectorMapping", with: .unreachable)
        await model.setTier(.library, for: "entry")
        #expect(model.saveFailure == .unreachable)
        #expect(model.kinds["entry"]?.draft.tier == .library)
        #expect(model.isUnsaved("entry"))
    }

    // MARK: Fields

    @Test func anEmptyTemplateOnARequiredFieldUsesTheAppsSentence() async {
        let (model, _) = await loaded()
        await model.setTarget("user.job", for: "entry")
        let client = Self.job.field("client")!
        await model.setChoice(.template, for: client, in: "entry")
        #expect(model.wire("entry")?.fields["client"] == nil)
        #expect(model.error(for: client, in: "entry") == "Job needs Client. Choose a field or a fixed value.")
    }

    @Test func aTemplateIsSentOnlyOnceItHoldsTextAndIsNotWrittenBack() async {
        let (model, bench) = await loaded()
        let body = Self.task.field("body")!
        await model.setTarget("core.task", for: "entry")
        await model.setChoice(.template, for: body, in: "entry")
        #expect(model.choice(of: "body", in: "entry") == .template)
        #expect(model.wire("entry")?.fields["body"] == nil)
        model.type("{{ body }} {{ url }}", into: body, in: "entry")
        await model.commit("entry")
        let saved = bench.calls.state.withLock { $0.mappings["feed"]?.kinds["entry"]?.fields["body"] }
        #expect(saved == .template("{{ body }} {{ url }}"))
    }

    @Test func aNumberTypedIntoAFixedValueIsSentAsANumberAndAWordIsRefusedBeforeItGoes() async {
        let (model, bench) = await loaded()
        let estimate = Self.task.field("estimate")!
        await model.setTarget("core.task", for: "entry")
        await model.setChoice(.fixed, for: estimate, in: "entry")
        model.type("three", into: estimate, in: "entry")
        let before = bench.calls.state.withLock { $0.mappingSaves.count }
        await model.commit("entry")
        #expect(model.error(for: estimate, in: "entry") == "Enter a number.")
        #expect(bench.calls.state.withLock { $0.mappingSaves.count } == before)
        model.type("3", into: estimate, in: "entry")
        await model.commit("entry")
        #expect(bench.calls.state.withLock { $0.mappings["feed"]?.kinds["entry"]?.fields["estimate"] } == .fixed(.number(3)))
    }

    @Test func aFieldCanBeFilledOnlyFromFieldsOfTheSameSortOfValue() async {
        let (model, _) = await loaded()
        let due = Self.task.field("due_at")!
        let title = Self.task.field("title")!
        #expect(model.sources(for: due, in: "entry").map(\.name) == ["published_at"])
        #expect(Set(model.sources(for: title, in: "entry").map(\.name)) == ["body", "entry_id", "title"])
    }

    @Test func aStatusRefusalIsShownOnItsWordAndEveryOtherFaultIsKept() async {
        let (model, bench) = await loaded()
        await model.setTarget("core.task", for: "entry")
        await model.setChoice(.field("state"), for: Self.task.field("status")!, in: "entry")
        bench.calls.state.withLock {
            $0.scriptedMappingFaults = [
                MappingFault(path: "kinds.entry.status_overrides.closed", message: "Closed is not a word of Task."),
                MappingFault(path: "kinds.entry.status_overrides.open", message: "Open is not a word of Task."),
                MappingFault(path: "kinds.entry.target_type", message: "Task can't be written."),
                MappingFault(path: "kinds.entry.target_type", message: "Choose another type."),
                MappingFault(path: "kinds.entry.tier", message: "Feed is not a tier here."),
            ]
        }
        await model.setTier(.library, for: "entry")
        #expect(model.targetError("entry") == "Task can't be written.\nChoose another type.")
        #expect(model.overrideError(of: "closed", in: "entry") == "Closed is not a word of Task.")
        #expect(model.overrideError(of: "open", in: "entry") == "Open is not a word of Task.")
        #expect(model.looseFaults("entry").map(\.message) == ["Feed is not a tier here."])
    }

    @Test func aKindWithAStatusFieldMapsItsWordsByGroupWithAnOverridePerWord() async {
        let (model, bench) = await loaded()
        await model.setTarget("core.task", for: "entry")
        #expect(model.statusPair(of: "entry") == nil)
        await model.setChoice(.field("state"), for: Self.task.field("status")!, in: "entry")
        #expect(model.statusPair(of: "entry")?.own.statusWords.map(\.value) == ["open", "closed"])
        await model.setOverride("dropped", for: "closed", in: "entry")
        #expect(bench.calls.state.withLock { $0.mappings["feed"]?.kinds["entry"]?.statusOverrides } == ["closed": "dropped"])
        await model.setOverride(nil, for: "closed", in: "entry")
        #expect(bench.calls.state.withLock { $0.mappings["feed"]?.kinds["entry"]?.statusOverrides } == [:])
    }

    // MARK: Preview

    private func item() -> MappingPreviewItem {
        MappingPreviewItem(type: "feed.entry", title: "A post", properties: ["title": "A post"])
    }

    @Test func aPreviewOfAnUnsavedDraftSendsTheDraft() async {
        let (model, bench) = await loaded()
        bench.calls.fail("saveConnectorMapping", with: .unreachable)
        await model.setTier(.library, for: "entry")
        bench.calls.state.withLock { $0.previewAnswers = [.ready(item())] }
        await model.preview("entry", every: .milliseconds(1))
        #expect(bench.calls.state.withLock { $0.previewsAsked.last?.draft?.tier } == .library)
    }

    @Test func aFailedPollFromAnOlderPreviewDoesNotReplaceANewerOne() async {
        let (model, bench) = await loaded()
        let gate = bench.calls.hold("mappingPreview")
        let older = Task { await model.preview("entry", every: .milliseconds(1)) }
        #expect(await eventually { bench.calls.state.withLock { $0.waiting["mappingPreview"] ?? 0 } >= 1 })
        bench.calls.state.withLock {
            $0.previewStart = .ready(item())
            $0.previewFailureAfterWait = .unreachable
        }
        await model.preview("entry", every: .milliseconds(1))
        #expect(model.previewState("entry") == .ready(item()))
        gate.open()
        await older.value
        #expect(model.previewState("entry") == .ready(item()))
    }

    // MARK: Existing items

    @Test func aFailedReadAfterApplyIsShown() async {
        let (model, bench) = await loaded()
        bench.calls.fail("connectorMapping", with: .unreachable)
        model.askToApply("entry")
        await model.apply("entry")
        #expect(model.rewriteFailure == nil)
        #expect(model.readBackFailure == .unreachable)
        #expect(model.pending("entry").isEmpty)
        bench.calls.fail("connectorMapping", with: nil)
        await model.readBack()
        #expect(model.readBackFailure == nil)
        #expect(model.pending("entry").count == 1)
    }

    @Test func applyingToExistingItemsCountsFirstThenAsksAndShowsTheRequestPending() async {
        let (model, bench) = await loaded()
        #expect(bench.calls.state.withLock { $0.rewritesAsked.map(\.dryRun) } == [true])
        #expect(model.counts["entry"] == 40)
        model.askToApply("entry")
        #expect(model.question == "entry")
        await model.apply("entry")
        let asked = bench.calls.state.withLock { $0.rewritesAsked }
        #expect(asked.map(\.dryRun) == [true, false, true])
        #expect(asked[1].kinds == ["entry"])
        #expect(model.pending("entry").count == 1)
    }

    @Test func aDryRunThatFailsWhileTheQuestionIsOpenClosesItAndApplySendsNothing() async {
        let (model, bench) = await loaded()
        model.askToApply("entry")
        #expect(model.question == "entry")
        bench.calls.fail("rewriteConnectorItems", with: .unreachable)
        await model.count("entry")
        #expect(model.question == nil)
        bench.calls.fail("rewriteConnectorItems", with: nil)
        await model.apply("entry")
        #expect(!bench.calls.state.withLock { $0.rewritesAsked.map(\.dryRun) }.contains(false))
    }

    @Test func readingBackATargetChangedElsewhereCountsAgain() async {
        let (model, bench) = await loaded()
        bench.calls.state.withLock {
            $0.mappings["feed"]?.version = 9
            $0.mappings["feed"]?.kinds["entry"]?.targetType = "core.task"
        }
        await model.readBack()
        #expect(model.kinds["entry"]?.saved.targetType == "core.task")
        #expect(model.counts["entry"] != nil)
        #expect(model.canApply("entry"))
    }

    @Test func aFailedDryRunClearsTheCountAndANewTargetDoesNotKeepTheOldOne() async {
        let (model, bench) = await loaded()
        #expect(model.canApply("entry"))
        bench.calls.fail("rewriteConnectorItems", with: .unreachable)
        await model.count("entry")
        #expect(model.counts["entry"] == nil)
        #expect(!model.canApply("entry"))
        bench.calls.fail("rewriteConnectorItems", with: nil)
        await model.count("entry")
        let gate = bench.calls.hold("rewriteConnectorItems")
        let changing = Task { await model.setTarget("core.task", for: "entry") }
        #expect(await eventually {
            model.version == 4 && bench.calls.state.withLock { ($0.waiting["rewriteConnectorItems"] ?? 0) >= 1 }
        })
        #expect(model.counts["entry"] == nil)
        #expect(!model.canApply("entry"))
        #expect(!model.isSaving)
        gate.open()
        await changing.value
        #expect(model.counts["entry"] == 40)
        #expect(model.kinds["entry"]?.saved.targetType == "core.task")
        #expect(model.canApply("entry"))
    }

    @Test func aCountFromThePreviousTargetDoesNotComeBack() async {
        let (model, bench) = await loaded()
        let first = bench.calls.hold("rewriteConnectorItems")
        let recount = Task { await model.count("entry") }
        #expect(await eventually { bench.calls.state.withLock { ($0.waiting["rewriteConnectorItems"] ?? 0) >= 1 } })
        let second = bench.calls.hold("rewriteConnectorItems")
        bench.calls.state.withLock { $0.rewriteCounts["entry"] = 2 }
        let changing = Task { await model.setTarget("core.task", for: "entry") }
        #expect(await eventually {
            model.version == 4 && bench.calls.state.withLock { ($0.waiting["rewriteConnectorItems"] ?? 0) >= 2 }
        })
        first.open()
        await recount.value
        #expect(model.counts["entry"] == nil)
        #expect(!model.canApply("entry"))
        second.open()
        await changing.value
        #expect(model.counts["entry"] == 2)
        #expect(model.canApply("entry"))
    }

    @Test func nothingIsAppliedWhileTheDraftIsUnsavedOrThereIsNothingToMove() async {
        let (model, bench) = await loaded()
        bench.calls.fail("saveConnectorMapping", with: .unreachable)
        await model.setTier(.library, for: "entry")
        #expect(!model.canApply("entry"))
        model.askToApply("entry")
        #expect(model.question == nil)
        let (empty, _) = await loaded(count: 0)
        #expect(!empty.canApply("entry"))
    }

    // MARK: Closing and the server's words

    @Test func whatTheServerHoldsNotIsHandedOverWhenSettingsCloses() async {
        let (model, bench) = await loaded()
        bench.calls.fail("saveConnectorMapping", with: .unreachable)
        await model.setTier(.library, for: "entry")
        let drafts = model.takeDrafts()
        #expect(drafts.count == 1)
        guard case .typed(let title, let text) = drafts[0] else { Issue.record("expected typed text"); return }
        #expect(title == "Entry Mapping Not Saved")
        #expect(text.contains("Tier: Library"))
        let (clean, _) = await loaded()
        #expect(clean.takeDrafts().isEmpty)
    }

    @Test func theServersRefusalsAreReadFromTheirDetails() {
        let refusal = MarfaError.validation(
            code: "validation_error", message: "The mapping cannot be saved: kinds.entry.fields.client.",
            details: .object(["errors": .array([.object(["path": .string("kinds.entry.fields.client"), "message": .string("Job requires client.")])])]), server: nil)
        #expect(ClientOwnerCalls.mappingFaults(refusal) == [MappingFault(path: "kinds.entry.fields.client", message: "Job requires client.")])
        let stale = MarfaError.server(status: 409, code: "connector_mapping_stale", message: "Stale.", details: .object(["version": .integer(7)]), server: nil)
        #expect(ClientOwnerCalls.mappingStale(stale) == .some(7))
        #expect(ClientOwnerCalls.mappingStale(refusal) == nil)
        #expect(ClientOwnerCalls.mappingFaults(stale) == nil)
    }
}
