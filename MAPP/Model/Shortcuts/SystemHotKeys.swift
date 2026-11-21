import AppKit
import KeyboardShortcuts

/// Registers the any-app shortcuts with the system through the KeyboardShortcuts package, which wraps Carbon's
/// `RegisterEventHotKey`: it needs no Accessibility permission and works in the sandbox. A hot key is registered only
/// while it is set (`AnyAppShortcuts`), so an off shortcut takes no key from any other app.
struct SystemHotKeys: HotKeyRegistrar {
    private func name(of command: AnyAppCommand) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("anyApp\(command.rawValue.prefix(1).uppercased())\(command.rawValue.dropFirst())")
    }

    func register(_ shortcut: Shortcut, for command: AnyAppCommand, action: @escaping @MainActor () -> Void) {
        guard let code = shortcut.keyCode else { return }
        let name = name(of: command)
        KeyboardShortcuts.removeHandler(for: name)
        KeyboardShortcuts.onKeyUp(for: name) { MainActor.assumeIsolated { action() } }
        KeyboardShortcuts.setShortcut(
            KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: code), modifiers: Self.flags(shortcut.modifiers)), for: name)
    }

    func unregister(_ command: AnyAppCommand) {
        let name = name(of: command)
        KeyboardShortcuts.removeHandler(for: name)
        KeyboardShortcuts.setShortcut(nil, for: name)
    }

    private static func flags(_ modifiers: ShortcutModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }
}
