import SwiftUI

/// The month the corner's month button opens above its buttons: a small grid with the week the calendar shows marked in
/// gray, nothing marked while the calendar shows a month, and today in red. Choosing a day goes to its week or month and
/// closes the card. Its arrows change the month the card shows and leave the calendar where it is, until the calendar
/// itself moves, when the card follows it.
struct CalendarMonthCard: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    /// A day in the month the card shows, or nil while it follows the calendar.
    @State private var shown: Date?
    @AppStorage(WeekStart.key) private var weekStart = 0

    var body: some View {
        let _ = weekStart
        let calendar = Calendar.chosenWeekStart
        let now = library.now()
        let current = browser.calendarDay ?? now
        let anchor = shown ?? current
        let month = CalendarMonth.make(entries: [], around: anchor, calendar: calendar, now: now)
        let marked = browser.calendarScale == .week ? Self.shownWeek(browser.calendarDay, now: now, calendar: calendar) : nil
        let markedDays = marked.map(month.marked(in:))
        VStack(spacing: 6) {
            HStack {
                Text(month.interval.start, format: .dateTime.month(.wide).year())
                    .interfaceFont(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { move(anchor, by: -1, calendar) } label: { arrow("chevron.left") }
                    .accessibilityLabel("Previous Month")
                    .accessibilityIdentifier("CalendarMonthPrevious")
                Button { move(anchor, by: 1, calendar) } label: { arrow("chevron.right") }
                    .accessibilityLabel("Next Month")
                    .accessibilityIdentifier("CalendarMonthNext")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            if let first = month.weeks.first {
                HStack(spacing: 0) {
                    ForEach(first) { day in
                        Text(day.date, format: .dateTime.weekday(.narrow))
                            .interfaceFont(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
            ForEach(month.weeks.indices, id: \.self) { index in
                let week = month.weeks[index]
                let marks = markedDays?[index] ?? []
                HStack(spacing: 0) {
                    ForEach(week.indices, id: \.self) { column in
                        dayButton(week[column], calendar: calendar)
                            .background { mark(column, in: marks) }
                    }
                }
            }
        }
        .padding(14)
        .accessibilityIdentifier("CalendarMonthCard")
        .onChange(of: browser.calendarDay) { shown = nil }
        .onChange(of: browser.calendarMoves) { shown = nil }
    }

    /// The seven days the calendar shows, from the first of them.
    private static func shownWeek(_ shown: Date?, now: Date, calendar: Calendar) -> DateInterval {
        let first = CalendarLayout.firstDayShown(shown, now: now, calendar: calendar)
        return DateInterval(start: first, end: calendar.date(byAdding: .day, value: 7, to: first) ?? first)
    }

    /// The gray behind a day of the marked week, rounded at the ends of the run it is part of in its row.
    @ViewBuilder private func mark(_ column: Int, in marks: [Bool]) -> some View {
        if marks.indices.contains(column), marks[column] {
            let opensRun = column == 0 || !marks[column - 1]
            let closesRun = column == marks.count - 1 || !marks[column + 1]
            UnevenRoundedRectangle(
                topLeadingRadius: opensRun ? 13 : 0, bottomLeadingRadius: opensRun ? 13 : 0,
                bottomTrailingRadius: closesRun ? 13 : 0, topTrailingRadius: closesRun ? 13 : 0, style: .continuous
            )
            .fill(.primary.opacity(0.1))
        }
    }

    private func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 24, height: 24)
            .contentShape(.rect)
    }

    @ViewBuilder private func dayButton(_ day: CalendarMonth.Day, calendar: Calendar) -> some View {
        if day.isInMonth {
            Button { browser.chooseCalendarDay(day.date, calendar: calendar) } label: {
                Text(day.date, format: .dateTime.day())
                    .interfaceFont(.callout.weight(day.isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(day.isToday ? Color.red : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide)))
            .accessibilityIdentifier("CalendarMonthDay")
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 26).accessibilityHidden(true)
        }
    }

    private func move(_ anchor: Date, by steps: Int, _ calendar: Calendar) {
        shown = CalendarLayout.moved(anchor, by: steps, scale: .month, calendar: calendar)
    }
}
