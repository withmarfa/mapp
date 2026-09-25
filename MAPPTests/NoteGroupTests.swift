import Foundation
import Testing
@testable import MAPP

struct NoteGroupTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    var now: Date { date(2026, 9, 25, hour: 18) }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func group(_ date: Date) -> NoteGroup {
        NoteGroup.group(for: date, now: now, calendar: calendar)
    }

    @Test func daysAreGroupedAsNotesGroupsThem() {
        #expect(group(date(2026, 9, 25, hour: 0)) == .today)
        #expect(group(date(2026, 9, 24, hour: 23)) == .yesterday)
        #expect(group(date(2026, 9, 23)) == .previous7Days)
        #expect(group(date(2026, 9, 18)) == .previous7Days)
        #expect(group(date(2026, 9, 17)) == .previous30Days)
        #expect(group(date(2026, 8, 26)) == .previous30Days)
    }

    @Test func olderNotesThisYearGroupByMonthAndEarlierYearsByYear() {
        #expect(group(date(2026, 8, 25)) == .month(DateComponents(year: 2026, month: 8)))
        #expect(group(date(2026, 1, 3)) == .month(DateComponents(year: 2026, month: 1)))
        #expect(group(date(2025, 12, 31)) == .year(2025))
    }

    @Test func pinnedNotesLeadAndTheRestFollowInDateSections() {
        let pinnedOld = Note(body: "Pinned", created: date(2026, 3, 1), isPinned: true)
        let today = Note(body: "Today", created: date(2026, 9, 25, hour: 9))
        let yesterday = Note(body: "Yesterday", created: date(2026, 9, 24))
        let sections = NoteGroup.sections(
            of: [today, yesterday, pinnedOld], sort: .dateEdited, pinnedFirst: true, now: now, calendar: calendar
        )
        #expect(sections.map(\.group) == [.pinned, .today, .yesterday])
        #expect(sections[0].notes == [pinnedOld])
    }

    @Test func withoutPinnedFirstPinnedNotesStayInTheirDateSection() {
        let pinned = Note(body: "Pinned", created: date(2026, 9, 25, hour: 9), isPinned: true)
        let sections = NoteGroup.sections(of: [pinned], sort: .dateEdited, pinnedFirst: false, now: now, calendar: calendar)
        #expect(sections.map(\.group) == [.today])
    }

    @Test func sortingByTitleListsNotesWithoutDateSections() {
        let a = Note(body: "Apples", created: date(2026, 9, 25))
        let b = Note(body: "Bread", created: date(2025, 1, 1))
        let sections = NoteGroup.sections(of: [a, b], sort: .title, pinnedFirst: true, now: now, calendar: calendar)
        #expect(sections.count == 1)
        #expect(sections[0].group == nil)
        #expect(sections[0].notes == [a, b])
    }

    @Test func sortingOrdersByTheChosenDateOrByTitle() {
        let older = Note(body: "Zebra", created: date(2026, 9, 1), modified: date(2026, 9, 25))
        let newer = Note(body: "apple", created: date(2026, 9, 20), modified: date(2026, 9, 21))
        #expect(NoteSort.dateEdited.sorted([newer, older]) == [older, newer])
        #expect(NoteSort.dateCreated.sorted([older, newer]) == [newer, older])
        #expect(NoteSort.title.sorted([older, newer]) == [newer, older])
    }
}
