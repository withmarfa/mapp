import AppKit
import UniformTypeIdentifiers

/// The panels and notices of Export Shortcuts and Import Shortcuts. The file is made and read by `ShortcutsFile`.
@MainActor
enum KeyboardFiles {
    static func export(from libraries: Libraries) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "Marfa Shortcuts") + ".json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let file = ShortcutsFile(shortcuts: libraries.shortcuts.current, anyApp: libraries.anyAppShortcuts.current)
                try file.encoded().write(to: url, options: .atomic)
            } catch {
                libraries.host.notices.tell(
                    String(localized: "Couldn’t Export Shortcuts"),
                    String(localized: "The shortcuts could not be written to “\(url.lastPathComponent)”. Choose another place and try again."))
            }
        }
    }

    static func importShortcuts(into libraries: Libraries) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            `import`(url, into: libraries)
        }
    }

    /// Reads the file and applies it, or tells why it was not: a file that is not the app's, one from a newer version of the app, or one that
    /// could not be read. A refused file changes no shortcut.
    static func `import`(_ url: URL, into libraries: Libraries) {
        let title = String(localized: "Couldn’t Import Shortcuts")
        guard let data = try? Data(contentsOf: url) else {
            libraries.host.notices.tell(title, String(localized: "“\(url.lastPathComponent)” could not be read. No shortcuts were changed."))
            return
        }
        do throws(ShortcutsFile.ReadError) {
            let file = try ShortcutsFile.read(data)
            let menu = libraries.shortcuts.apply(file.shortcuts)
            var applied = menu.applied
            var skipped = menu.skipped
            if let anyApp = file.anyApp {
                let result = libraries.anyAppShortcuts.apply(anyApp)
                applied += result.applied
                skipped += result.skipped
            }
            libraries.host.notices.tell(String(localized: "Imported Shortcuts"), summary(applied: applied, skipped: skipped))
        } catch {
            let message = switch error {
            case .notOurs: String(localized: "“\(url.lastPathComponent)” is not a shortcuts file that app can read. No shortcuts were changed.")
            case .newerVersion: String(localized: "“\(url.lastPathComponent)” was made by a newer version of the app. Update the app to import it. No shortcuts were changed.")
            }
            libraries.host.notices.tell(title, message)
        }
    }

    static func summary(applied: Int, skipped: Int) -> String {
        let done = applied == 1 ? String(localized: "One shortcut was imported.") : String(localized: "\(applied) shortcuts were imported.")
        guard skipped > 0 else { return done }
        let left = skipped == 1
            ? String(localized: "One was skipped: the app no longer has its command, or its keys can’t be used.")
            : String(localized: "\(skipped) were skipped: the app no longer has their commands, or their keys can’t be used.")
        return done + " " + left
    }
}
