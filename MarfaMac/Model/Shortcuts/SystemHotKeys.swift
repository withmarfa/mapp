import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// Registers the any-app shortcuts with the system through the KeyboardShortcuts package, which wraps Carbon's
/// `RegisterEventHotKey`: it needs no Accessibility permission. A hot key is registered only
/// while it is set (`AnyAppShortcuts`), so an off shortcut takes no key from any other app.
struct SystemHotKeys: HotKeyRegistrar {
    private func name(of command: AnyAppCommand) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("anyApp\(command.rawValue.prefix(1).uppercased())\(command.rawValue.dropFirst())")
    }

    private func package(_ shortcut: Shortcut) -> KeyboardShortcuts.Shortcut? {
        shortcut.keyCode.map { KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: $0), modifiers: Self.flags(shortcut.modifiers)) }
    }

    /// The package registers a hot key without saying whether another app already holds it, so the key is tried first. The
    /// name lets go of its own key before the try, and takes it back if the new one cannot be had.
    func register(_ shortcut: Shortcut, for command: AnyAppCommand, action: @escaping @MainActor () -> Void) -> Bool {
        guard let wanted = package(shortcut) else { return false }
        let name = name(of: command)
        let previous = KeyboardShortcuts.getShortcut(for: name)
        KeyboardShortcuts.removeHandler(for: name)
        func install(_ shortcut: KeyboardShortcuts.Shortcut) {
            KeyboardShortcuts.onKeyUp(for: name) { MainActor.assumeIsolated { action() } }
            KeyboardShortcuts.setShortcut(shortcut, for: name)
        }
        guard Self.canRegister(wanted) else {
            if let previous, previous != wanted { install(previous) }
            return false
        }
        install(wanted)
        return true
    }

    func unregister(_ command: AnyAppCommand) {
        let name = name(of: command)
        KeyboardShortcuts.removeHandler(for: name)
        KeyboardShortcuts.setShortcut(nil, for: name)
    }

    func isTakenBySystem(_ shortcut: Shortcut) -> Bool { package(shortcut)?.isTakenBySystem ?? false }

    func setSuspended(_ suspended: Bool) { KeyboardShortcuts.isEnabled = !suspended }

    private static func canRegister(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.carbonKeyCode), UInt32(shortcut.carbonModifiers), EventHotKeyID(signature: OSType(0x4D50_5052), id: 1),
            GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr else { return false }
        if let reference { UnregisterEventHotKey(reference) }
        return true
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
