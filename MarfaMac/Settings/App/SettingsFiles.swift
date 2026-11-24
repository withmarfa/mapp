import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What Settings > General's Export Settings…, Import Settings… and Restore Earlier Settings… keep while a panel or a sheet is open:
/// the file chosen to import with the sections ticked, or the restore points with the one chosen. The file and the points are
/// made and applied by `PreferencesSync`; this holds the choice, tells the outcome and reads nothing else.
@MainActor @Observable
final class SettingsFilesModel {
    struct Importing {
        let name: String
        let file: SettingsFile
        var chosen: Set<SettingsFile.Section>

        /// The sections the file holds, in the order of Settings' pages. A section it lacks is never offered, since importing
        /// it would put that section back to its defaults.
        var offered: [SettingsFile.Section] { SettingsFile.Section.allCases.filter { file.sections[$0] != nil } }
    }

    struct Restoring {
        let points: [RestorePoint]
        var chosen: RestorePoint.ID?
    }

    enum Sheet {
        case importing(Importing)
        case restoring(Restoring)
    }

    private(set) var sheet: Sheet?
    private(set) var isWorking = false
    @ObservationIgnored private let libraries: Libraries

    init(libraries: Libraries) {
        self.libraries = libraries
        refresh()
    }

    private var preferences: PreferencesSync { libraries.preferences }
    private var notices: Notices { libraries.host.notices }

    func close() {
        guard !isWorking else { return }
        sheet = nil
    }

    // MARK: Export

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "Marfa Settings") + ".json"
        panel.begin { [self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try preferences.settingsFile().encoded().write(to: url, options: .atomic)
            } catch {
                notices.tell(
                    String(localized: "Couldn’t Export Settings"),
                    String(localized: "The settings could not be written to “\(url.lastPathComponent)”. Choose another place and try again."))
            }
        }
    }

    // MARK: Import

    func chooseFileToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [self] response in
            guard response == .OK, let url = panel.url else { return }
            open(url)
        }
    }

    /// Reads the file and offers its sections, or tells why it can't: a file that is not the app's, one from a newer version of the
    /// app, or one that could not be read. A refused file changes no setting.
    func open(_ url: URL) {
        let title = String(localized: "Couldn’t Import Settings")
        let name = url.lastPathComponent
        guard let data = try? Data(contentsOf: url) else {
            notices.tell(title, String(localized: "“\(name)” could not be read. No settings were changed."))
            return
        }
        do throws(SettingsFile.ReadError) {
            let file = try SettingsFile.read(data)
            let sections = Set(file.sections.keys)
            guard !sections.isEmpty else {
                notices.tell(title, String(localized: "“\(name)” holds no settings. No settings were changed."))
                return
            }
            sheet = .importing(Importing(name: name, file: file, chosen: sections))
        } catch {
            let message = switch error {
            case .notOurs: String(localized: "“\(name)” is not a settings file that the app can read. No settings were changed.")
            case .newerVersion: String(localized: "“\(name)” was made by a newer version of the app. Update the app to import it. No settings were changed.")
            }
            notices.tell(title, message)
        }
    }

    func setImport(_ section: SettingsFile.Section, on: Bool) {
        guard case .importing(var importing) = sheet else { return }
        if on { importing.chosen.insert(section) } else { importing.chosen.remove(section) }
        sheet = .importing(importing)
    }

    func runImport() async {
        guard case .importing(let importing) = sheet, !importing.chosen.isEmpty, !isWorking else { return }
        isWorking = true
        defer {
            isWorking = false
            refresh()
        }
        do throws(RestorePoints.Failure) {
            let applied = try await preferences.importSettings(importing.file, sections: importing.chosen)
            sheet = nil
            notices.tell(String(localized: "Imported Settings"), Self.importSummary(applied))
        } catch {
            sheet = nil
            tellNotChanged(String(localized: "Couldn’t Import Settings"))
        }
    }

    // MARK: Restore

    /// The points on this Mac, newest first, as last read: when the page appeared or a step of its own ended.
    private(set) var restorePoints: [RestorePoint] = []

    func refresh() { restorePoints = preferences.listRestorePoints() }

    func chooseRestorePoint() {
        refresh()
        guard !restorePoints.isEmpty else { return }
        sheet = .restoring(Restoring(points: restorePoints, chosen: nil))
    }

    func setRestore(_ point: RestorePoint.ID) {
        guard case .restoring(var restoring) = sheet else { return }
        restoring.chosen = point
        sheet = .restoring(restoring)
    }

    func runRestore() async {
        guard case .restoring(let restoring) = sheet, let point = restoring.chosen, !isWorking else { return }
        isWorking = true
        defer {
            isWorking = false
            refresh()
        }
        do throws(RestorePoints.Failure) {
            let applied = try await preferences.restore(point)
            sheet = nil
            notices.tell(String(localized: "Restored Settings"), Self.restoreSummary(applied, point: restoring.points.first { $0.id == point }))
        } catch {
            sheet = nil
            tellNotChanged(String(localized: "Couldn’t Restore Settings"), unreadable: error == .unreadable)
        }
    }

    // MARK: Words

    private func tellNotChanged(_ title: String, unreadable: Bool = false) {
        notices.tell(
            title,
            unreadable
                ? String(localized: "That restore point can’t be read. No settings were changed.")
                : String(localized: "A restore point could not be saved first, so no settings were changed."))
    }

    /// What an import did: how many settings were applied, or that none changed, and any that were skipped.
    static func importSummary(_ result: PreferencesSync.Applied) -> String {
        let applied = result.applied
        let done = switch applied {
        case 0: String(localized: "No settings changed.")
        case 1: String(localized: "One setting was applied.")
        default: String(localized: "\(applied) settings were applied.")
        }
        return done + skippedSentence(result.skipped)
    }

    /// What a restore did: whose settings are back, and any that were skipped. A point equal to the current settings
    /// applies nothing and still reads as done.
    static func restoreSummary(_ result: PreferencesSync.Applied, point: RestorePoint?) -> String {
        let done = if let point {
            point.reason.backPhrase(RestoreSettingsSheet.when(point.date))
        } else {
            String(localized: "Your earlier settings are back.")
        }
        return done + skippedSentence(result.skipped)
    }

    private static func skippedSentence(_ skipped: Int) -> String {
        switch skipped {
        case 0: ""
        case 1: " " + String(localized: "One was skipped: this version of the app can’t use it.")
        default: " " + String(localized: "\(skipped) were skipped: this version of the app can’t use them.")
        }
    }

    /// What a sheet says about who it reaches, where the settings sync and where they don't.
    func reach(_ importing: Bool) -> String {
        guard preferences.syncs else {
            return importing
                ? String(localized: "Importing changes these settings on this Mac only. A restore point is saved first.")
                : String(localized: "Restoring changes the settings on this Mac only. A restore point is saved first.")
        }
        guard let name = preferences.marfaName else {
            return importing
                ? String(localized: "Importing changes these settings on every Mac connected to this Marfa. A restore point is saved first.")
                : String(localized: "Restoring changes the settings on every Mac connected to this Marfa. A restore point is saved first.")
        }
        return importing
            ? String(localized: "Importing changes these settings on every Mac connected to \(name). A restore point is saved first.")
            : String(localized: "Restoring changes the settings on every Mac connected to \(name). A restore point is saved first.")
    }
}

extension RestorePoint.Reason {
    /// The sentence a restore's notice opens with: whose settings are back, by what the point was saved before and when.
    func backPhrase(_ when: String) -> String {
        switch self {
        case .firstSync: String(localized: "Your settings are back as they were before the first sync, \(when).")
        case .adoption: String(localized: "Your settings are back as they were before taking another Mac’s settings, \(when).")
        case .reset: String(localized: "Your settings are back as they were before Reset, \(when).")
        case .import: String(localized: "Your settings are back as they were before Import, \(when).")
        case .switching: String(localized: "Your settings are back as they were before switching Marfa, \(when).")
        case .restoring: String(localized: "Your settings are back as they were before restoring, \(when).")
        }
    }
}
