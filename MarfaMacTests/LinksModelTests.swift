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

    @Test func aDeleteIsSentOnlyOnceTheOwnerAgrees() async {
        let calls = listing()
        let model = await loaded(calls)

        model.askToDelete("user.supplied_by")
        #expect(model.question?.id == "user.supplied_by")
        model.cancelDelete()
        await model.confirmDelete()
        #expect(!calls.calls.contains("deleteLinkType"))
        #expect(model.linkType("user.supplied_by") != nil)

        model.askToDelete("user.supplied_by")
        await model.confirmDelete()
        #expect(calls.calls.filter { $0 == "deleteLinkType" }.count == 1)
        #expect(model.linkType("user.supplied_by") == nil)
        #expect(model.deleted == "user.supplied_by")
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

    @Test func aRefusedDeleteLeavesTheListAsTheServerHoldsIt() async {
        let calls = listing()
        calls.state.withLock { $0.linkTypesInUse = ["user.supplied_by"] }
        let model = await loaded(calls)

        model.askToDelete("user.supplied_by")
        await model.confirmDelete()
        #expect(model.linkTypes == calls.state.withLock { $0.linkTypes })
        #expect(model.deleted == nil)
        #expect(model.deleteLine(for: "user.supplied_by") == "Items still link with Supplied By, so it was kept. Remove those links first.")

        calls.state.withLock { $0.linkTypesInUse = [] }
        calls.fail("deleteLinkType", with: .notPermitted("schema.write"))
        model.askToDelete("user.supplied_by")
        await model.confirmDelete()
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
}
