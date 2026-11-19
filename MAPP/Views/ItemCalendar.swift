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

    var body: some View {
        let _ = daysSeen
        let items = browser.filteredItems(in: library)
        let calendar = Calendar.current
        let now = library.now()
        let anchor = browser.calendarDay ?? now
        let placed = CalendarLayout.entries(for: items, looks: browser.looks(in: library), catalogue: library.catalogue, calendar: calendar)
        let scale = browser.calendarScale
        let visible = CalendarLayout.interval(of: scale, containing: anchor, calendar: calendar)

        Group {
            switch scale {
            case .week:
                let week = CalendarWeek.make(entries: placed.entries, around: anchor, calendar: calendar, now: now)
                CalendarWeekView(week: week, browser: browser, keyboard: keyboard, calendar: calendar, now: now, choose: choose, open: open)
                    .navigationTitle(Self.title(of: week.interval, calendar: calendar))
                    .navigationSubtitle(Text("Week \(calendar.component(.weekOfYear, from: week.interval.start))").editedSubtitle(browser.hasViewChanges))
            case .month:
                let month = CalendarMonth.make(entries: placed.entries, around: anchor, calendar: calendar, now: now)
                CalendarMonthView(month: month, browser: browser, calendar: calendar, choose: choose, open: open)
                    .navigationTitle(Self.title(of: month.interval, calendar: calendar))
                    .navigationSubtitle(Text("^[\(month.itemCount) item](inflect: true)").editedSubtitle(browser.hasViewChanges))
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
            if !visible.contains(next.day) { browser.calendarDay = next.day }
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
                    EmptyState("No Items")
                }
            }
        }
        .filteredEmptyState(browser)
        .background(ChosenRowOpensSidebar(browser: browser))
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
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

    /// The month of the span, or both months where a week crosses two, with the year.
    static func title(of interval: DateInterval, calendar: Calendar) -> String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateTemplate = "yMMMM"
        return formatter.string(from: interval.start, to: interval.end.addingTimeInterval(-1))
    }
}

// MARK: Parts shared by the week and the month

/// What the keys and the scroll share, kept out of what any view reads so that moving the choice runs no body: the day
/// the chosen event was chosen on and the part of the week on screen are plain, and only the small watcher that scrolls
/// reads `reveal`.
@Observable
private final class CalendarKeyboard {
    @ObservationIgnored var day: Date?
    @ObservationIgnored var viewport = CGRect.zero
    /// The event a key has just moved to, for the week to bring into view.
    var reveal: CalendarNavigation.Spot?
}

private extension CalendarEntry {
    /// What a block says to VoiceOver beyond its title: where the event really starts and ends, whatever part of it the
    /// day shows.
    func spoken(calendar: Calendar) -> String {
        let style = Date.IntervalFormatStyle(
            date: .abbreviated, time: isAllDay ? .omitted : .shortened, locale: calendar.locale ?? .current, calendar: calendar,
            timeZone: calendar.timeZone)
        let last = isAllDay ? max(end.addingTimeInterval(-1), start) : end
        return (start..<last).formatted(style)
    }
}

/// One item as a control: it answers a click and a double click, and reads the selection itself, so a selection that
/// moves runs these small bodies and not the calendar's.
private struct CalendarCell<Label: View>: View {
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    let entry: CalendarEntry
    /// The day this one is drawn on, since an event over midnight is drawn on each.
    let day: Date
    let calendar: Calendar
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
        .accessibilityLabel(Text(verbatim: entry.title))
        .accessibilityValue(Text(verbatim: entry.spoken(calendar: calendar)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("Open")) { open(id) }
        .accessibilityIdentifier("CalendarItem-\(id.rawValue)-\(Self.dayKey(day, calendar))")
    }
}

private extension CalendarCell {
    static func dayKey(_ day: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

private extension View {
    /// The quiet fill of an item, or the accent for the chosen one.
    func calendarFill(_ isSelected: Bool, radius: CGFloat) -> some View {
        background(
            isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.05)),
            in: .rect(cornerRadius: radius, style: .continuous))
    }
}

private extension Color {
    static let calendarToday = Color.red
}

private extension Calendar {
    /// The label of an hour on the clock, read on a day that has no daylight saving change, so the hour a change skips
    /// still has its label.
    func hourText(_ hour: Int) -> String {
        var plain = Calendar(identifier: .gregorian)
        plain.timeZone = .gmt
        let date = plain.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour)) ?? Date(timeIntervalSinceReferenceDate: TimeInterval(hour * 3600))
        return date.formatted(Date.FormatStyle(locale: locale ?? .current, calendar: plain, timeZone: .gmt).hour())
    }
}

// MARK: Week

private struct CalendarWeekView: View {
    let week: CalendarWeek
    let browser: Browser
    let keyboard: CalendarKeyboard
    let calendar: Calendar
    let now: Date
    let choose: (ItemID, Date) -> Void
    let open: (ItemID) -> Void

    fileprivate static let hourHeight: CGFloat = 59
    private static let margin: CGFloat = 56
    /// The hour the day opens scrolled to, a little above the working day's first hour.
    private static let workday = 8
    @State private var position = ScrollPosition()

    var body: some View {
        VStack(spacing: 0) {
            header
            allDay
            ScrollView { grid }
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, visible in keyboard.viewport = visible }
                .background(CalendarReveal(keyboard: keyboard, week: week, position: $position))
                .scrollBounceBehavior(.basedOnSize)
                .task {
                    // The grid has no size on the first pass, so scroll once it has been laid out.
                    try? await Task.sleep(for: .milliseconds(100))
                    position.scrollTo(y: CGFloat(Self.workday) * Self.hourHeight - 12)
                }
        }
        .accessibilityLabel("Week")
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.margin)
            ForEach(week.days) { day in
                HStack(spacing: 6) {
                    Text(day.date, format: .dateTime.weekday(.abbreviated))
                        .interfaceFont(.system(size: 12))
                        .foregroundStyle(day.isToday ? Color.calendarToday : .secondary)
                    Text(day.date, format: .dateTime.day())
                        .interfaceFont(.system(size: 14, weight: day.isToday ? .semibold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(day.isToday ? Color.white : .primary)
                        .frame(minWidth: 24, minHeight: 24)
                        .background { if day.isToday { Circle().fill(Color.calendarToday) } }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
    }

    private var allDay: some View {
        HStack(spacing: 0) {
            Text("All day")
                .interfaceFont(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
                .frame(width: Self.margin, alignment: .trailing)
                .frame(maxHeight: .infinity, alignment: .center)
            ForEach(week.days) { day in
                VStack(spacing: 2) {
                    ForEach(day.allDay) { entry in
                        CalendarCell(browser: browser, entry: entry, day: day.date, calendar: calendar, choose: choose, open: open) { isSelected in
                            Text(verbatim: entry.title)
                                .interfaceFont(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? Color.white : .primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .calendarFill(isSelected, radius: 5)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(day.isWeekend ? Color.primary.opacity(0.03) : .clear)
                .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 0.5) }
            }
        }
        .frame(minHeight: 28)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
        .accessibilityLabel("All day")
    }

    private var grid: some View {
        let height = Self.hourHeight * 24
        return HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ForEach(1..<24, id: \.self) { hour in
                    Text(calendar.hourText(hour))
                        .interfaceFont(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                        .offset(y: CGFloat(hour) * Self.hourHeight - 7)
                }
            }
            .frame(width: Self.margin, height: height, alignment: .topTrailing)
            .accessibilityHidden(true)
            ForEach(week.days) { day in
                column(day, height: height)
            }
        }
        .frame(height: height)
    }

    private func column(_ day: CalendarWeek.Day, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle().fill(.separator).frame(height: 0.5).offset(y: CGFloat(hour) * Self.hourHeight)
                }
                ForEach(day.blocks) { block in
                    let slot = (width - 6) / CGFloat(block.columns)
                    let top = CGFloat(block.startMinute) / 60 * Self.hourHeight
                    let tall = max(CGFloat(block.endMinute - block.startMinute) / 60 * Self.hourHeight, 20)
                    let blockWidth = max(slot - 2, 8)
                    CalendarCell(browser: browser, entry: block.entry, day: day.date, calendar: calendar, choose: choose, open: open) { isSelected in
                        CalendarBlockLabel(
                            entry: block.entry, isSelected: isSelected, calendar: calendar, showsTime: tall >= 34, width: blockWidth,
                            height: tall - 1)
                            .frame(width: blockWidth, height: tall - 1, alignment: .topLeading)
                            .calendarFill(isSelected, radius: 6)
                            .shadow(color: isSelected ? .black.opacity(0.18) : .clear, radius: 3, y: 2)
                    }
                    .offset(x: 3 + slot * CGFloat(block.column), y: top)
                }
                if let line = week.nowMinute(now: now, calendar: calendar), line.day == day.date {
                    NowLine().offset(y: CGFloat(line.minute) / 60 * Self.hourHeight)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .background(day.isWeekend ? Color.primary.opacity(0.03) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 0.5) }
        .clipped()
    }
}

/// Scrolls the week to the event a key has moved to, when it is not in view. It alone reads `reveal`.
private struct CalendarReveal: View {
    let keyboard: CalendarKeyboard
    let week: CalendarWeek
    @Binding var position: ScrollPosition

    var body: some View {
        Color.clear.onChange(of: keyboard.reveal) { _, spot in
            guard let spot,
                let block = week.days.first(where: { $0.date == spot.day })?.blocks.first(where: { $0.entry.id == spot.id })
            else { return }
            let hour = CalendarWeekView.hourHeight
            let top = CGFloat(block.startMinute) / 60 * hour
            let bottom = top + max(CGFloat(block.endMinute - block.startMinute) / 60 * hour, 20)
            let shown = keyboard.viewport
            if top < shown.minY + 8 {
                position.scrollTo(y: max(top - 12, 0))
            } else if bottom > shown.maxY - 8 {
                position.scrollTo(y: bottom + 12 - shown.height)
            }
        }
    }
}

/// What a block says: its title on up to two lines, by word and ending in an ellipsis where it is cut, and its start.
private struct CalendarBlockLabel: View {
    let entry: CalendarEntry
    let isSelected: Bool
    let calendar: Calendar
    let showsTime: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.interfaceTextSize) private var textSize

    private static let padding = EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let font = NSFont.systemFont(ofSize: 11.5 * scale, weight: .medium)
        let room = height - Self.padding.top - Self.padding.bottom - (showsTime ? 12 * scale : 0)
        let lineCount = max(1, min(2, Int(room / (14 * scale))))
        // A point is kept back so a line that measures as fitting is not cut by the text's own rounding.
        let lines = CalendarLayout.titleLines(
            entry.title, lines: lineCount, fitting: width - Self.padding.leading - Self.padding.trailing - 1
        ) { ($0 as NSString).size(withAttributes: [.font: font]).width }
        VStack(alignment: .leading, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .interfaceFont(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isSelected ? Color.white : .primary)
                }
            }
            if showsTime {
                Text(verbatim: DateDisplay.timeOfDay(of: entry.start, calendar: calendar))
                    .interfaceFont(.system(size: 10.5))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The present moment: a red line across today's column, which the minute moves.
private struct NowLine: View {
    var body: some View {
        Rectangle().fill(Color.calendarToday).frame(height: 1)
            .overlay(alignment: .leading) { Circle().fill(Color.calendarToday).frame(width: 7, height: 7).offset(x: -3) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: Month

private struct CalendarMonthView: View {
    let month: CalendarMonth
    let browser: Browser
    let calendar: Calendar
    let choose: (ItemID, Date) -> Void
    let open: (ItemID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
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
                            ForEach(week) { day in cell(day, capacity: capacity) }
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        }
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
                CalendarCell(browser: browser, entry: entry, day: day.date, calendar: calendar, choose: choose, open: open) { isSelected in
                    Text(verbatim: entry.title)
                        .interfaceFont(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.white : .primary)
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
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(day.isWeekend ? Color.primary.opacity(0.03) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
        .clipped()
    }
}
