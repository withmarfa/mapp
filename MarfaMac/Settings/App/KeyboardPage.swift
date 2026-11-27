import SwiftUI

/// The Keyboard page: a shortcut for every menu command the app adds, and the few that work in any app. Each is a field that
/// records the next keys pressed; a shortcut another command holds is shown as taken, with the choice to replace it. The
/// chosen shortcuts drive the menus at once (`ShortcutBindings`).
struct KeyboardPage: View {
    private let libraries: Libraries
    @State private var model: KeyboardPageModel
    @State private var confirmsRestore = false

    init(libraries: Libraries) {
        self.init(libraries: libraries, model: KeyboardPageModel(bindings: libraries.shortcuts, anyApp: libraries.anyAppShortcuts))
    }

    /// A page over a model already in a state, for the renders of the states a window cannot be put in.
    init(libraries: Libraries, model: KeyboardPageModel) {
        self.libraries = libraries
        _model = State(initialValue: model)
    }

    var body: some View {
        SettingsPageColumn {
            HStack {
                Spacer(minLength: 0)
                SettingsShortcutSearch(
                    text: $model.search, byKeys: $model.searchesByKeys, pressed: model.pressed?.display,
                    clearPressed: { model.pressed = nil }
                ) { event in
                    if let shortcut = Shortcut(event: event) { model.pressed = shortcut }
                }
            }
            if !model.hasResults {
                SettingsEmptyCard(
                    symbol: "magnifyingglass", title: Text("No Shortcuts Found"),
                    line: Text(model.searchesByKeys ? "No command has the keys you pressed." : "No command matches your search."))
            }
            if !model.anyAppCommands.isEmpty {
                SettingsSection(
                    "Global Shortcuts", footer: "Off until you set one. They work in any app while Marfa for Mac is open."
                ) {
                    ForEach(model.anyAppCommands, id: \.self) { command in
                        row(command.title, target: .anyApp(command))
                    }
                }
            }
            ForEach(model.sections, id: \.menu) { section in
                SettingsSection(name: Text(verbatim: section.menu.title), line: model.line(forCount: section.commands.count).map { Text(verbatim: $0) }) {
                    ForEach(section.commands) { command in
                        row(command.title, target: .menu(command))
                    }
                }
            }
            if model.searchesByKeys {
                SettingsNote("With the keyboard button on, pressing keys searches for that shortcut. Typing searches by name.")
            }
            if !model.isSearching {
                SettingsBar {
                    SettingsButton("Restore Defaults", small: true) { confirmsRestore = true }
                        .accessibilityIdentifier("RestoreShortcuts")
                    SettingsButton("Export…", small: true) { KeyboardFiles.export(from: libraries) }
                        .accessibilityIdentifier("ExportShortcuts")
                    SettingsButton("Import…", small: true) { KeyboardFiles.importShortcuts(into: libraries) }
                        .accessibilityIdentifier("ImportShortcuts")
                }
            }
        }
        .alert("Restore Default Shortcuts?", isPresented: $confirmsRestore) {
            Button("Restore Defaults") { model.restoreDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every command goes back to its own shortcut, and the shortcuts that work in any app are turned off.")
        }
        .alert(
            "Replace the Shortcut?",
            isPresented: Binding { model.refusal?.canReplace == true } set: { if !$0 { model.cancelRefusal() } }
        ) {
            Button("Replace") { model.replace() }
            Button("Cancel", role: .cancel) { model.cancelRefusal() }
        } message: {
            Text(verbatim: model.refusal.map { "\($0.line) " + String(localized: "It will have none if you replace it.") } ?? "")
        }
        .onDisappear { model.pageDidDisappear() }
        .accessibilityIdentifier("KeyboardPage")
    }

    private func row(_ title: String, target: KeyboardPageModel.Target) -> some View {
        SettingsRow(verbatim: title, error: model.error(for: target), lines: nil) {
            SettingsShortcutField(
                title: LocalizedStringKey(title),
                keys: model.keys(for: target),
                isRecording: model.recording == target,
                isError: model.error(for: target) != nil,
                startRecording: { model.startRecording(target) },
                stopRecording: { model.stopRecording() },
                record: { event in if let shortcut = Shortcut(event: event) { model.record(shortcut) } },
                clear: { model.clear(target) })
        }
    }
}
