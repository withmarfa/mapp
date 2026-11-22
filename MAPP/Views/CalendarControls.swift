import SwiftUI

/// The calendar's corner: Today, back and forward, Week or Month, and the month button, whose card opens above them.
/// In a narrow window Week or Month folds into one button with a menu (`CalendarCorner`). Each is a View menu command
/// and a palette entry too (`ItemCalendarOptions`, `ViewOptionCommand`).
struct CalendarCornerView: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    /// The content's width, which decides whether Week or Month folds.
    let width: CGFloat

    var body: some View {
        let scale = browser.calendarScale
        WindowCorner(isCardOpen: browser.showsCalendarMonth) {
            Button("Today") { browser.moveCalendar(by: nil, now: library.now()) }
                .buttonStyle(CornerButtonStyle())
                .accessibilityLabel("Today")
                .accessibilityIdentifier("CalendarToday")
            CornerButtonGroup {
                Button("Previous", systemImage: "chevron.left") { browser.moveCalendar(by: -1, now: library.now()) }
                    .help(scale == .week ? "Previous Week" : "Previous Month")
                    .accessibilityLabel(scale == .week ? "Previous Week" : "Previous Month")
                    .accessibilityIdentifier("CalendarPrevious")
                Button("Next", systemImage: "chevron.right") { browser.moveCalendar(by: 1, now: library.now()) }
                    .help(scale == .week ? "Next Week" : "Next Month")
                    .accessibilityLabel(scale == .week ? "Next Week" : "Next Month")
                    .accessibilityIdentifier("CalendarNext")
            }
            .labelStyle(.iconOnly)
            scalePicker(scale)
            Button(browser.showsCalendarMonth ? "Hide Month" : "Show Month", systemImage: "calendar") { browser.toggleCalendarMonth() }
                .labelStyle(.iconOnly)
                .buttonStyle(CornerButtonStyle(isOn: browser.showsCalendarMonth))
                .help(browser.showsCalendarMonth ? "Hide Month" : "Show Month")
                .accessibilityLabel(browser.showsCalendarMonth ? "Hide Month" : "Show Month")
                .accessibilityIdentifier("CalendarShowMonth")
        } card: {
            CalendarMonthCard(browser: browser)
        }
        .onChange(of: browser.item) { browser.showsCalendarMonth = false }
        .onDisappear { browser.showsCalendarMonth = false }
    }

    @ViewBuilder private func scalePicker(_ scale: CalendarScale) -> some View {
        let choice = Binding { scale } set: { browser.changeCalendarScale($0) }
        if CalendarCorner.foldsScale(forWidth: width) {
            CornerMenu(title: String(localized: scale.title)) {
                Picker("Show", selection: choice) {
                    ForEach(CalendarScale.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            .help("Show a Week or a Month")
            .accessibilityLabel("Show a Week or a Month")
            .accessibilityIdentifier("CalendarScale")
        } else {
            CornerSegmented(label: "Show", selection: choice, options: CalendarScale.allCases) { $0.title }
                .help("Show a Week or a Month")
                .accessibilityLabel("Show a Week or a Month")
                .accessibilityIdentifier("CalendarScale")
        }
    }
}

/// The calendar's commands in the View menu, which a hidden toolbar leaves as the way to them, in the order the corner
/// has them. Week and Month are ticked for the one showing.
struct ItemCalendarOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    /// The keys the menu binds; the toolbar's copy in View Options has none and leaves them to the menu.
    var shortcuts: ShortcutBindings?

    var body: some View {
        let scale = browser.calendarScale
        Button("Today", systemImage: "calendar.circle") { browser.moveCalendar(by: nil, now: library.now()) }
            .shortcut(.today, shortcuts)
        Button(scale == .week ? "Previous Week" : "Previous Month", systemImage: "chevron.left") {
            browser.moveCalendar(by: -1, now: library.now())
        }
        .shortcut(.previousPeriod, shortcuts)
        Button(scale == .week ? "Next Week" : "Next Month", systemImage: "chevron.right") {
            browser.moveCalendar(by: 1, now: library.now())
        }
        .shortcut(.nextPeriod, shortcuts)
        Toggle("Week", isOn: Binding { scale == .week } set: { _ in browser.changeCalendarScale(.week) })
            .shortcut(.showWeek, shortcuts)
        Toggle("Month", isOn: Binding { scale == .month } set: { _ in browser.changeCalendarScale(.month) })
            .shortcut(.showMonthScale, shortcuts)
        Button(browser.showsCalendarMonth ? "Hide Month" : "Show Month", systemImage: "calendar") {
            browser.toggleCalendarMonth()
        }
        .shortcut(.toggleMonth, shortcuts)
    }
}
