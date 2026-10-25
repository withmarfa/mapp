import Foundation
import Testing
@testable import MAPP

/// The one way anything reaches the person: each notice waits, in order, until it is answered.
@MainActor struct NoticesTests {
    @Test func aNoticeWaitsBehindTheOneShownUntilThatIsAnswered() throws {
        let notices = Notices()
        notices.tell("Can’t Search", "The search failed.")
        notices.tell("Couldn’t Print Note", "The printer is gone.")
        #expect(notices.waiting.map(\.title) == ["Can’t Search", "Couldn’t Print Note"])

        notices.answered(try #require(notices.waiting.first))
        #expect(notices.waiting.map(\.title) == ["Couldn’t Print Note"])
    }

    @Test func theSameWordsWaitingAreNotToldTwice() {
        let notices = Notices()
        notices.tell("Can’t Read This Library", "The store is damaged.")
        notices.tell("Can’t Read This Library", "The store is damaged.")
        #expect(notices.waiting.count == 1)
    }

    @Test func textNotKeptIsGatheredUntilThePersonAnswers() throws {
        let notices = Notices()
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel")
        #expect(notices.newest?.title == "Couldn’t Save “Trip”")
        #expect(notices.newest?.text == "Book the hotel")
        #expect(notices.newest?.message == "MAPP closed the library before it could keep what you typed. Your text is on the clipboard, so you can paste it back.")

        notices.tell("Can’t Search", "The search failed.")
        notices.notKept("Couldn’t Save “Plan”", text: "Pack")
        #expect(notices.waiting.count == 2)
        let gathered = try #require(notices.waiting.first)
        #expect(gathered.title == "Some Changes Weren’t Saved")
        #expect(gathered.text == "Book the hotel\n\nPack")

        notices.answered(gathered)
        notices.notKept("Couldn’t Save “Plan”", text: "Rest")
        #expect(notices.waiting.map(\.text) == [nil, "Rest"])
    }

    @Test func textNotKeptForAReasonIsToldWithTheReasonAndOnlyThatReasonIsShared() {
        let notices = Notices()
        notices.notKept("Couldn’t Save “Trip”", text: "Book the hotel", reason: "This item can’t be changed now.")
        #expect(notices.newest?.message == "This item can’t be changed now. Your text is on the clipboard, so you can paste it back.")

        notices.notKept("Couldn’t Save “Trip”", text: "Pack", reason: "This item can’t be changed now.")
        #expect(notices.newest?.message == "This item can’t be changed now. Your text is on the clipboard, so you can paste it back.")

        notices.notKept("Couldn’t Save “Plan”", text: "Rest", reason: "Try again in a moment.")
        #expect(notices.newest?.title == "Some Changes Weren’t Saved")
        #expect(notices.newest?.text == "Book the hotel\n\nPack\n\nRest")
        #expect(notices.newest?.message == "MAPP couldn’t keep some of what you typed. Your text is on the clipboard, so you can paste it back.")
    }

    @Test func aChangeNotKeptWithNoTextAsksThePersonToMakeItAgain() {
        let notices = Notices()
        notices.notKept("Couldn’t Save Note", text: "")
        #expect(notices.newest?.text == nil)
        #expect(notices.newest?.message == "MAPP closed the library before it could keep your change. Make the change again.")
    }
}
