import Foundation
import Testing
@testable import MarfaMac

/// The one way anything reaches the person: each notice waits, in order, until it is answered.
@MainActor struct NoticesTests {
    /// Stands in for the clipboard, recording each text written to it.
    @MainActor final class Clipboard {
        var written: [String] = []
        func write(_ text: String) { written.append(text) }
    }

    @Test func aNoticeWaitsBehindTheOneShownUntilThatIsAnswered() throws {
        let notices = Notices()
        notices.tell("Can’t Search", "The search failed.")
        notices.tell("Couldn’t Print Item", "The printer is gone.")
        #expect(notices.waiting.map(\.title) == ["Can’t Search", "Couldn’t Print Item"])

        notices.answered(try #require(notices.waiting.first).id)
        #expect(notices.waiting.map(\.title) == ["Couldn’t Print Item"])
    }

    @Test func theSameWordsWaitingAreNotToldTwiceButTheTellIsCounted() {
        let notices = Notices()
        notices.tell("Can’t Read This Library", "The store is damaged.")
        notices.tell("Can’t Read This Library", "The store is damaged.")
        #expect(notices.waiting.count == 1)
        #expect(notices.told == 2)

        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")
        notices.notKept("Couldn’t Save “Trip”", text: "Pack")
        #expect(notices.waiting.count == 2)
        #expect(notices.told == 4)
    }

    @Test func textNotKeptIsGatheredUntilItIsShown() throws {
        let notices = Notices()
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")
        #expect(notices.waiting.last?.title == "Couldn’t Save “Trip”")
        #expect(notices.waiting.last?.text == "Book the hotel")
        #expect(notices.waiting.last?.message == "The app closed the library before it could keep what you typed. Your text is on the clipboard, so you can paste it back.")
        let id = try #require(notices.waiting.first?.id)

        notices.tell("Can’t Search", "The search failed.")
        notices.notKept("Couldn’t Save “Plan”", text: "Pack")
        #expect(notices.waiting.count == 2)
        let gathered = try #require(notices.waiting.first)
        #expect(gathered.id == id, "a notice keeps its identity as more gathers into it")
        #expect(gathered.title == "Some Changes Weren’t Saved")
        #expect(gathered.text == "Book the hotel\n\nPack")

        notices.answered(id)
        #expect(notices.waiting.map(\.title) == ["Can’t Search"], "answering a notice that gathered more removes it")
        notices.notKept("Couldn’t Save “Plan”", text: "Rest")
        #expect(notices.waiting.map(\.text) == [nil, "Rest"])
    }

    @Test func aNoticeThatStandsAloneKeepsItsWordsAndGathersNothing() throws {
        let notices = Notices()
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")
        notices.notKept("Key Not Copied", text: nil, reason: "The key was made.", standsAlone: true)
        notices.notKept("Couldn’t Save “Plan”", text: "Pack")
        #expect(notices.waiting.map(\.title) == ["Some Changes Weren’t Saved", "Key Not Copied"])
        #expect(notices.waiting.last?.message == "The key was made.")
        #expect(notices.waiting.first?.text == "Book the hotel\n\nPack")
        #expect(notices.holdsQuit)
    }

    @Test func textNotKeptForAReasonIsToldWithTheReasonAndOnlyThatReasonIsShared() {
        let notices = Notices()
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel", reason: "This item can’t be changed now.")
        #expect(notices.waiting.last?.message == "This item can’t be changed now. Your text is on the clipboard, so you can paste it back.")

        notices.notKept("Couldn’t Save “Trip”", text: "Pack", reason: "This item can’t be changed now.")
        #expect(notices.waiting.last?.message == "This item can’t be changed now. Your text is on the clipboard, so you can paste it back.")

        notices.notKept("Couldn’t Save “Plan”", text: "Rest", reason: "Try again in a moment.")
        #expect(notices.waiting.last?.title == "Some Changes Weren’t Saved")
        #expect(notices.waiting.last?.text == "Book the hotel\n\nPack\n\nRest")
        #expect(notices.waiting.last?.message == "The app couldn’t keep some of what you typed. Your text is on the clipboard, so you can paste it back.")
    }

    @Test func aChangeNotKeptWithNoTextAsksThePersonToMakeItAgain() {
        let notices = Notices()
        notices.notKept("Couldn’t Save Item", text: "")
        #expect(notices.waiting.last?.text == nil)
        #expect(notices.waiting.last?.message == "The app closed the library before it could keep your change. Make the change again.")
    }

    @Test func aNoticeIsShownInOneWindowOnly() throws {
        let notices = Notices()
        let clipboard = Clipboard()
        let front = UUID(), other = UUID()
        notices.tell("Can’t Search", "The search failed.")

        let shown = try #require(notices.show(in: front, copying: clipboard.write))
        #expect(shown.title == "Can’t Search")
        #expect(notices.show(in: other, copying: clipboard.write) == nil, "another window that becomes key shows nothing")
        #expect(notices.show(in: front, copying: clipboard.write)?.id == shown.id, "the window showing it keeps it")

        notices.released(by: other)
        #expect(notices.show(in: other, copying: clipboard.write) == nil, "only the showing window releases it")
        notices.released(by: front)
        #expect(notices.show(in: other, copying: clipboard.write)?.id == shown.id, "a window that closes unanswered hands it on")

        notices.answered(shown.id)
        #expect(notices.waiting.isEmpty)
        #expect(notices.show(in: other, copying: clipboard.write) == nil)
    }

    @Test func textGoesToTheClipboardOnceWhenItIsShown() throws {
        let notices = Notices()
        let clipboard = Clipboard()
        let front = UUID(), other = UUID()
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")
        #expect(clipboard.written.isEmpty, "nothing reaches the clipboard before the person is told")

        let shown = try #require(notices.show(in: front, copying: clipboard.write))
        #expect(clipboard.written == ["Book the hotel"])
        _ = notices.show(in: front, copying: clipboard.write)
        _ = notices.show(in: other, copying: clipboard.write)
        #expect(clipboard.written == ["Book the hotel"], "showing it again, or in another window, writes nothing over what the person copied since")

        notices.released(by: front)
        #expect(notices.show(in: other, copying: clipboard.write)?.id == shown.id)
        #expect(clipboard.written == ["Book the hotel"])
    }

    @Test func textNotKeptWhileANoticeIsShownWaitsBehindItAndOverwritesNothing() throws {
        let notices = Notices()
        let clipboard = Clipboard()
        let front = UUID()
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")
        let shown = try #require(notices.show(in: front, copying: clipboard.write))

        notices.notKept("Couldn’t Save “Plan”", text: "Pack")
        notices.notKept("Couldn’t Save “Plan”", text: "Rest")
        #expect(notices.waiting.first == shown, "the notice shown does not change under the person")
        #expect(notices.waiting.map(\.text) == ["Book the hotel", "Pack\n\nRest"], "later text gathers into a notice of its own")
        _ = notices.show(in: front, copying: clipboard.write)
        #expect(clipboard.written == ["Book the hotel"], "the text shown stays on the clipboard until the person answers")

        notices.answered(shown.id)
        let next = try #require(notices.show(in: front, copying: clipboard.write))
        #expect(next.text == "Pack\n\nRest")
        #expect(clipboard.written == ["Book the hotel", "Pack\n\nRest"])
    }

    @Test func textNotKeptAfterItsNoticeWasShownOnceIsToldAgainSeparately() throws {
        let notices = Notices()
        let clipboard = Clipboard()
        let front = UUID(), other = UUID()
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")
        _ = try #require(notices.show(in: front, copying: clipboard.write))
        notices.released(by: front)

        notices.notKept("Couldn’t Save “Plan”", text: "Pack")
        #expect(notices.waiting.map(\.text) == ["Book the hotel", "Pack"])
        let first = try #require(notices.show(in: other, copying: clipboard.write))
        notices.answered(first.id)
        _ = try #require(notices.show(in: other, copying: clipboard.write))
        #expect(clipboard.written == ["Book the hotel", "Pack"])
    }

    @Test func quittingTellsTextNoWindowHasShown() throws {
        let notices = Notices()
        let clipboard = Clipboard()
        notices.tell("Can’t Search", "The search failed.")
        #expect(!notices.holdsQuit, "a notice with nothing at stake does not hold the quit")
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")
        #expect(notices.holdsQuit)

        var presented: [String] = []
        let quits = notices.tellBeforeQuitting(copying: clipboard.write) { presented.append($0.title) }
        #expect(quits)
        #expect(presented == ["Can’t Search", "Couldn’t Save “Trip”"], "told in order, up to the last text not kept")
        #expect(clipboard.written == ["Book the hotel"])
        #expect(!notices.holdsQuit)
        #expect(notices.waiting.isEmpty)
    }

    @Test func quittingWaitsForAWindowAlreadyShowingANotice() throws {
        let notices = Notices()
        let clipboard = Clipboard()
        notices.tell("Can’t Search", "The search failed.")
        _ = try #require(notices.show(in: UUID(), copying: clipboard.write))
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")

        var presented: [String] = []
        #expect(!notices.tellBeforeQuitting(copying: clipboard.write) { presented.append($0.title) })
        #expect(presented.isEmpty, "the window showing a notice tells the rest after it")
        #expect(clipboard.written.isEmpty)
        #expect(notices.holdsQuit)
    }

    @Test func quittingWithTextAlreadyShownGoesAhead() throws {
        let notices = Notices()
        let clipboard = Clipboard()
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")
        _ = try #require(notices.show(in: UUID(), copying: clipboard.write))
        #expect(!notices.holdsQuit)
        #expect(notices.tellBeforeQuitting(copying: clipboard.write) { _ in Issue.record("nothing is left to tell") })
    }

    @Test func aWithdrawnNoticeIsNotToldUnlessAWindowShowedIt() throws {
        let notices = Notices()
        notices.notKept("Typing Might Be Missing", text: nil, reason: "Check it when it shows again.", standsAlone: true)
        notices.notKept("Typing Might Be Missing", text: nil, reason: "Close the window and open it again.", standsAlone: true)
        notices.withdraw(try #require(notices.waiting.first).id)
        #expect(notices.waiting.map(\.message) == ["Close the window and open it again."])

        let window = UUID()
        let shown = try #require(notices.show(in: window) { _ in })
        notices.withdraw(shown.id)
        #expect(notices.waiting.map(\.id) == [shown.id], "the person may be reading it")
        #expect(notices.shownIn == window)
    }
}

extension Notices {
    /// Answers every notice waiting, as a person dismissing each alert in turn would.
    func answerAll() {
        for notice in waiting { answered(notice.id) }
    }
}

/// A key the server refuses while the copy is open leaves the windows showing the library, so its notice is the only
/// sign and has to lead to the way out.
@Suite(.hangLimit)
@MainActor struct RefusedKeyNoticeTests {
    @Test func aRefusedKeyIsToldWithTheWayToLibrarySettings() async throws {
        let source = FakeItemSource()
        let notices = Notices()
        let library = MarfaLibrary(source: source, notices: notices)
        source.send(.unavailable(SourceFailure(kind: .denied, message: MarfaSync.keyRefused)))
        #expect(await eventually { !notices.waiting.isEmpty })

        let notice = try #require(notices.waiting.first)
        #expect(notice.action == .openSettings(.connection))
        #expect(notice.message == MarfaSync.keyRefused)
        #expect(notice.message.contains("disconnect"), "the words say Settings can start again")
        _ = library
    }

    @Test func otherLibraryFailuresAndOrdinaryNoticesOfferNothing() async throws {
        let source = FakeItemSource()
        let notices = Notices()
        let library = MarfaLibrary(source: source, notices: notices)
        source.send(.unavailable(SourceFailure(kind: .failed, message: "The store is damaged.")))
        #expect(await eventually { !notices.waiting.isEmpty })
        notices.tell("Can’t Search", "The search failed.")
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")

        #expect(notices.waiting.count == 3)
        #expect(notices.waiting.allSatisfy { $0.action == nil })
        _ = library
    }

    @Test func theSameWordsWithAndWithoutAnActionAreTwoNotices() {
        let notices = Notices()
        notices.tell("Title", "Message", action: .openSettings(.connection))
        notices.tell("Title", "Message", action: .openSettings(.connection))
        notices.tell("Title", "Message")
        #expect(notices.waiting.map(\.action) == [.openSettings(.connection), nil])
    }
}
