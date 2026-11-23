import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

/// Typing reaches the source as one body save per pause (`MarfaLibrary.TextPause`), and no text the person typed is
/// lost or sent on the wrong version while it waits.
@MainActor
@Suite(.hangLimit) struct MarfaTypingTests {
    typealias F = LibraryFixture
    typealias Pause = MarfaLibrary.TextPause

    /// A pause no test reaches, so only a hand-over or another write sends what waits.
    static let held = Pause(quiet: .seconds(600), cap: .seconds(600))

    private func loaded(_ pause: Pause = held) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for (id, text) in F.texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source, notices: Notices(), textPause: pause)
        source.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func aBurstOfReportsIsOneWriteWithTheLastText() async throws {
        let (library, source) = try await loaded(Pause(quiet: .milliseconds(50), cap: .seconds(600)))
        for text in ["Note body.", "Note body. A", "Note body. An", "Note body. And"] { library.updateBody(of: F.n1, to: text) }
        #expect(source.writes.isEmpty)
        #expect(library.body(of: F.n1) == ItemBody(id: F.n1, text: "Note body. And", version: ItemVersion(1)))
        #expect(library.hasUnreadSave(F.n1), "the copy has not bound what the waiting text links or embeds")

        #expect(await eventually { !source.writes.isEmpty })
        #expect(source.writes == [.editBody(F.n1, "Note body. And", base: ItemVersion(1), merge: .asRead)])
    }

    @Test func textTypedWhileAnEarlierWriteIsUnansweredGoesAfterTheAnswerAndFollowsIt() async throws {
        let (library, source) = try await loaded(Pause(quiet: .milliseconds(20), cap: .seconds(600)))
        library.updateBody(of: F.n1, to: "A")
        #expect(await eventually { source.writes.count == 1 })
        let first = try #require(source.submitted.first?.id)

        library.updateBody(of: F.n1, to: "AB")
        library.updateBody(of: F.n1, to: "ABC")
        // Many times the pause, in which nothing may be sent while the first write is unanswered.
        try await Task.sleep(for: .milliseconds(300))
        #expect(source.writes.count == 1)

        source.send(.taken(first))
        source.send(.answered(first, .accepted))
        #expect(await eventually { source.writes.count == 2 })
        #expect(source.writes.last == .editBody(F.n1, "ABC", base: ItemVersion(1), merge: .following))
        #expect(library.body(of: F.n1)?.text == "ABC")
    }

    @Test func finishingSendsWhatWaitsBeforeItWaitsForTheQueue() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Typed before quitting")
        source.queuing.withLock { $0 = true }
        let finishing = Task { await library.finish() }
        #expect(await eventually { source.writes == [.editBody(F.n1, "Typed before quitting", base: ItemVersion(1), merge: .asRead)] })
        #expect(source.queues.withLock { $0 } == 0, "the text is in the queue before the queue is waited on")
        source.queuing.withLock { $0 = false }
        await finishing.value
        #expect(source.queues.withLock { $0 } == 1)

        // A library being left closes after `finish`, so what was typed is in the queue the close reads.
        await source.close()
        #expect(source.writes.count == 1)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func textTypedWhileFinishingWaitsIsSentBeforeFinishingReturns() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Before")
        source.queuing.withLock { $0 = true }
        let finishing = Task { await library.finish() }
        #expect(await eventually { source.writes.count == 1 })
        library.updateBody(of: F.n1, to: "Before and after")
        source.queuing.withLock { $0 = false }
        await finishing.value
        #expect(source.writes.last == .editBody(F.n1, "Before and after", base: ItemVersion(1), merge: .following))
    }

    @Test func aPageHandingOverSendsWhatWaitsOutsideTheUndoItWaitsFor() async throws {
        typealias T = TypeChangeFixture
        func note(_ id: ItemID, _ title: String, version: Int64 = 1, type: TypeID = T.note) -> MarfaMac.Item {
            let date = Date(timeIntervalSince1970: 1_000_000)
            return MarfaMac.Item(
                id: id, type: type, title: title, titleRule: .property("title"),
                properties: [Property(key: "title", value: .string(title))], version: ItemVersion(version),
                created: date, modified: date)
        }
        let typed = ItemID("typed"), other = ItemID("other")
        let source = FakeItemSource()
        source.setBody("Agenda", of: typed)
        source.setBody("", of: other)
        let library = MarfaLibrary(source: source, notices: Notices(), textPause: Self.held)
        var handingOver: [(Bool) -> Void] = []
        library.handOverEdits = { handingOver.append($0) }
        source.send(.loaded(SourceSnapshot(items: [note(typed, "Typed"), note(other, "Other")], catalogue: T.catalogue)))
        try #require(await eventually { library.isLoaded })

        let undo = UndoManager()
        library.changeType([other], to: T.task, filling: [:], undoManager: undo)
        source.send(.upserted([note(other, "Other", version: 2, type: T.task)]))
        #expect(await eventually { library.item(other)?.type == T.task })

        library.updateBody(of: typed, to: "Agenda, more")
        undo.undo()
        try #require(handingOver.count == 1)
        // The page reports its last edit as it hands over.
        library.updateBody(of: typed, to: "Agenda, more and more")
        handingOver[0](true)
        #expect(source.writes == [
            .retype(other, T.task, [:], base: ItemVersion(1)),
            .editBody(typed, "Agenda, more and more", base: ItemVersion(1), merge: .asRead),
            .retype(other, T.note, [:], base: ItemVersion(2)),
        ])
        #expect(source.submitted[1].undoing == nil, "the text is no part of the undo")
        #expect(source.submitted[2].undoing != nil)
    }

    @Test func anotherWriteNamingTheItemGoesAfterTheTextTypedBeforeIt() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Typed, then tagged")
        library.addTag("later", to: [F.n1], undoManager: nil)
        #expect(source.writes == [
            .editBody(F.n1, "Typed, then tagged", base: ItemVersion(1), merge: .asRead),
            .tag(F.n1, "later", on: true),
        ])
    }

    /// Another device's text that lands while the person's waits is held aside, and the person's goes as typed on the
    /// version it was typed on, so the server merges the two or keeps the person's on a conflicted copy.
    @Test func anotherDevicesChangeDuringThePauseIsMergedAgainstWhatWasTyped() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Note body, mine")
        var theirs = try #require(library.item(F.n1))
        theirs.version = ItemVersion(2)
        source.setBody("Theirs", of: F.n1, version: 2)
        source.send(.upserted([theirs]))
        #expect(await eventually { library.item(F.n1)?.version == ItemVersion(2) })
        #expect(library.body(of: F.n1) == ItemBody(id: F.n1, text: "Note body, mine", version: ItemVersion(1)))

        library.sendWaitingText()
        #expect(source.writes == [.editBody(F.n1, "Note body, mine", base: ItemVersion(1), merge: .asRead)])
        let write = try #require(source.submitted.last?.id)

        // The server kept its own text and put the person's on a copy.
        var conflicted = theirs
        conflicted.sync = .conflicted(sibling: F.n2, fields: ["body"])
        source.send(.answered(write, .conflicted(sibling: F.n2, fields: ["body"])))
        source.send(.upserted([conflicted]))
        #expect(await eventually { library.body(of: F.n1)?.text == "Theirs" })
        #expect(library.body(of: F.n1)?.version == ItemVersion(2))

        // What the person types on the server's text is the first save on its version.
        library.updateBody(of: F.n1, to: "Theirs!")
        library.sendWaitingText()
        #expect(source.writes.last == .editBody(F.n1, "Theirs!", base: ItemVersion(2), merge: .asRead))
    }

    /// Offline, nothing is answered, so the cap alone sends the text to the copy's queue.
    @Test func textWaitsNoLongerThanTheCapWhileAnEarlierWriteIsNeverAnswered() async throws {
        let (library, source) = try await loaded(Pause(quiet: .milliseconds(20), cap: .milliseconds(300)))
        library.updateBody(of: F.n1, to: "A")
        #expect(await eventually { source.writes.count == 1 })
        library.updateBody(of: F.n1, to: "AB")
        #expect(await eventually { source.writes.count == 2 })
        #expect(source.writes.last == .editBody(F.n1, "AB", base: ItemVersion(1), merge: .following))
    }

    @Test func textTypedBackToWhatTheCopyHoldsSendsNothing() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Note body!")
        library.updateBody(of: F.n1, to: "Note body")
        #expect(library.body(of: F.n1) == ItemBody(id: F.n1, text: "Note body", version: ItemVersion(1)))
        #expect(!library.hasUnreadSave(F.n1))
        await library.finish()
        #expect(source.writes.isEmpty)

        // Another device's text is taken in again once nothing waits.
        source.setBody("Theirs", of: F.n1, version: 2)
        var theirs = try #require(library.item(F.n1))
        theirs.version = ItemVersion(2)
        source.send(.upserted([theirs]))
        #expect(await eventually { library.body(of: F.n1)?.text == "Theirs" })
    }

    @Test func textWaitingForAnItemPurgedMeanwhileIsGivenBack() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Typed as it was purged")
        source.send(.removed([F.n1]))
        #expect(await eventually { library.item(F.n1) == nil })
        library.sendWaitingText()
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.map(\.text) == ["Typed as it was purged"])
        #expect(library.notices.waiting.last?.message == "\(MarfaLibrary.cantChange) Your text is on the clipboard, so you can paste it back.")
    }

    /// A source that closes with text waiting takes no write, so the text goes back to the person, and no wait is left
    /// to fire into the closed source.
    @Test func textWaitingAsTheSourceClosesIsGivenBack() async throws {
        let (library, source) = try await loaded(Pause(quiet: .milliseconds(200), cap: .milliseconds(400)))
        library.updateBody(of: F.n1, to: "Typed as it closed")
        await source.close()
        #expect(await eventually { library.notices.waiting.map(\.text) == ["Typed as it closed"] })
        #expect(!library.hasUnreadSave(F.n1))
        // Past the cap, by which a wait left behind would have told the person again.
        try await Task.sleep(for: .milliseconds(600))
        #expect(library.notices.waiting.count == 1)
        #expect(source.writes.isEmpty)
    }
}
