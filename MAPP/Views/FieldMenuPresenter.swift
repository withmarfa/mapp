import AppKit

/// Draws a field's menu (`FieldMenu`) as a menu under the field's name and hands back what the person chose. The model
/// decides what is offered and what is dimmed; this only gives each command its words and its symbol.
@MainActor
enum FieldMenuPresenter {
    /// Keeps the menu's targets alive until the menu closes, since an item holds its target weakly.
    private final class Choice: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire(_ sender: NSMenuItem) { run() }
    }

    static func title(of command: FieldMenu.Command, typeLabel: String) -> String {
        switch command {
        case .editValue: String(localized: "Edit Value")
        case .rename: String(localized: "Rename Field…")
        case .editChoices: String(localized: "Edit Choices…")
        case .remove: String(localized: "Remove Field…")
        case .pin: String(localized: "Pin Under the Title")
        case .unpin: String(localized: "Unpin from Under the Title")
        case .moveUp: String(localized: "Move Up")
        case .moveDown: String(localized: "Move Down")
        case .hide: typeLabel.isEmpty ? String(localized: "Hide on the Type’s Pages") : String(localized: "Hide on \(typeLabel) Pages")
        }
    }

    private static func symbol(of command: FieldMenu.Command) -> String? {
        switch command {
        case .editValue: "pencil"
        case .rename: "character.cursor.ibeam"
        case .editChoices: "list.bullet"
        case .remove: "trash"
        case .pin: "pin"
        case .unpin: "pin.slash"
        case .moveUp: "arrow.up"
        case .moveDown: "arrow.down"
        case .hide: "eye.slash"
        }
    }

    /// The menu and what keeps it working. `typeLabel` names the type whose pages a hide affects. `choose` runs once, with
    /// the command, after the menu closes on a choice.
    static func build(
        _ menu: FieldMenu, typeLabel: String, choose: @escaping (FieldMenu.Command) -> Void
    ) -> (menu: NSMenu, keeping: AnyObject) {
        let result = NSMenu()
        result.autoenablesItems = false
        var keep: [Choice] = []
        if let lock = menu.lockText {
            let note = NSMenuItem(title: lock, action: nil, keyEquivalent: "")
            note.image = NSImage(systemSymbolName: "lock", accessibilityDescription: nil)
            note.isEnabled = false
            result.addItem(note)
            if !menu.sections.isEmpty { result.addItem(.separator()) }
        }
        for (index, section) in menu.sections.enumerated() {
            if index > 0 { result.addItem(.separator()) }
            for entry in section {
                let chosen = Choice { choose(entry.command) }
                keep.append(chosen)
                let words = title(of: entry.command, typeLabel: typeLabel)
                let item = NSMenuItem(title: words, action: #selector(Choice.fire(_:)), keyEquivalent: "")
                item.target = chosen
                item.isEnabled = entry.isEnabled
                if let name = symbol(of: entry.command) { item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil) }
                // A menu item has no destructive role of its own, so the removal is drawn red as the alert's button is.
                if entry.command == .remove, entry.isEnabled {
                    item.attributedTitle = NSAttributedString(string: words, attributes: [.foregroundColor: NSColor.systemRed])
                    item.image = item.image?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
                }
                result.addItem(item)
            }
        }
        return (result, keep as AnyObject)
    }
}
