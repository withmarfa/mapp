import SwiftUI

/// The calendar layout: a week of day columns with hours, or a month of days, with each item where its type's date puts
/// it (`CalendarLayout`). Choosing an item opens the right sidebar, as the timeline does. A selection that moves runs
/// the bodies of the cells that wrap an item and of no calendar: the layout is worked out here from the items alone.
struct ItemCalendar: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var daysSeen = 0
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard

    var body: some View {
        let _ = daysSeen
        let items = browser.filteredItems(in: library)
        let calendar = Calendar.current
        let now = library.now()
        let anchor = browser.calendarDay ?? now
        let placed = CalendarLayout.entries(for: items, looks: browser.looks(in: library), catalogue: library.catalogue, calendar: calendar)
        let scale = browser.calendarScale

        Group {
            switch scale {
            case .week:
                let week = CalendarWeek.make(entries: placed.entries, around: anchor, calendar: calendar, now: now)
                CalendarWeekView(week: week, browser: browser, calendar: calendar, now: now, open: open)
                    .navigationTitle(Self.title(of: week.interval, calendar: calendar))
                    .navigationSubtitle(Text("Week \(calendar.component(.weekOfYear, from: week.interval.start))").editedSubtitle(browser.hasViewChanges))
            case .month:
                let month = CalendarMonth.make(entries: placed.entries, around: anchor, calendar: calendar, now: now)
                CalendarMonthView(month: month, browser: browser, calendar: calendar, open: open)
                    .navigationTitle(Self.title(of: month.interval, calendar: calendar))
                    .navigationSubtitle(Text("^[\(month.itemCount) item](inflect: true)").editedSubtitle(browser.hasViewChanges))
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused(pane, equals: .list)
        .onKeyPress(.return) {
            guard browser.selection.count == 1 else { return .ignored }
            browser.openCollectionSelection()
            return .handled
        }
        .onKeyPress(.escape) { browser.selection = []; return .handled }
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

    private func open(_ id: ItemID) {
        browser.selection = [id]
        browser.openCollectionSelection()
    }

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

/// One item as a control: it answers a click and a double click, and reads the selection itself, so a selection that
/// moves runs these small bodies and not the calendar's.
private struct CalendarCell<Label: View>: View {
    let browser: Browser
    let id: ItemID
    let help: String
    let open: (ItemID) -> Void
    @ViewBuilder let label: (_ isSelected: Bool) -> Label

    var body: some View {
        let isSelected = browser.selection.contains(id)
        Button {
            browser.selection = [id]
        } label: {
            label(isSelected)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .simultaneousGesture(TapGesture(count: 2).onEnded { open(id) })
        .help(help)
        .contextMenu { Button("Open") { open(id) } }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("Open")) { open(id) }
        .accessibilityIdentifier("CalendarItem-\(id.rawValue)")
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
    func hourText(_ hour: Int, on day: Date) -> String {
        let date = self.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return date.formatted(Date.FormatStyle(calendar: self, timeZone: timeZone).hour())
    }
}

// MARK: Week

private struct CalendarWeekView: View {
    let week: CalendarWeek
    let browser: Browser
    let calendar: Calendar
    let now: Date
    let open: (ItemID) -> Void

    private static let hourHeight: CGFloat = 59
    private static let margin: CGFloat = 56
    /// The hour the day opens scrolled to, a little above the working day's first hour.
    private static let workday = 8

    var body: some View {
        VStack(spacing: 0) {
            header
            allDay
            ScrollViewReader { proxy in
                ScrollView {
                    grid.id("grid")
                        .overlay(alignment: .topLeading) {
                            Color.clear.frame(width: 1, height: 1)
                                .offset(y: CGFloat(Self.workday) * Self.hourHeight - 12)
                                .id("workday")
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onAppear { proxy.scrollTo("workday", anchor: .top) }
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
            Text("All Day")
                .interfaceFont(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
                .frame(width: Self.margin, alignment: .trailing)
                .frame(maxHeight: .infinity, alignment: .center)
            ForEach(week.days) { day in
                VStack(spacing: 2) {
                    ForEach(day.allDay) { entry in
                        CalendarCell(browser: browser, id: entry.id, help: entry.title, open: open) { isSelected in
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
        .accessibilityLabel("All Day")
    }

    private var grid: some View {
        let height = Self.hourHeight * 24
        return HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ForEach(1..<24, id: \.self) { hour in
                    Text(calendar.hourText(hour, on: week.interval.start))
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
                    CalendarCell(browser: browser, id: block.entry.id, help: block.entry.title, open: open) { isSelected in
                        CalendarBlockLabel(entry: block.entry, isSelected: isSelected, calendar: calendar, showsTime: tall >= 34)
                            .frame(width: max(slot - 2, 8), height: tall - 1, alignment: .topLeading)
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

/// What a block says: its title on up to two lines and its start.
private struct CalendarBlockLabel: View {
    let entry: CalendarEntry
    let isSelected: Bool
    let calendar: Calendar
    let showsTime: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: entry.title)
                .interfaceFont(.system(size: 11.5, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(isSelected ? Color.white : .primary)
            if showsTime {
                Text(verbatim: DateDisplay.timeOfDay(of: entry.start, calendar: calendar))
                    .interfaceFont(.system(size: 10.5))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
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
                CalendarCell(browser: browser, id: entry.id, help: entry.title, open: open) { isSelected in
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
                Text("+\(fitting.more)")
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
