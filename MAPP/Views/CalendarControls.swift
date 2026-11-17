import SwiftUI

/// The calendar's controls in the window's toolbar: Today, back and forward, and the Week or Month choice, as the
/// system draws them. Each is a View menu command and a palette entry too (`ItemCalendarOptions`,
/// `ViewOptionCommand`). They are declared in every state and hidden unless the calendar is showing.
struct CalendarToolbarItems: CustomizableToolbarContent {
    @Bindable var browser: Browser
    var isHidden: Bool { browser.viewMode != .calendar || !browser.showsCollection }

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "calendarToday") {
            Button("Today") { browser.moveCalendar(by: nil, now: .now) }
                .help("Go to Today")
                .accessibilityIdentifier("CalendarToday")
        }
        .hidden(isHidden)
        ToolbarItem(id: "calendarBack") {
            Button("Previous", systemImage: "chevron.left") { browser.moveCalendar(by: -1, now: .now) }
                .help(browser.calendarScale == .week ? "Previous Week" : "Previous Month")
                .accessibilityIdentifier("CalendarPrevious")
        }
        .hidden(isHidden)
        ToolbarItem(id: "calendarForward") {
            Button("Next", systemImage: "chevron.right") { browser.moveCalendar(by: 1, now: .now) }
                .help(browser.calendarScale == .week ? "Next Week" : "Next Month")
                .accessibilityIdentifier("CalendarNext")
        }
        .hidden(isHidden)
        ToolbarItem(id: "calendarScale") {
            Picker("Scale", selection: Binding { browser.calendarScale } set: { browser.changeCalendarScale($0) }) {
                ForEach(CalendarScale.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .help("Show a Week or a Month")
            .accessibilityIdentifier("CalendarScale")
        }
        .hidden(isHidden)
    }
}

/// The calendar's commands in the View menu, which a hidden toolbar leaves as the way to them.
struct ItemCalendarOptions: View {
    @Bindable var browser: Browser
    /// Whether each command binds its key; the toolbar's copy in View Options leaves them to the menu.
    var bindsKeys = false

    var body: some View {
        let scale = browser.calendarScale
        Button("Go to Today", systemImage: "calendar") { browser.moveCalendar(by: nil, now: .now) }
            .keyboardShortcut(bindsKeys ? KeyboardShortcut("t") : nil)
        Button(scale == .week ? "Previous Week" : "Previous Month", systemImage: "chevron.left") {
            browser.moveCalendar(by: -1, now: .now)
        }
        .keyboardShortcut(bindsKeys ? KeyboardShortcut(.leftArrow, modifiers: [.command, .option]) : nil)
        Button(scale == .week ? "Next Week" : "Next Month", systemImage: "chevron.right") {
            browser.moveCalendar(by: 1, now: .now)
        }
        .keyboardShortcut(bindsKeys ? KeyboardShortcut(.rightArrow, modifiers: [.command, .option]) : nil)
        Picker("Show", selection: Binding { scale } set: { browser.changeCalendarScale($0) }) {
            ForEach(CalendarScale.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.inline)
    }
}
