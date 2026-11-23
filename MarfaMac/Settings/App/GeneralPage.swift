import SwiftUI

/// The General page: how the app opens, what a new item is, how dates and times read, what the app does with the web, and
/// putting every setting back.
struct GeneralPage: View {
    let libraries: Libraries
    @AppStorage(StartWith.key) private var startWith = StartWith.standard
    @AppStorage(ReopenWindows.key) private var reopensWindows = ReopenWindows.standard
    @AppStorage(ListKey.openItemsIn) private var openItemsIn = ItemOpening.standard
    @AppStorage(NewItemType.key) private var newItemType = ""
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(WeekStart.key) private var weekStart = 0
    @AppStorage(RemotePictureSetting.key) private var pictures = RemotePictureSetting.standard
    @AppStorage(Reporting.switchKey) private var sendsReports = true
    @Environment(\.library) private var library
    @State private var isConfirmingReset = false

    var body: some View {
        SettingsPageColumn {
            opening
            newItems
            dates
            privacy
            reset
        }
        .accessibilityIdentifier("GeneralPage")
        .alert("Reset This App’s Settings?", isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetSettings() }
        } message: {
            Text(resetMessage)
        }
    }

    // MARK: Opening

    private var opening: some View {
        SettingsSection("Opening") {
            SettingsRow("Start With", line: "What a new window shows.") {
                SettingsPopUp(title: "Start With", selection: $startWith) {
                    Text("Where I Left Off").tag(StartWith.leftOff)
                    Divider()
                    Text("Inbox").tag(StartWith.place(.inbox))
                    Text("Recents").tag(StartWith.place(.recents))
                    Text("All Items").tag(StartWith.place(.allItems))
                    Text("Favorites").tag(StartWith.place(.favorites))
                    let types = library?.itemTypeCounts ?? []
                    if !types.isEmpty {
                        Divider()
                        ForEach(types) { Text(verbatim: $0.label).tag(StartWith.place(.itemType($0.id.rawValue))) }
                    }
                    if let missing = missingStart(among: types) {
                        Divider()
                        Text(verbatim: missing).tag(startWith)
                    }
                }
                .accessibilityIdentifier("StartWith")
            }
            SettingsRow("Reopen Windows", line: "After you quit Marfa.") {
                SettingsToggle(title: "Reopen Windows", isOn: $reopensWindows).accessibilityIdentifier("ReopenWindows")
            }
            SettingsRow("Open Items", line: "From a list or a search.") {
                SettingsPopUp(title: "Open Items", selection: $openItemsIn) {
                    ForEach(ItemOpening.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("OpenItems")
            }
        }
    }

    /// The pop-up's line for a stored place the library does not list, or nil where the choice is one the pop-up offers.
    private func missingStart(among types: [ItemTypeCount]) -> String? {
        guard case .place(let place) = startWith else { return nil }
        switch place {
        case .inbox, .recents, .allItems, .favorites: return nil
        case .itemType(let identifier) where types.contains(where: { $0.id.rawValue == identifier }): return nil
        default: return missingName(MissingChoice.placeName(place))
        }
    }

    /// With no library open nothing can be said to be missing, so the name stands alone.
    private func missingName(_ name: String) -> String {
        library == nil ? name : MissingChoice.label(name)
    }

    // MARK: New items

    private var newItems: some View {
        SettingsSection("New Items") {
            SettingsRow("New Items Are", line: "Outside a type’s own list.") {
                SettingsPopUp(title: "New Items Are", selection: $newItemType) {
                    Text("Last Used").tag("")
                    let types = library.map { QuickAdd.types(in: $0) } ?? []
                    if !types.isEmpty {
                        Divider()
                        ForEach(types) { Text(verbatim: $0.label).tag($0.id.rawValue) }
                    }
                    if !newItemType.isEmpty, !types.contains(where: { $0.id.rawValue == newItemType }) {
                        Divider()
                        Text(verbatim: missingName(MissingChoice.typeName(newItemType))).tag(newItemType)
                    }
                }
                .accessibilityIdentifier("NewItemsAre")
            }
        }
    }

    // MARK: Dates and times

    private var dates: some View {
        SettingsSection("Dates and Times") {
            SettingsRow("Today and Yesterday", line: "Instead of the date, when it’s recent.") {
                SettingsToggle(title: "Today and Yesterday", isOn: $dateFormat.usesWords).accessibilityIdentifier("TodayAndYesterday")
            }
            SettingsRow("Week Starts On") {
                SettingsPopUp(title: "Week Starts On", selection: $weekStart) {
                    Text("System Setting").tag(0)
                    Divider()
                    ForEach(WeekStart.days, id: \.self) { Text(verbatim: Self.weekdayName($0)).tag($0) }
                }
                .accessibilityIdentifier("WeekStartsOn")
            }
            SettingsRow("Date Format") {
                SettingsPopUp(title: "Date Format", selection: $dateFormat.date) {
                    Text("System Setting").tag(DateFormat.DateStyle.system)
                    Divider()
                    Text("Numeric").tag(DateFormat.DateStyle.numeric)
                    Text("Abbreviated").tag(DateFormat.DateStyle.abbreviated)
                    Text("Long").tag(DateFormat.DateStyle.long)
                }
                .accessibilityIdentifier("DateFormat")
            }
            SettingsRow("Time Format") {
                SettingsPopUp(title: "Time Format", selection: $dateFormat.time) {
                    Text("System Setting").tag(DateFormat.TimeStyle.system)
                    Divider()
                    Text("12-Hour").tag(DateFormat.TimeStyle.twelveHour)
                    Text("24-Hour").tag(DateFormat.TimeStyle.twentyFourHour)
                }
                .accessibilityIdentifier("TimeFormat")
            }
        }
    }

    /// A weekday's name in the Mac's language, for the weekday numbered as calendars number them.
    static func weekdayName(_ weekday: Int, in calendar: Calendar = .current) -> String {
        calendar.weekdaySymbols[weekday - 1]
    }

    // MARK: Privacy

    private var privacy: some View {
        SettingsSection("Privacy") {
            SettingsRow("Pictures from Websites", line: "In saved pages and emails.") {
                SettingsPopUp(title: "Pictures from Websites", selection: $pictures) {
                    ForEach(RemotePictureSetting.allCases) { option in
                        switch option {
                        case .ask: Text("Ask").tag(option)
                        case .always: Text("Always").tag(option)
                        case .never: Text("Never").tag(option)
                        }
                    }
                }
                .accessibilityIdentifier("RemotePictures")
            }
            if Reporting.carriesDestination {
                SettingsRow("Send Error Reports", line: "What went wrong, never your items.") {
                    SettingsToggle(title: "Send Error Reports", isOn: $sendsReports).accessibilityIdentifier("SendErrorReports")
                }
            }
        }
        .onChange(of: sendsReports) { _, isOn in Reporting.shared.switchChanged(to: isOn) }
    }

    // MARK: Reset

    private var reset: some View {
        SettingsSection("Reset") {
            SettingsRow("Reset This App’s Settings", line: libraries.preferences.syncs ? "On every Mac that connects to this Marfa. Your items stay." : "Every setting on this Mac. Your items stay.") {
                SettingsButton("Reset…", role: .destructive) { isConfirmingReset = true }
                    .accessibilityIdentifier("ResetSettings")
            }
        }
    }

    /// Where the settings sync, a reset reaches every Mac that connects to the Marfa.
    private var resetMessage: String {
        guard libraries.preferences.syncs else { return String(localized: "Every setting on this Mac starts over. Your items and sign-in stay.") }
        guard let name = libraries.preferences.marfaName else {
            return String(localized: "This app’s settings start over on every Mac that connects to this Marfa. Your items and sign-in stay.")
        }
        return String(localized: "This app’s settings start over on every Mac that connects to \(name). Your items and sign-in stay.")
    }

    private func resetSettings() {
        libraries.resetMacSettings()
        Reporting.shared.switchChanged(to: true)
    }
}
