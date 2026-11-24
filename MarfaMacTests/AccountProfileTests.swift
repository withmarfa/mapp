import Foundation
import Synchronization
import Testing

@testable import MarfaMac

@MainActor
@Suite(.hangLimit) struct AccountProfileTests {
    private func loaded(_ bench: OwnerBench) async -> AccountModel {
        bench.calls.state.withLock { $0.profile.name = "Mira Castell" }
        let account = AccountModel(context: bench.context)
        await account.load()
        return account
    }

    @Test func aRefusedNameKeepsWhatWasTypedThroughAReadAgain() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        bench.calls.fail("setProfileName", with: .refused("The name can’t hold control characters."))
        account.nameDraft = "Mira Castell-Owen"
        await account.saveName()
        #expect(account.nameDraft == "Mira Castell-Owen")
        #expect(account.nameError != nil)
        await account.load()
        #expect(account.nameDraft == "Mira Castell-Owen")
        #expect(account.profile?.name == "Mira Castell")
    }

    @Test func aNameTypedWhileOneIsSentIsSentAfterIt() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        let gate = bench.calls.hold("setProfileName")
        account.nameDraft = "Mira C"
        let first = Task { await account.saveName() }
        #expect(await eventually { bench.calls.state.withLock { $0.waiting["setProfileName"] == 1 } })
        account.nameDraft = "Mira Castell-Owen"
        await account.saveName()
        gate.open()
        #expect(await eventually { bench.calls.state.withLock { $0.waiting["setProfileName"] == 1 } })
        gate.open()
        await first.value
        #expect(bench.calls.state.withLock { $0.namesSent } == ["Mira C", "Mira Castell-Owen"])
        #expect(account.nameDraft == "Mira Castell-Owen")
        #expect(account.profile?.name == "Mira Castell-Owen")
    }

    @Test func aNameNotSentIsHandedOverWhenSettingsCloses() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        bench.calls.fail("setProfileName", with: .unreachable)
        account.nameDraft = "Mira Castell-Owen"
        await account.saveName()
        #expect(account.takeDrafts() == [.typed(title: String(localized: "Name Not Changed"), text: "Mira Castell-Owen")])
    }
}
