import SwiftUI

/// The General page: how the app opens, what a new item is, how dates and times read, what the app does with the web, and
/// this app's settings: saving them to a file, bringing them back and starting them over.
struct GeneralPage: View {
    let libraries: Libraries
    @State private var files: SettingsFilesModel
    @AppStorage(StartWith.key) private var startWith = StartWith.standard
    @AppStorage(ReopenWindows.key) private var reopensWindows = ReopenWindows.standard
    @AppStorage(ListKey.openItemsIn) private var openItemsIn = ItemOpening.standard
    @AppStorage(NewItemType.key) private var newItemType = ""
    @AppStorage(NewOpens.key) private var newOpens = NewOpens.line
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(WeekStart.key) private var weekStart = 0
    @AppStorage(RemotePictureSetting.key) private var pictures = RemotePictureSetting.standard
    @AppStorage(Reporting.switchKey) private var sendsReports = true
    @AppStorage(UpdateSettings.betaKey) private var betaVersions = false
    @Environment(\.library) private var library
    @Environment(\.appUpdater) private var updater
    @State private var isConfirmingReset = false

    init(libraries: Libraries) {
        self.libraries = libraries
        _files = State(initialValue: SettingsFilesModel(libraries: libraries))
    }

    var body: some View {
        SettingsPageColumn {
            opening
            newItems
            dates
            privacy
            updates
            appSettings
        }
        .accessibilityIdentifier("GeneralPage")
        .onAppear { files.refresh() }
        .settingsSheet(presenting: files.sheet != nil, dismiss: { files.close() }) { SettingsFilesSheet(model: files) }
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
                    Text("Library").tag(StartWith.place(.library))
                    Text("Feed").tag(StartWith.place(.feed))
                    Text("Favorites").tag(StartWith.place(.favorites))
                    let types = library?.itemTypeCounts ?? []
                    if !types.isEmpty {
                        Divider()
                        ForEach(types) { Text(verbatim: $0.label).tag(StartWith.place(.type($0.id))) }
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
        guard case .place(let place, let item) = startWith else { return nil }
        if item == nil, [.library, .feed, .favorites].contains(place) { return nil }
        if item == nil, place.view == .own, case .type(let type) = place.place, types.contains(where: { $0.id == type }) { return nil }
        return missingName(MissingChoice.placeName(place))
    }

    /// With no library open nothing can be said to be missing, so the name stands alone.
    private func missingName(_ name: String) -> String {
        library == nil ? name : MissingChoice.label(name)
    }

    // MARK: New items

    private var newItems: some View {
        SettingsSection("New Items") {
            SettingsRow("New Opens", line: "One line, or a form that also takes text and files.") {
                SettingsPopUp(title: "New Opens", selection: $newOpens) {
                    ForEach(NewOpens.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("NewOpens")
            }
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

    // MARK: Updates

    /// Shown only in a build that updates itself.
    @ViewBuilder private var updates: some View {
        if let updater {
            SettingsSection("Updates") {
                SettingsRow("Check Automatically", line: "Look for a new version once a day.") {
                    SettingsToggle(
                        title: "Check Automatically",
                        isOn: Binding { updater.checksAutomatically } set: { updater.checksAutomatically = $0 }
                    )
                    .accessibilityIdentifier("CheckAutomatically")
                }
                SettingsRow("Beta Versions", line: "Try new versions before they’re released.") {
                    SettingsToggle(title: "Beta Versions", isOn: $betaVersions).accessibilityIdentifier("BetaVersions")
                }
            }
        }
    }

    // MARK: This app's settings

    private var appSettings: some View {
        SettingsSection("This App’s Settings") {
            SettingsRow("Export Settings", line: "Save every setting to a file.") {
                SettingsButton("Export…") { files.export() }
                    .accessibilityIdentifier("ExportSettings")
            }
            SettingsRow("Import Settings", line: "Replace settings with those in a file.") {
                SettingsButton("Import…") { files.chooseFileToImport() }
                    .accessibilityIdentifier("ImportSettings")
            }
            SettingsRow(
                "Restore Earlier Settings", line: files.restorePoints.isEmpty ? "None saved yet." : "Go back to settings saved before a change.",
                look: files.restorePoints.isEmpty ? .off : .normal
            ) {
                SettingsButton("Restore…") { files.chooseRestorePoint() }
                    .accessibilityIdentifier("RestoreSettings")
            }
            SettingsRow("Reset This App’s Settings", line: libraries.preferences.syncs ? "On every Mac that connects to this Marfa. Your items stay." : "Every setting on this Mac. Your items stay.") {
                SettingsButton("Reset…", role: .destructive) { isConfirmingReset = true }
                    .accessibilityIdentifier("ResetSettings")
            }
        }
    }

    /// Where the settings sync, a reset reaches every Mac that connects to the Marfa. Either way a restore point is saved first.
    private var resetMessage: String {
        guard libraries.preferences.syncs else {
            return String(localized: "Every setting on this Mac starts over. Your items and sign-in stay. A restore point is saved first, and Restore Earlier Settings brings it back.")
        }
        guard let name = libraries.preferences.marfaName else {
            return String(localized: "This app’s settings start over on every Mac that connects to this Marfa. Your items and sign-in stay. A restore point is saved first, and Restore Earlier Settings brings it back.")
        }
        return String(localized: "This app’s settings start over on every Mac that connects to \(name). Your items and sign-in stay. A restore point is saved first, and Restore Earlier Settings brings it back.")
    }

    private func resetSettings() {
        // Only once the settings are reset, so a Reset that waits for a sync step and then cannot save its restore point
        // leaves the updater and reporting as their switches still read.
        libraries.resetMacSettings { [updater, files] in
            updater?.resetChoices()
            Reporting.shared.switchChanged(to: true)
            files.refresh()
        }
    }
}

extension EnvironmentValues {
    /// The updater this page offers choices for, or nil where the build has none.
    @Entry var appUpdater: AppUpdater?
}
