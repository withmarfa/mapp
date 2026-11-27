import SwiftUI

struct GeneralPage: View {
    let libraries: Libraries
    @State private var files: SettingsFilesModel
    @State private var links = OpenLinksModel()
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
    @State private var isConfirmingRemoval = false
    @State private var isChangingKeptSettings = false
    @State private var settingsProblem: String?

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
        .environment(\.settingsFitsPopUpLabels, true)
        .accessibilityIdentifier("GeneralPage")
        .onAppear { files.refresh() }
        .settingsSheet(presenting: files.sheet != nil, dismiss: { files.close() }) { SettingsFilesSheet(model: files) }
        .alert("Reset This App’s Settings?", isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetSettings() }
        } message: {
            Text(resetMessage)
        }
        .alert(Text(verbatim: keptSettings.removeTitle), isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { removeKeptSettings() }
        } message: {
            Text(keptSettings.removeMessage)
        }
    }

    // MARK: Opening

    private var opening: some View {
        SettingsSection("Opening") {
            SettingsRow("Start with") {
                SettingsPopUp(title: "Start with", selection: $startWith) {
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
            SettingsRow("Reopen windows after quitting") {
                SettingsToggle(title: "Reopen windows after quitting", isOn: $reopensWindows).accessibilityIdentifier("ReopenWindows")
            }
            SettingsRow("Open items in") {
                SettingsPopUp(title: "Open items in", selection: Binding { openItemsIn.asDefault } set: { openItemsIn = $0 }) {
                    ForEach(ItemOpening.defaultChoices) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("OpenItems")
            }
            OpenLinksRow(model: links)
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
        SettingsSection("New Items", footer: "Outside a type’s own list.") {
            SettingsRow("New items are") {
                SettingsPopUp(title: "New items are", selection: $newItemType) {
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
            SettingsRow("New item opens as") {
                SettingsPopUp(title: "New item opens as", selection: $newOpens) {
                    ForEach(NewOpens.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("NewOpens")
            }
        }
    }

    // MARK: Dates and times

    private var dates: some View {
        SettingsSection("Dates and Times") {
            SettingsRow("Say today and yesterday") {
                SettingsToggle(title: "Say today and yesterday", isOn: $dateFormat.usesWords).accessibilityIdentifier("TodayAndYesterday")
            }
            SettingsRow("Week starts on") {
                SettingsPopUp(title: "Week starts on", selection: $weekStart) {
                    Text("System Setting").tag(0)
                    Divider()
                    ForEach(WeekStart.days, id: \.self) { Text(verbatim: Self.weekdayName($0)).tag($0) }
                }
                .accessibilityIdentifier("WeekStartsOn")
            }
            SettingsRow("Date format") {
                SettingsPopUp(title: "Date format", selection: $dateFormat.date) {
                    Text("System Setting").tag(DateFormat.DateStyle.system)
                    Divider()
                    Text("Numeric").tag(DateFormat.DateStyle.numeric)
                    Text("Abbreviated").tag(DateFormat.DateStyle.abbreviated)
                    Text("Long").tag(DateFormat.DateStyle.long)
                }
                .accessibilityIdentifier("DateFormat")
            }
            SettingsRow("Time format") {
                SettingsPopUp(title: "Time format", selection: $dateFormat.time) {
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
            SettingsRow("Load pictures from websites", line: "In saved pages and emails.") {
                SettingsPopUp(title: "Load pictures from websites", selection: $pictures) {
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
                SettingsRow("Send error reports", line: "What went wrong, never your items.") {
                    SettingsToggle(title: "Send error reports", isOn: $sendsReports).accessibilityIdentifier("SendErrorReports")
                }
            }
        }
        .onChange(of: sendsReports) { _, isOn in Reporting.shared.switchChanged(to: isOn) }
    }

    // MARK: Updates

    /// Shown only in a build that updates itself.
    @ViewBuilder private var updates: some View {
        if let updater {
            SettingsSection("Marfa for Mac") {
                SettingsRow(title: Text("Marfa for Mac \(updater.version)"), line: updater.checkSummary.map { Text(verbatim: $0) }, lines: nil) {
                    SettingsButton("Check for Updates") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
                SettingsRow("Check automatically") {
                    SettingsToggle(
                        title: "Check automatically",
                        isOn: Binding { updater.checksAutomatically } set: { updater.checksAutomatically = $0 }
                    )
                    .accessibilityIdentifier("CheckAutomatically")
                }
                SettingsRow("Try beta versions") {
                    SettingsToggle(title: "Try beta versions", isOn: $betaVersions).accessibilityIdentifier("BetaVersions")
                }
            }
        }
    }

    // MARK: This app's settings

    private var appSettings: some View {
        SettingsSection("Settings") {
            keptSettingsRow
            SettingsRow("Export settings") {
                SettingsButton("Export…") { files.export() }
                    .accessibilityIdentifier("ExportSettings")
            }
            SettingsRow("Import settings") {
                SettingsButton("Import…") { files.chooseFileToImport() }
                    .accessibilityIdentifier("ImportSettings")
            }
            SettingsRow("Restore earlier settings", line: files.restorePoints.isEmpty ? "None saved yet." : nil) {
                SettingsButton("Restore…") { files.chooseRestorePoint() }
                    .disabled(files.restorePoints.isEmpty)
                    .accessibilityIdentifier("RestoreSettings")
            }
            SettingsRow("Reset settings", line: libraries.preferences.syncs ? "On every Mac that connects to this Marfa. Your items stay." : "Every setting on this Mac. Your items stay.") {
                SettingsButton("Reset", role: .destructive) { isConfirmingReset = true }
                    .accessibilityIdentifier("ResetSettings")
            }
        }
    }

    private var keptSettings: ConnectionSettings {
        ConnectionSettings(standing: libraries.preferences.standing, name: LibraryDescription.name(libraries))
    }

    @ViewBuilder private var keptSettingsRow: some View {
        let words = keptSettings
        if libraries.host.configuredConnection != nil, words.isShown {
            SettingsRow(verbatim: words.title, line: words.line, error: settingsProblem, lines: nil) {
                if let title = words.actionTitle {
                    let buttonTitle = words.action == .allowMore && libraries.marfaSettings.isAllowingMore
                        ? String(localized: "Waiting…") : title
                    SettingsButton(title: Text(verbatim: buttonTitle), role: words.action == .remove ? .destructive : .normal) {
                        act(on: words.action)
                    }
                    .disabled(isChangingKeptSettings || libraries.marfaSettings.isAllowingMore)
                    .accessibilityIdentifier(words.action == .remove ? "RemoveAppSettings" :
                        words.action == .keepAgain ? "KeepAppSettingsAgain" : "AllowMoreForAppSettings")
                }
            }
            .accessibilityIdentifier("AppSettingsRow")
        }
    }

    private func act(on action: ConnectionSettings.Action) {
        settingsProblem = nil
        switch action {
        case .remove:
            isConfirmingRemoval = true
        case .allowMore:
            let model = libraries.marfaSettings
            Task {
                if await model.allowMore([]) == .failed {
                    settingsProblem = model.notice?.message ?? String(localized: "That didn’t work. Try again in a moment.")
                }
            }
        case .keepAgain:
            changeKeptSettings { try await libraries.preferences.startAgain() }
        case .none:
            break
        }
    }

    private func changeKeptSettings(_ step: @escaping () async throws -> Void) {
        isChangingKeptSettings = true
        Task {
            defer { isChangingKeptSettings = false }
            do {
                try await step()
            } catch {
                settingsProblem = String(localized: "That didn’t work. Try again in a moment.")
            }
        }
    }

    private func removeKeptSettings() {
        changeKeptSettings { try await libraries.preferences.remove() }
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
