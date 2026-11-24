import SwiftUI

/// The sheet Import Settings… opens for a good file: a box for each section the file holds.
struct ImportSettingsSheet: View {
    let model: SettingsFilesModel
    let importing: SettingsFilesModel.Importing

    var body: some View {
        SettingsSheet(title: Text("Import Settings"), line: Text("Choose what to replace with the settings in “\(importing.name)”.")) {
            SettingsSection(name: Text("Settings"), footer: Text(verbatim: model.reach(true))) {
                ForEach(importing.offered, id: \.self) { section in
                    SettingsCheckRow(
                        verbatim: section.title,
                        isOn: Binding { importing.chosen.contains(section) } set: { model.setImport(section, on: $0) })
                }
            }
        } buttons: {
            SettingsButton("Cancel") { model.close() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("ImportSettingsCancel")
            SettingsButton("Import", role: .confirm) { Task { await model.runImport() } }
                .disabled(importing.chosen.isEmpty)
                .accessibilityIdentifier("ImportSettingsConfirm")
        }
        .disabled(model.isWorking)
        .accessibilityIdentifier("ImportSettingsSheet")
    }
}

/// The sheet Restore Earlier Settings… opens: the restore points, newest first, of which one is chosen.
struct RestoreSettingsSheet: View {
    let model: SettingsFilesModel
    let restoring: SettingsFilesModel.Restoring

    var body: some View {
        SettingsSheet(title: Text("Restore Earlier Settings"), line: Text("Choose the settings to go back to.")) {
            SettingsSection(name: Text("Restore Points"), footer: Text(verbatim: model.reach(false))) {
                ForEach(restoring.points) { point in
                    SettingsCheckRow(
                        verbatim: point.reason.title, line: Self.when(point.date),
                        isOn: Binding { restoring.chosen == point.id } set: { if $0 { model.setRestore(point.id) } })
                }
            }
        } buttons: {
            SettingsButton("Cancel") { model.close() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("RestoreSettingsCancel")
            SettingsButton("Restore", role: .confirm) { Task { await model.runRestore() } }
                .disabled(restoring.chosen == nil)
                .accessibilityIdentifier("RestoreSettingsConfirm")
        }
        .disabled(model.isWorking)
        .accessibilityIdentifier("RestoreSettingsSheet")
    }

    /// "23 Nov 14:02", in the Mac's language and clock. The day and the time are formatted apart, since the system joins a
    /// date and a time with "at".
    static func when(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated)) + " " + date.formatted(.dateTime.hour().minute())
    }
}

/// Whichever sheet the model holds.
struct SettingsFilesSheet: View {
    let model: SettingsFilesModel

    var body: some View {
        switch model.sheet {
        case .importing(let importing): ImportSettingsSheet(model: model, importing: importing)
        case .restoring(let restoring): RestoreSettingsSheet(model: model, restoring: restoring)
        case nil: EmptyView()
        }
    }
}
