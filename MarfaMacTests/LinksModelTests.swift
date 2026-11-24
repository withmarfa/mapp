import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

/// The Links page deletes and registers link types the owner's items use, so nothing is sent before the owner agrees and a
/// refusal leaves the page as the server holds it.
@Suite(.hangLimit)
@MainActor struct LinksModelTests {
    private func listing() -> FakeOwnerCalls {
        let calls = FakeOwnerCalls()
        calls.state.withLock {
            $0.linkTypes = [
                OwnerLinkType(
                    id: "user.supplied_by", label: "Supplied By", reverseLabel: "Supplies", cardinality: .manyToOne, fromTypes: ["user.job"],
                    toTypes: ["core.person"], shipped: false),
                OwnerLinkType(
                    id: "tickets.blocks", label: "Blocks", reverseLabel: "Blocked By", cardinality: .manyToMany, fromTypes: ["*"], toTypes: ["*"],
                    shipped: false, plugin: "Tickets"),
                OwnerLinkType(
                    id: "parent-of", label: "Children", reverseLabel: "Parent", cardinality: .oneToMany, fromTypes: ["*"], toTypes: ["*"],
                    shipped: true),
            ]
            $0.linkTypeNames = ["user.job": "Job", "core.person": "Person"]
        }
        return calls
    }

    private func loaded(_ calls: FakeOwnerCalls) async -> LinksModel {
        let model = LinksModel(context: OwnerContext(calls: calls, grants: { Set(InstancePermission.allCases) }))
        await model.load()
        return model
    }

    /// The alert clears `question` as it closes, before the destructive button's task runs, so the delete takes the
    /// question the alert presented.
    @Test func aDeleteIsSentOnlyOnceTheOwnerAgreesWithTheQuestionTheAlertPresented() async throws {
        let calls = listing()
        let model = await loaded(calls)

        model.askToDelete("user.supplied_by")
        let asked = try #require(model.question)
        #expect(asked.shown.id == "user.supplied_by")
        model.dismissQuestion()
        #expect(!calls.calls.contains("deleteLinkType"))

        await model.confirmDelete(asked)
        #expect(calls.calls.filter { $0 == "deleteLinkType" }.count == 1)
        #expect(model.linkType("user.supplied_by") == nil)
        #expect(model.deleted == "user.supplied_by")
    }

    /// A question answered once, whatever the answer, sends nothing when answered again.
    @Test func aQuestionIsAnsweredOnce() async throws {
        let calls = listing()
        calls.state.withLock { $0.linkTypesInUse = ["user.supplied_by"] }
        let model = await loaded(calls)

        model.askToDelete("user.supplied_by")
        let refused = try #require(model.question)
        await model.confirmDelete(refused)
        #expect(calls.calls.filter { $0 == "deleteLinkType" }.count == 1)
        calls.state.withLock { $0.linkTypesInUse = [] }
        await model.confirmDelete(refused)
        #expect(calls.calls.filter { $0 == "deleteLinkType" }.count == 1, "a refused answer replayed")

        model.askToDelete("user.supplied_by")
        let cancelled = try #require(model.question)
        model.cancelDelete(cancelled)
        await model.confirmDelete(cancelled)
        #expect(calls.calls.filter { $0 == "deleteLinkType" }.count == 1, "a cancelled question")

        model.askToDelete("user.supplied_by")
        let skipped = try #require(model.question)
        calls.fail("linkTypes", with: .unreachable)
        await model.confirmDelete(skipped)
        calls.fail("linkTypes", with: nil)
        await model.confirmDelete(skipped)
        #expect(calls.calls.filter { $0 == "deleteLinkType" }.count == 1, "a skipped answer replayed")
        #expect(model.linkType("user.supplied_by") != nil)
    }

    /// Deleted somewhere else and registered again under the same ID: the owner never saw the new one.
    @Test func aReplacementUnderTheSameIDIsNotDeleted() async throws {
        let calls = listing()
        let model = await loaded(calls)
        model.askToDelete("user.supplied_by")
        let asked = try #require(model.question)
        calls.state.withLock { state in
            if let index = state.linkTypes.firstIndex(where: { $0.id == "user.supplied_by" }) {
                state.linkTypes[index].label = "Bought From"
                state.linkTypes[index].toTypes = ["*"]
            }
        }

        await model.confirmDelete(asked)
        #expect(!calls.calls.contains("deleteLinkType"))
        #expect(model.deleted == nil)
        #expect(model.deleteLine(for: "user.supplied_by") == "Supplied By changed since you chose Delete, so it wasn’t deleted. Check it, then try again.")
    }

    @Test func aTypeThatStoppedBeingTheOwnersSinceTheQuestionIsNotDeleted() async throws {
        let calls = listing()
        let model = await loaded(calls)
        model.askToDelete("user.supplied_by")
        let asked = try #require(model.question)
        calls.state.withLock { state in
            if let index = state.linkTypes.firstIndex(where: { $0.id == "user.supplied_by" }) { state.linkTypes[index].plugin = "Suppliers" }
        }

        await model.confirmDelete(asked)
        #expect(!calls.calls.contains("deleteLinkType"))
        #expect(model.deleted == nil)
        #expect(model.deleteLine(for: "user.supplied_by") == "Supplied By now comes from a plugin or from Marfa, so it wasn’t deleted.")
    }

    @Test func nothingIsDeletedWhenTheListCannotBeReadAgain() async throws {
        let calls = listing()
        let model = await loaded(calls)
        model.askToDelete("user.supplied_by")
        let asked = try #require(model.question)
        calls.fail("linkTypes", with: .unreachable)

        await model.confirmDelete(asked)
        #expect(!calls.calls.contains("deleteLinkType"))
        #expect(model.deleteLine(for: "user.supplied_by") != nil)
    }

    @Test func onlyTheOwnersOwnLinkTypesCanBeAskedAbout() async {
        let model = await loaded(listing())
        model.askToDelete("parent-of")
        #expect(model.question == nil)
        model.askToDelete("tickets.blocks")
        #expect(model.question == nil)
        #expect(model.yours.map(\.id) == ["user.supplied_by"])
        #expect(model.fromPlugins.map(\.id) == ["tickets.blocks"])
        #expect(model.builtIn.map(\.id) == ["parent-of"])
    }

    @Test func aRefusedDeleteLeavesTheListAsTheServerHoldsIt() async throws {
        let calls = listing()
        calls.state.withLock { $0.linkTypesInUse = ["user.supplied_by"] }
        let model = await loaded(calls)

        model.askToDelete("user.supplied_by")
        await model.confirmDelete(try #require(model.question))
        #expect(model.linkTypes == calls.state.withLock { $0.linkTypes })
        #expect(model.deleted == nil)
        #expect(model.deleteLine(for: "user.supplied_by") == "Items still link with Supplied By, so it was kept. Remove those links first.")

        calls.state.withLock { $0.linkTypesInUse = [] }
        calls.fail("deleteLinkType", with: .notPermitted("schema.write"))
        model.askToDelete("user.supplied_by")
        await model.confirmDelete(try #require(model.question))
        #expect(calls.calls.filter { $0 == "deleteLinkType" }.count == 2)
        #expect(model.linkTypes == calls.state.withLock { $0.linkTypes })
        #expect(model.linkType("user.supplied_by") != nil)
        #expect(model.deleteLine(for: "user.supplied_by") != nil)
    }

    @Test func aRefusedNewLinkTypeKeepsWhatWasTyped() async {
        let calls = listing()
        let model = await loaded(calls)
        model.beginNew()
        model.name = "Supplied By"
        model.fromType = "user.job"
        calls.fail("registerLinkType", with: .refused("Another link type has this name. Choose another."))
        await model.make()
        #expect(model.isMaking)
        #expect(model.name == "Supplied By")
        #expect(model.fromType == "user.job")
        #expect(model.makeFailureLine == "Another link type has this name. Choose another.")

        calls.fail("registerLinkType", with: nil)
        await model.make()
        #expect(!model.isMaking)
        let sent = calls.state.withLock { $0.linkTypesMade }
        #expect(sent.map(\.id) == ["user.supplied_by_2"])
        #expect(sent.first?.fromTypes == ["user.job"] && sent.first?.toTypes == ["*"])
        #expect(model.made == "user.supplied_by_2")
    }

    @Test func closingSettingsAfterARefusalHandsBackEveryField() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.linkTypeNames = ["user.job": "Job", "core.person": "Person"] }
        let model = LinksModel(context: bench.context)
        await model.load()
        model.beginNew()
        model.name = "Supplied By"
        model.otherEndName = "Supplies"
        model.fromType = "user.job"
        model.cardinality = .manyToOne
        bench.calls.fail("registerLinkType", with: .refused("Another link type has this name. Choose another."))
        await model.make()
        #expect(model.takeDrafts() == [
            .typed(
                title: "Link Type Not Made",
                text: "Name: Supplied By\nName at the Other End: Supplies\nFrom: Job\nTo: Any Type\nHow Many: Many to One"),
        ])
        #expect(!model.isMaking)
    }

    @Test func aNameTypedOnlyAtTheOtherEndIsHandedBack() async {
        let model = await loaded(listing())
        model.beginNew()
        model.otherEndName = "Supplies"
        model.toType = "core.person"
        #expect(model.takeDrafts() == [
            .typed(title: "Link Type Not Made", text: "Name at the Other End: Supplies\nFrom: Any Type\nTo: Person\nHow Many: Many to Many"),
        ])

        model.beginNew()
        model.fromType = "user.job"
        #expect(model.takeDrafts().isEmpty, "a choice of type alone is nothing typed")
    }

    @Test func aNewIDAvoidsEveryNameHeldAndFitsTheServersLimit() async {
        let calls = listing()
        calls.state.withLock {
            $0.linkTypes.append(
                OwnerLinkType(
                    id: "user.made_by", label: "Made By", reverseLabel: "Makes", cardinality: .manyToOne, fromTypes: ["*"], toTypes: ["*"],
                    shipped: false, reverseName: "user.supplies"))
        }
        let model = await loaded(calls)
        #expect(model.identifier(forNamed: "Supplies") == "user.supplies_2", "another type's reverse name is held")
        #expect(model.identifier(forNamed: "Supplied By") == "user.supplied_by_2")

        let long = String(repeating: "a", count: 200)
        let fitted = model.identifier(forNamed: long)
        #expect(fitted.utf8.count == LinksModel.identifierLimit)
        calls.state.withLock {
            $0.linkTypes.append(
                OwnerLinkType(id: fitted, label: long, reverseLabel: long, cardinality: .manyToMany, fromTypes: ["*"], toTypes: ["*"], shipped: false))
        }
        await model.load()
        let next = model.identifier(forNamed: long)
        #expect(next != fitted && next.utf8.count <= LinksModel.identifierLimit && next.hasSuffix("_2"))

        // A name another app registered since the list was read is avoided too.
        model.beginNew()
        model.name = "Ordered From"
        calls.state.withLock {
            $0.linkTypes.append(
                OwnerLinkType(
                    id: "user.ordered_from", label: "Ordered From", reverseLabel: "Ordered From", cardinality: .manyToMany, fromTypes: ["*"],
                    toTypes: ["*"], shipped: false))
        }
        await model.make()
        #expect(calls.state.withLock { $0.linkTypesMade.map(\.id) } == ["user.ordered_from_2"])
        #expect(model.identifier(forNamed: String(repeating: "a", count: 121) + " b").utf8.count <= LinksModel.identifierLimit)
    }

    @Test func anApprovalDropsTheSheetsRefusal() async {
        let bench = OwnerBench()
        let model = LinksModel(context: bench.context)
        await model.load()
        model.beginNew()
        model.name = "Supplied By"
        bench.calls.fail("registerLinkType", with: .notPermitted(ClientOwnerCalls.registeringLinkTypes))
        await model.make()
        #expect(model.makeNeedsPermission)

        bench.allowing = .cancelled
        await model.allowMore()
        #expect(model.makeNeedsPermission, "nothing was approved")

        bench.allowing = .allowed
        await model.allowMore()
        #expect(model.makeFailure == nil)
        #expect(model.isMaking && model.name == "Supplied By")
    }
}
