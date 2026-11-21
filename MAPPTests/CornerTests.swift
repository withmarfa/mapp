import Foundation
import SwiftUI
import Testing
@testable import MAPP

/// What the window's bottom-right corner does to the view in front.
@MainActor
struct CornerTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func date(_ text: String) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    // MARK: Moving the calendar

    @Test func backAndForwardMoveBySevenDaysFromTheWeekThatHoldsTodayAndTodayComesBack() {
        let browser = Browser()
        let now = Self.date("2026-11-04")
        // From no day shown, a week on from the one that holds today, which begins on its Monday.
        browser.moveCalendar(by: 1, now: now, calendar: Self.calendar)
        #expect(browser.calendarDay == Self.calendar.startOfDay(for: Self.date("2026-11-09")))
        browser.moveCalendar(by: -1, now: now, calendar: Self.calendar)
        browser.moveCalendar(by: -1, now: now, calendar: Self.calendar)
        #expect(browser.calendarDay == Self.calendar.startOfDay(for: Self.date("2026-10-26")))
        browser.moveCalendar(by: nil, now: now, calendar: Self.calendar)
        #expect(browser.calendarDay == nil)
    }

    @Test func aWeekScrolledToAnyDayMovesBySevenDaysFromIt() {
        let browser = Browser()
        let now = Self.date("2026-11-04")
        browser.calendarDay = Self.calendar.startOfDay(for: Self.date("2026-11-12"))
        browser.moveCalendar(by: 1, now: now, calendar: Self.calendar)
        #expect(browser.calendarDay == Self.calendar.startOfDay(for: Self.date("2026-11-19")))
        browser.moveCalendar(by: -1, now: now, calendar: Self.calendar)
        browser.moveCalendar(by: -1, now: now, calendar: Self.calendar)
        #expect(browser.calendarDay == Self.calendar.startOfDay(for: Self.date("2026-11-05")))
    }

    @Test func aMonthShownAsAWeekStartsOnTheFirstDayOfItsWeek() {
        let browser = Browser()
        browser.changeCalendarScale(.month)
        browser.calendarDay = Self.date("2026-11-19")
        browser.changeCalendarScale(.week, calendar: Self.calendar)
        #expect(browser.calendarDay == Self.calendar.startOfDay(for: Self.date("2026-11-16")))
    }

    @Test func aKeyThatLeavesTheWeekShowsTheWeekHoldingTheNextDay() {
        let browser = Browser()
        browser.showCalendarDay(Self.date("2026-11-19"), calendar: Self.calendar)
        #expect(browser.calendarDay == Self.calendar.startOfDay(for: Self.date("2026-11-16")))
        browser.changeCalendarScale(.month)
        browser.showCalendarDay(Self.date("2026-12-02"), calendar: Self.calendar)
        #expect(browser.calendarDay == Self.calendar.startOfDay(for: Self.date("2026-12-02")))
    }

    @Test func inAMonthBackAndForwardMoveByMonths() {
        let browser = Browser()
        browser.changeCalendarScale(.month)
        let now = Self.date("2026-11-04")
        browser.moveCalendar(by: 1, now: now, calendar: Self.calendar)
        #expect(browser.calendarDay == Self.date("2026-12-04"))
        browser.moveCalendar(by: -1, now: now, calendar: Self.calendar)
        browser.moveCalendar(by: -1, now: now, calendar: Self.calendar)
        #expect(browser.calendarDay == Self.date("2026-10-04"))
    }

    @Test func choosingADayShowsItsWeekAndPutsTheCardAway() throws {
        let browser = Browser()
        browser.toggleCalendarMonth()
        #expect(browser.showsCalendarMonth)
        browser.chooseCalendarDay(Self.date("2026-11-19"), calendar: Self.calendar)
        let day = try #require(browser.calendarDay)
        let week = CalendarLayout.interval(of: browser.calendarScale, containing: day, calendar: Self.calendar)
        #expect(week.start == Self.calendar.startOfDay(for: Self.date("2026-11-16")))
        #expect(week.contains(Self.date("2026-11-19")))
        #expect(!browser.showsCalendarMonth)
    }

    @Test func theMonthCardClosesWhenTheLayoutChanges() {
        let browser = Browser()
        browser.viewMode = .calendar
        browser.toggleCalendarMonth()
        browser.viewMode = .list
        #expect(!browser.showsCalendarMonth)
    }

    // MARK: Room

    @Test func weekOrMonthFoldsBelowTheThreshold() {
        #expect(CalendarCorner.foldsScale(forWidth: CalendarCorner.foldsBelow - 1))
        #expect(!CalendarCorner.foldsScale(forWidth: CalendarCorner.foldsBelow))
        #expect(!CalendarCorner.foldsScale(forWidth: .infinity))
    }

    @Test func onlyTheLayoutsWithButtonsInTheCornerLeaveRoomForThem() {
        #expect(ItemViewMode.allCases.filter(\.hasCorner) == [.gallery, .timeline, .calendar])
        #expect(CornerMetrics.clearance(scale: 1) == CornerMetrics.height + 2 * WindowCorner<EmptyView, EmptyView>.inset)
    }

    @Test func theMonthCardFollowsEveryMoveOfTheCalendar() {
        let browser = Browser()
        let now = Self.date("2026-11-04")
        browser.moveCalendar(by: nil, now: now, calendar: Self.calendar)
        browser.moveCalendar(by: 1, now: now, calendar: Self.calendar)
        #expect(browser.calendarMoves == 2)
    }

    // MARK: The timeline and the gallery

    @Test func todayOnTheTimelineIsAskedForByCounting() {
        let browser = Browser()
        browser.requestTimelineToday()
        browser.requestTimelineToday()
        #expect(browser.timelineTodayRequests == 2)
    }

    @Test func theCornersCardSizeIsTheValueEditViewReads() {
        let browser = Browser()
        #expect(browser.cards.size == .medium)
        browser.setCardSize(.large)
        #expect(browser.cards.size == .large)
        browser.changeCards { $0.size = .small }
        #expect(browser.cards.size == .small)
        browser.setCardSize(.small)
        #expect(browser.cards.size == .small)
    }
}
