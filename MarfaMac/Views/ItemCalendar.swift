import AppKit
import SwiftUI

/// The calendar layout: a week of day columns with hours, or a month of days, with each item where its type's date puts
/// it (`CalendarLayout`). Choosing an item opens the right sidebar, as the timeline does. A selection that moves runs
/// the bodies of the cells that wrap an item and of no calendar: the layout is worked out here from the items alone.
struct ItemCalendar: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var daysSeen = 0
    @State private var keyboard = CalendarKeyboard()
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(WeekStart.key) private var weekStart = 0

    var body: some View {
        let _ = daysSeen
        let _ = weekStart
        let items = browser.filteredItems(in: library)
        let calendar = Calendar.chosenWeekStart
        let now = library.now()
        let anchor = browser.calendarDay ?? now
        let firstShown = CalendarLayout.firstDayShown(browser.calendarDay, now: now, calendar: calendar)
        let placed = CalendarLayout.entries(for: items, looks: browser.looks(in: library), catalogue: library.catalogue, calendar: calendar)
        let scale = browser.calendarScale
        let visible = scale == .week
            ? DateInterval(start: firstShown, end: calendar.date(byAdding: .day, value: 7, to: firstShown) ?? firstShown)
            : CalendarLayout.interval(of: scale, containing: anchor, calendar: calendar)

        Group {
            switch scale {
            case .week:
                CalendarWeekView(
                    entries: placed.entries, firstDay: firstShown, browser: browser, keyboard: keyboard, calendar: calendar,
                    format: dateFormat, now: now, choose: choose, open: open)
            case .month:
                let month = CalendarMonth.make(entries: placed.entries, around: anchor, calendar: calendar, now: now)
                CalendarMonthView(month: month, browser: browser, calendar: calendar, format: dateFormat, choose: choose, open: open)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused(pane, equals: .list)
        .onKeyPress(.return) {
            browser.openSelection() ? .handled : .ignored
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { press in
            guard !press.modifiers.contains(.command) else { return .ignored }
            let direction: CalendarNavigation.Direction =
                press.key == .upArrow ? .up : press.key == .downArrow ? .down : press.key == .leftArrow ? .left : .right
            let current = browser.selection.count == 1 ? browser.selection.first : nil
            let from = current.flatMap {
                CalendarNavigation.spot(of: $0, near: keyboard.day, in: placed.entries, visible: visible, calendar: calendar)
            }
            guard let next = CalendarNavigation.move(from: from, direction, in: placed.entries, visible: visible, calendar: calendar)
            else { return .ignored }
            if !visible.contains(next.day) { browser.showCalendarDay(next.day, calendar: calendar) }
            choose(next.id, next.day)
            keyboard.reveal = next
            return .handled
        }
        .onKeyPress(.escape) {
            browser.selection = []
            keyboard.day = nil
            return .handled
        }
        .searchStatus(browser)
        .overlay {
            if items.isEmpty {
                if browser.isSearching {
                    SearchEmptyState(browser: browser)
                } else {
                    PlaceEmptyState(browser: browser)
                }
            }
        }
        .filteredEmptyState(browser)
        .background(ChosenRowOpensSidebar(browser: browser))
        .accessibilityIdentifier("ItemCalendar")
        .onChange(of: browser.isSearchExpanded) {
            if !browser.isSearchExpanded { browser.focusRequest = .list }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
        }
    }

    /// Chooses an event on one of its days, which is where the arrow keys go on from.
    private func choose(_ id: ItemID, _ day: Date) {
        keyboard.day = day
        browser.selection = [id]
    }

    private func open(_ id: ItemID) { browser.open([id]) }
}
