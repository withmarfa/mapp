import AppKit
import SwiftUI

/// The calendar layout: a week of day columns with hours, or a month of days, with each item where its type's date puts
/// it (`CalendarLayout`). Choosing an item opens the right sidebar, as the timeline does. A selection that moves runs
/// the bodies of the cells that wrap an item and of no calendar: the browser works the layout out from the items alone.
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
        let calendar = Calendar.chosenWeekStart
        Group {
            if let placing = browser.calendarPlacing(in: library, calendar: calendar) {
                content(placing, calendar: calendar)
            } else {
                PlaceProgress()
            }
        }
        .onClockChange { daysSeen += 1 }
    }

    private func content(_ placed: Browser.CalendarPlacing, calendar: Calendar) -> some View {
        let now = library.now()
        let anchor = browser.calendarDay ?? now
        let firstShown = CalendarLayout.firstDayShown(browser.calendarDay, now: now, calendar: calendar)
        let scale = browser.calendarScale
        let visible = scale == .week
            ? DateInterval(start: firstShown, end: calendar.date(byAdding: .day, value: 7, to: firstShown) ?? firstShown)
            : CalendarLayout.interval(of: scale, containing: anchor, calendar: calendar)
        let drawn = CalendarLayout.drawn(scale, firstShown: firstShown, anchor: anchor, calendar: calendar)
        // Only a week can hide its weekend: the month keeps all seven days, so an item on one stays reachable there.
        let skipsWeekends = scale == .week && !browser.calendarChoices.showsWeekends
        let hiddenOnWeekend = skipsWeekends
            ? CalendarLayout.ids(in: placed.entries, within: drawn).count
                - CalendarLayout.ids(in: placed.entries, within: drawn, weekends: false, calendar: calendar).count
            : 0

        return Group {
            switch scale {
            case .week:
                CalendarWeekView(
                    entries: placed.entries, firstDay: firstShown, browser: browser, keyboard: keyboard, calendar: calendar,
                    format: dateFormat, now: now, choose: choose, open: open)
                    .id(skipsWeekends)
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
            guard let next = CalendarNavigation.move(
                from: from, direction, in: placed.entries, visible: visible, calendar: calendar, skipsWeekends: skipsWeekends)
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
        // The menu and the capsule act on the whole choice, so a choice never holds an event the calendar has left behind.
        .onChange(of: drawn) {
            let kept = browser.selection.intersection(
                CalendarLayout.ids(in: placed.entries, within: drawn, weekends: !skipsWeekends, calendar: calendar))
            if kept != browser.selection { browser.selection = kept }
        }
        .onChange(of: skipsWeekends) {
            let kept = browser.selection.intersection(
                CalendarLayout.ids(in: placed.entries, within: drawn, weekends: !skipsWeekends, calendar: calendar))
            if kept != browser.selection { browser.selection = kept }
        }
        .searchStatus(browser)
        .overlay(alignment: .bottom) { footer(placed, hiddenOnWeekend: hiddenOnWeekend) }
        .overlay {
            if placed.isEmpty {
                if browser.narrowsBySearch {
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
    }

    /// The No Date pill, and where the week hides its weekend the count of what that leaves out of it.
    private func footer(_ placed: Browser.CalendarPlacing, hiddenOnWeekend: Int) -> some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 760
            HStack(spacing: 8) {
                if !placed.leftOut.isEmpty { CalendarNoDatePill(ids: placed.leftOut, open: open) }
                if hiddenOnWeekend > 0 {
                    CalendarWeekendNote(count: hiddenOnWeekend) { browser.changeCalendarScale(.month) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: wide ? .bottom : .bottomLeading)
            .padding(.bottom, WindowCorner<EmptyView, EmptyView>.inset)
            .padding(.leading, wide ? 0 : WindowCorner<EmptyView, EmptyView>.inset)
        }
        .allowsHitTesting(true)
    }

    /// Chooses an event on one of its days, which is where the arrow keys go on from.
    private func choose(_ id: ItemID, _ day: Date) {
        keyboard.day = day
        browser.selection = [id]
    }

    private func open(_ id: ItemID) { browser.open([id]) }
}

// MARK: Parts shared by the week and the month

/// What the keys and the scroll share, kept out of what any view reads so that moving the choice runs no body: the day
/// the chosen event was chosen on and the part of the week on screen are plain, and only the small watcher that scrolls
/// reads `reveal`.
@Observable
final class CalendarKeyboard {
    @ObservationIgnored var day: Date?
    /// The part of the hours grid in view, in the grid's own points from its top, below the pinned heading.
    @ObservationIgnored var viewport = CGRect.zero
    /// How far the week has scrolled down, in the scroll view's own measure.
    @ObservationIgnored var offsetY: CGFloat = 0
    /// The event a key has just moved to, for the week to bring into view.
    var reveal: CalendarNavigation.Spot?

    /// Where to scroll so that `gridY`, a point down the hours grid, is at the top of what is in view.
    func offset(forGridY gridY: CGFloat) -> CGFloat { offsetY + gridY - viewport.minY }
}

extension CalendarEntry {
    /// What a block says to VoiceOver beyond its title: where the event really starts and ends, whatever part of it the
    /// day shows.
    func spoken(calendar: Calendar, format: DateFormat) -> String {
        let style = Date.IntervalFormatStyle(
            date: DateDisplay.style(format.date, system: .abbreviated), time: isAllDay ? .omitted : .shortened,
            locale: format.locale(calendar.locale ?? .current), calendar: calendar,
            timeZone: calendar.timeZone)
        let last = isAllDay ? max(end.addingTimeInterval(-1), start) : end
        return (start..<last).formatted(style)
    }
}

/// One item as a control: it answers a click and a double click, and reads the selection itself, so a selection that
/// moves runs these small bodies and not the calendar's.
struct CalendarCell<Label: View>: View {
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    let entry: CalendarEntry
    /// The day this one is drawn on, since an event over midnight is drawn on each.
    let day: Date
    let calendar: Calendar
    let format: DateFormat
    let choose: (ItemID, Date) -> Void
    let open: (ItemID) -> Void
    @ViewBuilder let label: (_ isSelected: Bool) -> Label

    var body: some View {
        let id = entry.id
        let isSelected = browser.selection.contains(id)
        Button {
            choose(id, day)
        } label: {
            label(isSelected)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .simultaneousGesture(TapGesture(count: 2).onEnded { open(id) })
        .help(entry.title)
        .contextMenu {
            ItemRowMenu(browser: browser, ids: browser.selection.contains(id) ? browser.selection : [id], undoManager: undoManager)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.inFeed ? Text("\(entry.title), Feed") : Text(verbatim: entry.title))
        .accessibilityValue(Text(verbatim: entry.spoken(calendar: calendar, format: format)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("Open")) { open(id) }
        .accessibilityIdentifier("CalendarItem-\(id.rawValue)-\(Self.dayKey(day, calendar))")
    }
}

extension CalendarCell {
    static func dayKey(_ day: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension View {
    /// The quiet fill of an item, or the soft gray of the chosen one.
    func calendarFill(_ isSelected: Bool, radius: CGFloat) -> some View {
        modifier(CalendarFill(isSelected: isSelected, radius: radius))
    }
}

private struct CalendarFill: ViewModifier {
    let isSelected: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.background(
            Color.primary.opacity(isSelected ? 0.14 : 0.05),
            in: .rect(cornerRadius: radius, style: .continuous))
    }
}

extension Color {
    static let calendarToday = Color.red
}

// MARK: Month

private struct CalendarMonthView: View {
    let month: CalendarMonth
    let browser: Browser
    let calendar: Calendar
    let format: DateFormat
    let choose: (ItemID, Date) -> Void
    let open: (ItemID) -> Void
    @State private var width: CGFloat = 0

    /// The gutter holds the month's name above the weeks' numbers: the whole of it where the room is.
    private var isWide: Bool { width >= 760 }
    private var gutter: CGFloat { isWide ? 144 : 56 }

    private var monthName: some View {
        let day = month.weeks.joined().first(where: \.isInMonth)?.date ?? month.interval.start
        let style = Date.FormatStyle(calendar: calendar).month(isWide ? .wide : .abbreviated)
        return HStack(spacing: 4) {
            Text(day, format: style)
            if isWide { Text(day, format: Date.FormatStyle(calendar: calendar).year()) }
        }
        .interfaceFont(.system(size: 14, weight: .semibold))
        .lineLimit(1)
        .padding(.leading, 16)
        .frame(width: gutter, alignment: .leading)
    }

    private func weekNumber(_ week: [CalendarMonth.Day]) -> some View {
        let number = week.first.map { calendar.component(.weekOfYear, from: $0.date) } ?? 0
        return (isWide ? Text("Week \(number)") : Text(verbatim: "\(number)"))
            .interfaceFont(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .padding(.leading, 16)
            .padding(.top, 6)
            .frame(width: gutter, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .accessibilityHidden(true)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                monthName
                ForEach(month.weeks.first ?? []) { day in
                    Text(day.date, format: .dateTime.weekday(.abbreviated))
                        .interfaceFont(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 28)
            .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
            .accessibilityHidden(true)
            GeometryReader { proxy in
                let rowHeight = proxy.size.height / CGFloat(max(month.weeks.count, 1))
                // The date takes 22 points and each line 17, inside 4 points of padding on every side.
                let capacity = max(Int((rowHeight - 8 - 22 - 2) / 17), 1)
                VStack(spacing: 0) {
                    ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: 0) {
                            weekNumber(week)
                            ForEach(week) { day in cell(day, capacity: capacity) }
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityLabel("Month")
    }

    private func cell(_ day: CalendarMonth.Day, capacity: Int) -> some View {
        let fitting = day.fitting(capacity: capacity)
        return VStack(alignment: .leading, spacing: 2) {
            Text(day.date, format: .dateTime.day())
                .interfaceFont(.system(size: 12.5, weight: day.isToday ? .semibold : day.isInMonth ? .medium : .regular))
                .monospacedDigit()
                .foregroundStyle(day.isToday ? AnyShapeStyle(Color.white) : day.isInMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, 4)
                .background { if day.isToday { Capsule().fill(Color.calendarToday) } }
            ForEach(fitting.shown) { entry in
                CalendarCell(browser: browser, entry: entry, day: day.date, calendar: calendar, format: format, choose: choose, open: open) { isSelected in
                    HStack(spacing: 4) {
                        Text(verbatim: entry.title)
                            .interfaceFont(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if entry.inFeed { FeedMark() }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .calendarFill(isSelected, radius: 4)
                }
            }
            if fitting.more > 0 {
                Text(verbatim: "+\(fitting.more.formatted())")
                    .interfaceFont(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .accessibilityLabel(Text("\(fitting.more) more"))
            }
            Spacer(minLength: 0)
        }
        .opacity(day.isInMonth ? 1 : 0.55)
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(day.isWeekend ? Color.primary.opacity(0.03) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
        .clipped()
    }
}
