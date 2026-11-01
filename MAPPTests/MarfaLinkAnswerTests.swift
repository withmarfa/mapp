import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MAPP

/// What the core says a `[[link]]` names, asked through the library from the copy alone.
@MainActor
@Suite(.hangLimit)
struct MarfaLinkAnswerTests {
    private struct Scene {
        let store: TemporaryMarfaCopy
        let copy: WorkingCopy
        let source: MarfaSource
        let library: MarfaLibrary
        let ids: [String: ItemID]

        func id(_ name: String) -> ItemID { ids[name]! }

        func finish() async {
            await source.close()
            store.remove()
        }
    }

    /// Notes made with the titles given, in order; a repeated title makes a twin that `id(_:)` answers with the last.
    private static func scene(_ titles: [String]) async throws -> Scene {
        // A real copy: the in-memory one does not answer link candidates.
        let store = try TemporaryMarfaCopy()
        let copy = try await store.open()
        try await copy.declareTypes([[
            "id": "example.note", "label": "Note", "title_field": "title", "body_field": "body",
            "fields": ["title": ["type": "string"], "body": ["type": "string"]],
        ]])
        var ids: [String: ItemID] = [:]
        var all: [ItemID] = []
        for title in titles {
            let queued = try await copy.items.create(Draft(type: "example.note", properties: ["title": .string(title)]))
            let id = ItemID(try #require(queued.itemId))
            ids[title] = id
            all.append(id)
        }
        let source = MarfaSource(
            copy: copy, connection: SampleLibrary.connection, refreshing: ScriptedRefresh(status: ScriptedRefresh.complete()))
        source.events.yield(.paint)
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.isLoaded && all.allSatisfy { library.item($0) != nil } })
        return Scene(store: store, copy: copy, source: source, library: library, ids: ids)
    }

    @Test func aNameOneHeldNoteAnswersToStaysUnresolvedBecauseTheCopyHoldsASliceButAnIdentityIsBound() async throws {
        let scene = try await Self.scene(["Reader", "Plan"])
        let plan = scene.id("Plan")
        let answers = try #require(await scene.library.linkAnswers(of: ["Plan", "plan", "Nowhere", plan.rawValue + "|Plan"], in: scene.id("Reader")))
        #expect(answers.map(\.state) == [.unresolved, .unresolved, .unresolved, .bound], "case does not matter to the core")
        #expect(answers[0].candidates == [plan] && answers[1].candidates == [plan])
        #expect(answers[0].names(plan) && !answers[0].isMissing, "answered to by this note alone")
        #expect(answers[2].isMissing && answers[2].item == nil)
        #expect(answers[3].item == plan && answers[3].names(plan))
        await scene.finish()
    }

    @Test func aLinkTwoNotesAnswerToIsAmbiguousAndOffersBoth() async throws {
        let scene = try await Self.scene(["Reader", "Twin", "Twin"])
        let answer = try #require(await scene.library.linkAnswers(of: ["Twin"], in: scene.id("Reader"))?.first)
        #expect(answer.state == .ambiguous && answer.item == nil)
        #expect(Set(answer.candidates).count == 2 && !answer.isMissing)
        await scene.finish()
    }

    @Test func aBackslashIsPartOfTheNameNotAnEscape() async throws {
        let scene = try await Self.scene(["Reader", "back\\slash", "A\\"])
        let answers = try #require(await scene.library.linkAnswers(of: ["back\\slash", "A\\|B", "backslash"], in: scene.id("Reader")))
        #expect(answers[0].candidates == [scene.id("back\\slash")])
        // `A\|B` is the name `A\` with the alias `B`: the bar still separates, and the backslash stays in the name.
        #expect(answers[1].candidates == [scene.id("A\\")])
        #expect(answers[2].isMissing)
        #expect(await scene.library.bodyLink(to: scene.id("back\\slash"), in: scene.id("Reader")) == "[[back\\slash]]")
        await scene.finish()
    }

    @Test func aNoteInTheBinIsNotWhatALinkNames() async throws {
        let scene = try await Self.scene(["Reader", "Plan"])
        _ = try await scene.copy.items.delete(scene.id("Plan").rawValue)
        try #require(await eventually { scene.library.item(scene.id("Plan"))?.state == .trashed })
        let answer = try #require(await scene.library.linkAnswers(of: ["Plan"], in: scene.id("Reader"))?.first)
        #expect(answer.isMissing)
        await scene.finish()
    }

    @Test func aNameAskedWithNoNoteBindsNothingAndANoteNotHeldIsNeverAsked() async throws {
        let scene = try await Self.scene(["Reader", "Plan"])
        let named = try #require(await scene.library.linkAnswers(of: ["Plan", scene.id("Plan").rawValue], in: nil))
        #expect(named[0].state == .unresolved && named[0].candidates == [scene.id("Plan")])
        #expect(named[1].state == .bound && named[1].item == scene.id("Plan"))
        #expect(await scene.library.linkAnswers(of: ["Plan"], in: ItemID("not-held")) == nil, "never guessed")
        await scene.finish()
    }

    @Test func aTitleThatTwoNotesGoByIsLinkedByIdentityAndNotSuggested() async throws {
        let scene = try await Self.scene(["Reader", "Plan", "Plan", "Plan B"])
        let first = try #require(scene.library.items(in: .allNotes).first { $0.title == "Plan" })
        let link = try #require(await scene.library.bodyLink(to: first.id, in: scene.id("Reader")))
        #expect(link == "[[\(first.id.rawValue)|Plan]]")
        let names = await scene.library.noteNames(matching: "plan", in: scene.id("Reader"), using: NoteLinks.Index())
        #expect(names == ["Plan B"])
        #expect(await scene.library.bodyLink(to: scene.id("Plan B"), in: scene.id("Reader")) == "[[Plan B]]")
        await scene.finish()
    }
}
