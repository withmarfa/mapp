import Foundation
import Testing
@testable import MarfaMac

/// What the new-item line reads in typed words, with the locale and time zone set, so no rule depends on this Mac's.
@Suite
struct NewItemTextTests {
    static let zone = TimeZone(identifier: "Europe/London")!
    /// Wednesday 25 November 2026, 10:00 in London.
    static let now = Date(timeIntervalSince1970: 1_795_600_800)

    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static func day(_ text: String, _ locale: String) -> NewItemText.FoundDay? {
        NewItemText.day(in: text, now: now, calendar: calendar(), locale: Locale(identifier: locale))
    }

    static func ymd(_ date: Date) -> [Int] {
        let parts = calendar().dateComponents([.year, .month, .day], from: date)
        return [parts.year ?? 0, parts.month ?? 0, parts.day ?? 0]
    }

    @Test func theFixedMomentIsAWednesdayMorningInLondon() {
        let parts = Self.calendar().dateComponents([.weekday, .hour, .day], from: Self.now)
        #expect(parts.weekday == 4 && parts.hour == 10 && parts.day == 25)
    }

    // MARK: Days

    @Test(arguments: ["en_GB", "en_US"])
    func aWeekdayDayAndMonthAreReadInEitherEnglish(_ locale: String) throws {
        let found = try #require(Self.day("Call Sam Fri 27 Nov", locale))
        #expect(found.phrase == "Fri 27 Nov")
        #expect(Self.ymd(found.date) == [2026, 11, 27])
        #expect(!found.hasTime)
    }

    @Test func aNumericDayIsReadInTheOrderTheLocaleWritesIt() throws {
        let british = try #require(Self.day("Send invoice 27/11", "en_GB"))
        #expect(british.phrase == "27/11")
        #expect(Self.ymd(british.date) == [2026, 11, 27])

        let american = try #require(Self.day("Send invoice 11/27", "en_US"))
        #expect(Self.ymd(american.date) == [2026, 11, 27])

        #expect(Self.day("Send invoice 27/11", "en_US") == nil, "there is no 27th month")
        let early = try #require(Self.day("Pay rent 3/4", "en_GB"))
        #expect(Self.ymd(early.date) == [2027, 4, 3], "a day with no year that has passed is next year's")
    }

    @Test func germanNamesAndDotsAreRead() throws {
        let named = try #require(Self.day("Anruf Fr., 27. Nov.", "de_DE"))
        #expect(Self.ymd(named.date) == [2026, 11, 27])
        let numeric = try #require(Self.day("Rechnung 27.11.", "de_DE"))
        #expect(Self.ymd(numeric.date) == [2026, 11, 27])
    }

    @Test func aTimeAfterTheDayIsKeptInTheZone() throws {
        let found = try #require(Self.day("Dentist 27/11 14:30", "en_GB"))
        #expect(found.phrase == "27/11 14:30")
        #expect(found.hasTime)
        let parts = Self.calendar().dateComponents([.hour, .minute], from: found.date)
        #expect(parts.hour == 14 && parts.minute == 30)

        let counted = try #require(Self.day("Print Fri 27 Nov 3 copies", "en_GB"))
        #expect(counted.phrase == "Fri 27 Nov", "a bare number is no hour")
    }

    @Test func aWeekdayAloneIsTheNextOne() throws {
        let found = try #require(Self.day("Review Friday", "en_GB"))
        #expect(Self.ymd(found.date) == [2026, 11, 27])
        let today = try #require(Self.day("Review Wednesday", "en_GB"))
        #expect(Self.ymd(today.date) == [2026, 11, 25], "today's weekday is today")
    }

    @Test func wordsThatNameNoDayStayText() {
        #expect(Self.day("Plant seeds in May", "en_GB") == nil)
        #expect(Self.day("Issue #12", "en_GB") == nil)
        #expect(Self.day("Read 3 chapters", "en_GB") == nil)
        #expect(Self.day("sat on the step", "en_GB") == nil, "a short name inside a sentence is not a weekday")
    }

    static func removingDay(_ text: String, _ locale: String = "en_GB") -> String? {
        Self.day(text, locale).map { NewItemText.removing([$0.range], from: text) }
    }

    @Test func theDaysWordsLeaveTheTitle() {
        #expect(Self.removingDay("Call Sam Fri 27 Nov about rent") == "Call Sam about rent")
    }

    @Test func onlyTheWordsMatchedLeaveNotTheFirstTextLikeThem() {
        #expect(Self.removingDay("Read Saturn data Sat") == "Read Saturn data ")
        #expect(Self.removingDay("Fri 27 Nov: Fri report", "en_US") == ": Fri report")
    }

    @Test(arguments: ["en_GB", "en_US"])
    func nextAndAWeekdayLeaveTogether(_ locale: String) throws {
        let found = try #require(Self.day("Call next Friday", locale))
        #expect(found.phrase == "next Friday")
        #expect(Self.removingDay("Call next Friday", locale) == "Call ")
    }

    @Test(arguments: ["en_GB", "en_US"])
    func aDayNeedsWholeWordsAndAPossessiveIsNone(_ locale: String) {
        #expect(Self.day("Send Friday's report", locale) == nil)
        #expect(Self.day("Send Friday’s report", locale) == nil)
        #expect(Self.day("Fix Saturnalia lights", locale) == nil)
        #expect(Self.day("Plan Mondayish", locale) == nil)
    }

    // MARK: Tags

    /// The tags read in `text`, and the text with their words taken out, as Add does.
    static func taking(_ text: String, finishing: Bool, refuses: (String) -> Bool = { _ in false }) -> (tags: [String], text: String) {
        let found = NewItemText.tags(in: text, finishing: finishing, refuses: refuses)
        return (found.map(\.tag), NewItemText.removing(found.map(\.range), from: text))
    }

    @Test func aFinishedTagIsReadWhereItStands() {
        let typing = Self.taking("Call #work about it", finishing: false)
        #expect(typing.tags == ["work"])
        #expect(typing.text == "Call about it")
        #expect(NewItemText.tags(in: "Call #work about it", finishing: false).map(\.range) == [5..<10])

        #expect(Self.taking("Call #wor", finishing: false).tags.isEmpty, "a tag still being typed is not read")
        #expect(Self.taking("Call #work", finishing: true).tags == ["work"])
    }

    @Test func aFullStopAfterATagIsTheSentences() {
        let taken = Self.taking("Buy milk #home. Then call", finishing: true)
        #expect(taken.tags == ["home"])
        #expect(taken.text == "Buy milk. Then call")
    }

    @Test func eachTagIsReadWhereItStandsAndOnlyItsWordsLeave() {
        let taken = Self.taking("#home first. Then #home. And #work", finishing: true)
        #expect(taken.tags == ["home", "home", "work"])
        #expect(taken.text == "first. Then. And ")
    }

    @Test func numbersAndCodeStayText() {
        for text in ["Issue #12 ", "Learn C# today", "Win #1st prize "] {
            let taken = Self.taking(text, finishing: true)
            #expect(taken.tags.isEmpty, "\(text)")
            #expect(taken.text == text)
        }
        let refused = Self.taking("Pin #favorite ", finishing: true) { $0 == "favorite" }
        #expect(refused.tags.isEmpty && refused.text == "Pin #favorite ")
    }

    @Test func aMarkStartsAWordOnlyAfterASpace() {
        #expect(NewItemText.typing(in: "Plan #ho") == NewItemText.Typing(mark: .tag, query: "ho", before: "Plan "))
        #expect(NewItemText.typing(in: "Ask @Ali") == NewItemText.Typing(mark: .parent, query: "Ali", before: "Ask "))
        #expect(NewItemText.typing(in: "/pri") == NewItemText.Typing(mark: .property, query: "pri", before: ""))
        #expect(NewItemText.typing(in: "and/or") == nil)
        #expect(NewItemText.typing(in: "mail a@b") == nil)
        #expect(NewItemText.typing(in: "Issue #12") == nil)
        #expect(NewItemText.typing(in: "Plan #home ") == nil)
    }

    // MARK: Web addresses

    @Test func onlyAWholeWebAddressIsOne() {
        #expect(NewItemText.webAddress(" https://example.com/a?b=1 \n")?.absoluteString == "https://example.com/a?b=1")
        #expect(NewItemText.webAddress("http://example.com") != nil)
        #expect(NewItemText.webAddress("see https://example.com") == nil)
        #expect(NewItemText.webAddress("ftp://example.com") == nil)
        #expect(NewItemText.webAddress("example.com") == nil)
        #expect(NewItemText.webAddress("https://") == nil)
    }
}
