import AppKit

/// The modifier keys of a shortcut. Stored as a number of its own, so a file or a setting written today reads the same
/// whatever AppKit or SwiftUI number their own modifiers by.
nonisolated struct ShortcutModifiers: OptionSet, Hashable, Codable, Sendable {
    let rawValue: Int

    static let control = ShortcutModifiers(rawValue: 1)
    static let option = ShortcutModifiers(rawValue: 2)
    static let shift = ShortcutModifiers(rawValue: 4)
    static let command = ShortcutModifiers(rawValue: 8)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: ShortcutModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }

    /// The symbols in the order the system writes them.
    var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

/// A key and its modifiers, as a menu item or a hot key takes them: `key` is the character the key makes with no modifier
/// held (a named key, such as an arrow, is its private-use character, as SwiftUI's `KeyEquivalent` has it), and `keyCode`
/// is the key's own number, which a hot key needs and a recording always knows. Two shortcuts are equal when they press
/// the same key with the same modifiers, whether or not the code is known.
nonisolated struct Shortcut: Hashable, Codable, Sendable {
    var key: String
    var modifiers: ShortcutModifiers
    var keyCode: Int?

    init(key: String, modifiers: ShortcutModifiers, keyCode: Int? = nil) {
        self.key = key
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    static func == (left: Shortcut, right: Shortcut) -> Bool { left.key == right.key && left.modifiers == right.modifiers }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers)
    }

    /// What a key press makes, or nil for one that is no shortcut: a key with no character (a modifier alone) or a press
    /// that is not a key going down.
    @MainActor
    init?(event: NSEvent) {
        guard event.type == .keyDown,
              let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers,
              characters.count == 1, let first = characters.unicodeScalars.first, first.value >= 0x20 || Self.controlKeys.contains(first.value)
        else { return nil }
        self.init(key: characters.lowercased(), modifiers: ShortcutModifiers(event.modifierFlags), keyCode: Int(event.keyCode))
    }

    /// Return, Tab, Escape and Delete, which the system gives as control characters.
    private static let controlKeys: Set<UInt32> = [0x0D, 0x03, 0x09, 0x1B, 0x08, 0x7F]

    // MARK: Writing

    /// The shortcut as a menu writes it: modifiers first in the system's order, then the key.
    var display: String { modifiers.symbols + Self.name(of: key) }

    private static func name(of key: String) -> String {
        named[key] ?? key.uppercased()
    }

    private static func scalar(_ value: Int) -> String { String(UnicodeScalar(UInt32(value))!) }

    private static let named: [String: String] = {
        var names: [String: String] = [
            scalar(NSUpArrowFunctionKey): "↑", scalar(NSDownArrowFunctionKey): "↓", scalar(NSLeftArrowFunctionKey): "←",
            scalar(NSRightArrowFunctionKey): "→", scalar(NSDeleteFunctionKey): "⌦", scalar(NSHomeFunctionKey): "↖",
            scalar(NSEndFunctionKey): "↘", scalar(NSPageUpFunctionKey): "⇞", scalar(NSPageDownFunctionKey): "⇟",
            "\u{8}": "⌫", "\u{7F}": "⌫", "\r": "↩", "\u{3}": "⌤", "\t": "⇥", "\u{1B}": "⎋", " ": "Space",
        ]
        for number in 1...12 { names[scalar(NSF1FunctionKey + number - 1)] = "F\(number)" }
        return names
    }()

    /// Whether the key is a function key, which needs no modifier to be a shortcut.
    var isFunctionKey: Bool {
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else { return false }
        return (UInt32(NSF1FunctionKey)...UInt32(NSF12FunctionKey)).contains(scalar.value)
    }

    // MARK: Rules

    /// What makes a shortcut unfit where it would be used, or nil when it fits.
    enum Problem: Equatable, Sendable {
        /// A menu shortcut needs ⌘, ⌃ or ⌥ (or is a function key), since a bare key is typing.
        case needsModifier
        /// A shortcut that works in any app needs ⌘ or ⌃: Option alone fails on recent macOS.
        case needsCommandOrControl
        /// A shortcut that works in any app needs the key's own number, which a file written by hand may leave out.
        case unknownKey
    }

    /// For a menu command.
    var menuProblem: Problem? {
        if modifiers.isDisjoint(with: [.command, .control, .option]) && !isFunctionKey { return .needsModifier }
        return nil
    }

    /// For a shortcut that works in any app, while MAPP is running.
    var anyAppProblem: Problem? {
        if modifiers.isDisjoint(with: [.command, .control]) { return .needsCommandOrControl }
        if keyCode == nil { return .unknownKey }
        return nil
    }
}
