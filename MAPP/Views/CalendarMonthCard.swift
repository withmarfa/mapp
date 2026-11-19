import SwiftUI

/// The month the corner's month button opens above its buttons: a small grid with the week the calendar shows marked in
/// gray and today in red. Choosing a day goes to its week and closes the card. Its arrows change the month the card
/// shows and leave the calendar where it is.
struct CalendarMonthCard: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    /// A day in the month the card shows, or nil while it follows the calendar.
    @State private var shown: Date?

    var body: some View {
        let calendar = Calendar.current
        let now = library.now()
        let current = browser.calendarDay ?? now
        let anchor = shown ?? current
        let month = CalendarMonth.make(entries: [], around: anchor, calendar: calendar, now: now)
        let marked = CalendarLayout.interval(of: .week, containing: current, calendar: calendar)
        VStack(spacing: 6) {
            HStack {
                Text(month.interval.start, format: .dateTime.month(.wide).year())
                    .interfaceFont(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Previous Month", systemImage: "chevron.left") { move(anchor, by: -1, calendar) }
                    .accessibilityIdentifier("CalendarMonthPrevious")
                Button("Next Month", systemImage: "chevron.right") { move(anchor, by: 1, calendar) }
                    .accessibilityIdentifier("CalendarMonthNext")
            }
            .labelStyle(.iconOnly)
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
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        dayButton(day, calendar: calendar)
                    }
                }
                .background {
                    if let start = week.first?.date, marked.contains(start) {
                        Capsule().fill(.primary.opacity(0.1))
                    }
                }
            }
        }
        .padding(14)
        .accessibilityIdentifier("CalendarMonthCard")
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
