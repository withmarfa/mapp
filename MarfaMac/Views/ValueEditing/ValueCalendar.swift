import SwiftUI

/// A month drawn across the panel's width in the panel's own look: days 26 points across, the chosen day in a dark gray
/// circle, today's number in red, days of the neighbouring months dimmed. The system's graphical picker keeps its own
/// size and a grey ground, so it cannot be fitted to the panel.
struct ValueCalendar: View {
    let selected: Date?
    let today: Date
    let calendar: Calendar
    let scale: CGFloat
    let choose: (Date) -> Void
    @State private var shown: Date

    init(selected: Date?, today: Date, calendar: Calendar, scale: CGFloat, choose: @escaping (Date) -> Void) {
        self.selected = selected
        self.today = today
        self.calendar = calendar
        self.scale = scale
        self.choose = choose
        _shown = State(initialValue: selected ?? today)
    }

    private var monthStart: Date { calendar.dateInterval(of: .month, for: shown)?.start ?? shown }

    private var days: [Date] {
        let first = monthStart
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let weeks = (offset + count + 6) / 7
        let start = calendar.date(byAdding: .day, value: -offset, to: first) ?? first
        return (0..<weeks * 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func step(_ months: Int) {
        shown = calendar.date(byAdding: .month, value: months, to: monthStart) ?? shown
    }

    var body: some View {
        VStack(spacing: 4 * scale) {
            HStack(spacing: 0) {
                // The month is never cut: the arrows give way to it.
                Text(monthStart, format: .dateTime.month(.wide).year())
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4 * scale)
                nav("chevron.left", "Previous Month") { step(-1) }
                nav("circle.fill", "This Month", size: 6) { shown = today }
                nav("chevron.right", "Next Month") { step(1) }
            }
            .padding(.leading, 8 * scale)
            .padding(.trailing, 2 * scale)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2 * scale), count: 7), spacing: 2 * scale) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.system(size: 11 * scale, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 20 * scale)
                }
                ForEach(days, id: \.self) { day in
                    ValueCalendarDay(day: day, inMonth: calendar.isDate(day, equalTo: monthStart, toGranularity: .month),
                              isSelected: selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false,
                              isToday: calendar.isDate(today, inSameDayAs: day), calendar: calendar, scale: scale) { choose(day) }
                }
            }
        }
        .padding(.horizontal, 2 * scale)
        .onChange(of: selected) { if let selected { shown = selected } }
    }

    private func nav(_ symbol: String, _ label: LocalizedStringKey, size: CGFloat = 11, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * scale, weight: .semibold))
                .frame(width: 18 * scale, height: 24 * scale)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
    }
}

private struct ValueCalendarDay: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let calendar: Calendar
    let scale: CGFloat
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    /// Red for today, the one color a day takes; the chosen day is gray, never the accent.
    private static let todayRed = Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255)

    private var ink: Color { scheme == .dark ? .white : .black }

    var body: some View {
        Button(action: action) {
            Text(verbatim: String(calendar.component(.day, from: day)))
                .font(.system(size: 13 * scale, weight: isSelected || isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(width: 26 * scale, height: 26 * scale)
                .background(isSelected ? ink.opacity(0.72) : hovered ? SelectionLooks.hover(for: scheme) : .clear, in: .circle)
                .contentShape(.circle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(scheme == .dark ? Color.black : Color.white) }
        if isToday { return AnyShapeStyle(Self.todayRed) }
        return inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
    }
}
