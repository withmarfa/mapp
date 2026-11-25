import AppKit
import SwiftUI

/// The calendar's week: a strip of day columns that a two-finger swipe scrolls along, a day at a time as a Mac's own
/// scroll does, and settles on a day's edge. The week shown can start on any day; its title, and the corner's Today and
/// arrows, follow it (`Browser.calendarDay` holds the first day, written when a scroll settles).
///
/// The strip is one scroll view that scrolls both ways. Only the columns in and next to view are built, set in a space as
/// wide as the whole strip (`CalendarStrip`), so a scroll builds no body: the view reads where it is only in whole days.
/// The heading, which holds the day names and the All Day row, pins to the top, and the hours' labels pin to the left,
/// by the scroll view's own measure (`visualEffect`), which costs nothing as it scrolls. A pinch changes the height of an
/// hour (`CalendarHourHeight`); the blocks follow it, and the hour under the pointer stays under it.
struct CalendarWeekView: View {
    let entries: [CalendarEntry]
    /// The first day of the seven shown, as the browser holds it. A change that did not come from a scroll here scrolls
    /// the strip to it.
    let firstDay: Date
    let browser: Browser
    let keyboard: CalendarKeyboard
    let calendar: Calendar
    let format: DateFormat
    let now: Date
    let choose: (ItemID, Date) -> Void
    let open: (ItemID) -> Void

    @AppStorage(CalendarHourHeight.key) private var storedHeight = Double(CalendarHourHeight.standard)
    @State private var strip: CalendarStrip
    @State private var scrolled: CalendarStrip.Position
    @State private var position = ScrollPosition()
    @State private var size = CGSize.zero
    /// The hour's height while a pinch is going, which the setting takes when it ends.
    @State private var pinchHeight: CGFloat?
    @State private var isReady = false
    @State private var tracker = WeekTracker()

    private static let margin: CGFloat = 56
    private static let headerHeight: CGFloat = 40
    /// The hour the day opens scrolled to, a little above the working day's first hour.
    private static let workday = 8
    private nonisolated static let space = "CalendarWeekScroll"

    init(
        entries: [CalendarEntry], firstDay: Date, browser: Browser, keyboard: CalendarKeyboard, calendar: Calendar,
        format: DateFormat, now: Date, choose: @escaping (ItemID, Date) -> Void, open: @escaping (ItemID) -> Void
    ) {
        self.entries = entries
        self.firstDay = firstDay
        self.browser = browser
        self.keyboard = keyboard
        self.calendar = calendar
        self.format = format
        self.now = now
        self.choose = choose
        self.open = open
        let strip = CalendarStrip(around: firstDay, calendar: calendar)
        let index = strip.index(of: firstDay, calendar: calendar)
        _strip = State(initialValue: strip)
        _scrolled = State(initialValue: CalendarStrip.Position(leading: index, nearest: index, isBetween: false))
    }

    private var hourHeight: CGFloat { pinchHeight ?? CalendarHourHeight.clamped(CGFloat(storedHeight)) }
    private var columnWidth: CGFloat { max((size.width - Self.margin) / 7, 1) }

    var body: some View {
        let hour = hourHeight
        let column = columnWidth
        let range = strip.drawn(leading: scrolled.leading)
        let run = CalendarWeek.make(
            entries: entries, startingOn: strip.day(at: range.lowerBound, calendar: calendar), count: range.count,
            calendar: calendar, now: now, shortestBlock: CalendarHourHeight.shortestBlock(at: hour))
        let shown = scrolled.shown()
        let showsAllDay = CalendarWeek.showsAllDay(
            run.days.enumerated().filter { shown.contains(range.lowerBound + $0.offset) }.map(\.element))
        let first = strip.day(at: scrolled.nearest, calendar: calendar)
        let end = strip.day(at: scrolled.nearest + 7, calendar: calendar)

        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    grid(run, range: range, hour: hour, column: column)
                } header: {
                    heading(run, range: range, showsAllDay: showsAllDay, column: column)
                }
            }
        }
        .scrollIndicators(.hidden, axes: .horizontal)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollPosition($position)
        .scrollTargetBehavior(DaySnap(dayWidth: column))
        // `ScrollPosition` counts from the content's own corner, while `contentOffset` counts from the safe area's (the
        // sidebar and the toolbar are part of it), so both are read with the inset added back.
        .onScrollGeometryChange(for: CalendarStrip.Position.self) {
            CalendarStrip.position(offset: $0.contentOffset.x + $0.contentInsets.leading, dayWidth: column)
        } action: { _, new in
            scrolled = new
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            keyboard.offsetY = offset
        }
        .onScrollPhaseChange { old, phase, context in
            if phase == .idle { settle(atOffset: context.geometry.contentOffset.x + context.geometry.contentInsets.leading) }
        }
        .overlay(alignment: .top) { Color.clear.frame(height: 1).background(.background, ignoresSafeAreaEdges: .top).allowsHitTesting(false) }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0; updateViewport() }
        .background(
            CalendarReveal(keyboard: keyboard, entries: entries, calendar: calendar, now: now, hourHeight: hour, position: $position))
        .simultaneousGesture(pinch)
        .opacity(isReady ? 1 : 0)
        .task(id: size.width > 0) { await start() }
        .onChange(of: column) {
            if isReady { position.scrollTo(x: CGFloat(tracker.settledIndex) * column, y: keyboard.offsetY) }
        }
        .onChange(of: firstDay) { _, day in go(to: day) }
        .accessibilityLabel("Week")
    }

    // MARK: Scrolling

    /// Scrolls to the first day and the working day once the strip has a size, which the first pass does not give it.
    private func start() async {
        guard size.width > 0, !isReady else { return }
        try? await Task.sleep(for: .milliseconds(100))
        let index = strip.index(of: firstDay, calendar: calendar)
        tracker.settledIndex = index
        position.scrollTo(x: CGFloat(index) * columnWidth, y: keyboard.offset(forGridY: CGFloat(Self.workday) * hourHeight - 12))
        try? await Task.sleep(for: .milliseconds(50))
        isReady = true
    }

    /// Scrolls to `day` when the corner, the month card or a key moved the calendar there, by steps that are few, and
    /// at once when they are many, where the strip is built again around the day if it lies near an end of it.
    private func go(to day: Date) {
        guard isReady else { return }
        var index = strip.index(of: day, calendar: calendar)
        let near = abs(index - scrolled.nearest) <= 21
        var rebuilt = false
        if !strip.holds(index) {
            strip = CalendarStrip(around: day, calendar: calendar)
            index = strip.index(of: day, calendar: calendar)
            rebuilt = true
        }
        // The day a scroll here settled on comes back as `firstDay`, and is already where the strip is.
        guard rebuilt || index != tracker.settledIndex else { return }
        tracker.settledIndex = index
        let x = CGFloat(index) * columnWidth
        if near && !rebuilt {
            withAnimation(.smooth) { position.scrollTo(x: x, y: keyboard.offsetY) }
        } else {
            scrolled = CalendarStrip.Position(leading: index, nearest: index, isBetween: false)
            position.scrollTo(x: x, y: keyboard.offsetY)
        }
    }

    /// Tells the browser which day the scroll came to rest on. A scroll that stopped between days (a mouse wheel, say)
    /// is brought to the nearest one first.
    private func settle(atOffset offset: CGFloat) {
        guard isReady else { return }
        let rest = CalendarStrip.position(offset: offset, dayWidth: columnWidth)
        let index = rest.nearest
        if rest.isBetween {
            withAnimation(.smooth(duration: 0.2)) { position.scrollTo(x: CGFloat(index) * columnWidth, y: keyboard.offsetY) }
            return
        }
        guard index != tracker.settledIndex else { return }
        tracker.settledIndex = index
        let day = strip.day(at: index, calendar: calendar)
        if day != calendar.startOfDay(for: firstDay) { browser.calendarDay = day }
    }

    private func updateViewport() {
        keyboard.viewport = CGRect(
            x: 0, y: tracker.headingBottom - tracker.gridTop, width: 1, height: max(size.height - tracker.headingBottom, 0))
    }

    // MARK: Pinching

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = tracker.pinch ?? WeekTracker.Pinch(
                    height: hourHeight, offset: keyboard.offsetY, gridY: value.startLocation.y - tracker.gridTop)
                tracker.pinch = start
                let height = CalendarHourHeight.pinched(from: start.height, magnification: value.magnification)
                pinchHeight = height
                position.scrollTo(
                    y: CalendarHourHeight.offset(keeping: start.gridY, scrolled: start.offset, from: start.height, to: height))
            }
            .onEnded { _ in
                if let pinchHeight { storedHeight = Double(pinchHeight) }
                pinchHeight = nil
                tracker.pinch = nil
            }
    }

    // MARK: Heading

    private func heading(_ run: CalendarWeek, range: Range<Int>, showsAllDay: Bool, column: CGFloat) -> some View {
        let lead = Self.margin + CGFloat(range.lowerBound) * column
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: lead)
                ForEach(run.days) { day in dayName(day).frame(width: column) }
            }
            .frame(height: Self.headerHeight)
            if showsAllDay {
                HStack(spacing: 0) {
                    Color.clear.frame(width: lead)
                    ForEach(run.days) { day in allDay(day).frame(width: column).frame(maxHeight: .infinity) }
                }
                .frame(minHeight: 28)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: lead + CGFloat(strip.count - range.lowerBound) * column, alignment: .leading)
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: Self.headerHeight)
                    .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
                if showsAllDay {
                    Text("All day")
                        .interfaceFont(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
                        .accessibilityLabel("All day")
                }
            }
            .frame(width: Self.margin)
            .background(.background)
            .pinnedToLeadingEdge()
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxY } action: { bottom in
            tracker.headingBottom = bottom
            updateViewport()
        }
    }

    private func dayName(_ day: CalendarWeek.Day) -> some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.background)
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
    }

    private func allDay(_ day: CalendarWeek.Day) -> some View {
        VStack(spacing: 2) {
            ForEach(day.allDay) { entry in
                CalendarCell(browser: browser, entry: entry, day: day.date, calendar: calendar, format: format, choose: choose, open: open) { isSelected in
                    Text(verbatim: entry.title)
                        .interfaceFont(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
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
        .background(.background)
        .background(day.isWeekend ? Color.primary.opacity(0.03) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
    }

    // MARK: Hours

    private func grid(_ run: CalendarWeek, range: Range<Int>, hour: CGFloat, column: CGFloat) -> some View {
        let height = hour * 24
        let lead = Self.margin + CGFloat(range.lowerBound) * column
        return HStack(spacing: 0) {
            Color.clear.frame(width: lead)
            ForEach(run.days) { day in dayColumn(day, run: run, width: column, hour: hour) }
        }
        .frame(width: lead + CGFloat(strip.count - range.lowerBound) * column, height: height, alignment: .leading)
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topTrailing) {
                ForEach(1..<24, id: \.self) { hourOfDay in
                    Text(verbatim: DateDisplay.hourLabel(hourOfDay, format: format, locale: calendar.locale ?? .current))
                        .interfaceFont(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                        .offset(y: CGFloat(hourOfDay) * hour - 7)
                }
            }
            .frame(width: Self.margin, height: height, alignment: .topTrailing)
            .background(.background)
            .pinnedToLeadingEdge()
            .accessibilityHidden(true)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { top in
            tracker.gridTop = top
            updateViewport()
        }
    }

    private func dayColumn(_ day: CalendarWeek.Day, run: CalendarWeek, width: CGFloat, hour: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { hourOfDay in
                Rectangle().fill(.separator).frame(height: 0.5).offset(y: CGFloat(hourOfDay) * hour)
            }
            ForEach(day.blocks) { block in
                let slot = (width - 6) / CGFloat(block.columns)
                let top = CGFloat(block.startMinute) / 60 * hour
                let tall = max(CGFloat(block.endMinute - block.startMinute) / 60 * hour, 20)
                let blockWidth = max(slot - 2, 8)
                CalendarCell(browser: browser, entry: block.entry, day: day.date, calendar: calendar, format: format, choose: choose, open: open) { isSelected in
                    CalendarBlockLabel(
                        entry: block.entry, calendar: calendar, format: format, width: blockWidth, height: tall - 1)
                        .frame(width: blockWidth, height: tall - 1, alignment: .topLeading)
                        .calendarFill(isSelected, radius: 6)
                        .shadow(color: isSelected ? .black.opacity(0.18) : .clear, radius: 3, y: 2)
                }
                .offset(x: 3 + slot * CGFloat(block.column), y: top)
            }
            if let line = run.nowMinute(now: now, calendar: calendar), line.day == day.date {
                NowLine().offset(y: CGFloat(line.minute) / 60 * hour)
            }
        }
        .frame(width: width, height: hour * 24, alignment: .topLeading)
        .background(day.isWeekend ? Color.primary.opacity(0.03) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 0.5) }
        .clipped()
    }
}

/// What the week keeps from one moment to the next without drawing from it, so a scroll or a pinch runs no body.
private final class WeekTracker {
    struct Pinch {
        /// The hour's height, how far the week had scrolled, and the point down the grid under the pointer, when the
        /// pinch began.
        let height: CGFloat
        let offset: CGFloat
        let gridY: CGFloat
    }

    /// The day the strip last rested on.
    var settledIndex = 0
    /// Where the hours grid begins, and the heading ends, in the scroll view's own space.
    var gridTop: CGFloat = 0
    var headingBottom: CGFloat = 0
    var pinch: Pinch?
}

/// Ends a scroll on a day's left edge, whatever speed it was let go at. Up and down are left as they are.
private struct DaySnap: ScrollTargetBehavior {
    let dayWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = CalendarStrip.snapped(offset: target.rect.origin.x, dayWidth: dayWidth)
    }
}

private extension View {
    /// Keeps a view at the left edge of the scroll view it is in as that scrolls sideways, and lets it go with the
    /// content where the scroll view is pulled past its start.
    func pinnedToLeadingEdge() -> some View {
        visualEffect { content, proxy in
            content.offset(x: max(0, -proxy.frame(in: .scrollView).minX))
        }
    }
}

/// Scrolls the week to the event a key has moved to, when it is not in view. It alone reads `reveal`.
private struct CalendarReveal: View {
    let keyboard: CalendarKeyboard
    let entries: [CalendarEntry]
    let calendar: Calendar
    let now: Date
    let hourHeight: CGFloat
    @Binding var position: ScrollPosition

    var body: some View {
        Color.clear.onChange(of: keyboard.reveal) { _, spot in
            guard let spot,
                let block = CalendarWeek.make(entries: entries, startingOn: spot.day, count: 1, calendar: calendar, now: now)
                    .days.first?.blocks.first(where: { $0.entry.id == spot.id })
            else { return }
            let top = CGFloat(block.startMinute) / 60 * hourHeight
            let bottom = top + max(CGFloat(block.endMinute - block.startMinute) / 60 * hourHeight, 20)
            let shown = keyboard.viewport
            if top < shown.minY + 8 {
                position.scrollTo(y: keyboard.offset(forGridY: max(top - 12, 0)))
            } else if bottom > shown.maxY - 8 {
                position.scrollTo(y: keyboard.offset(forGridY: bottom + 12 - shown.height))
            }
        }
    }
}

/// What a block says: its title on as many lines as its height has room for, by word and ending in an ellipsis where it
/// is cut, and its start where there is room left after the title (`CalendarLayout.blockLabel`).
private struct CalendarBlockLabel: View {
    let entry: CalendarEntry
    let calendar: Calendar
    let format: DateFormat
    let width: CGFloat
    let height: CGFloat
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let font = NSFont.systemFont(ofSize: 11.5 * scale, weight: .medium)
        // A narrow block gives its sides up to the title.
        let side: CGFloat = width < 60 * scale ? 3 : 6
        let plan = CalendarLayout.blockLabel(height: height, width: width - side * 2, scale: scale)
        let showsTime = plan.showsTime
        // A point is kept back so a line that measures as fitting is not cut by the text's own rounding.
        let lines = CalendarLayout.titleLines(
            entry.title, lines: plan.titleLines, fitting: width - side * 2 - 1
        ) { ($0 as NSString).size(withAttributes: [.font: font]).width }
        VStack(alignment: .leading, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .interfaceFont(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                }
            }
            if showsTime {
                Text(verbatim: DateDisplay.timeOfDay(of: entry.start, format: format, calendar: calendar))
                    .interfaceFont(.system(size: 10.5))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(EdgeInsets(top: 3 * scale, leading: side, bottom: 3 * scale, trailing: side))
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
