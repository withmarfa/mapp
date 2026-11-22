import AppKit

/// The menu of a link in the item's text, asked for by a right-click. Inkkit selects the link, so Edit Link and Remove
/// Link act on it through the page's own commands.
extension EditorController {
    enum LinkChoice: Int, Sendable {
        case open, copy, edit, remove
    }

    struct LinkMenuEntry: Equatable {
        let choice: LinkChoice
        let title: String
        let isEnabled: Bool
    }

    /// What the menu offers, in order. A page that can't be edited offers only what leaves the text alone, and an
    /// address that may not be opened offers Open Link dimmed, so the person sees why nothing opens.
    static func linkMenuEntries(for target: LinkMenuTarget, isEditable: Bool) -> [LinkMenuEntry] {
        var entries: [LinkMenuEntry]
        switch target {
        case .web(_, let href, let openable):
            entries = [
                LinkMenuEntry(choice: .open, title: String(localized: "Open Link"), isEnabled: openable && URL(string: href) != nil),
                LinkMenuEntry(choice: .copy, title: String(localized: "Copy Link"), isEnabled: !href.isEmpty),
            ]
            if isEditable { entries.append(LinkMenuEntry(choice: .edit, title: String(localized: "Edit Link…"), isEnabled: true)) }
        case .item:
            entries = [
                LinkMenuEntry(choice: .open, title: String(localized: "Open"), isEnabled: true),
                LinkMenuEntry(choice: .copy, title: String(localized: "Copy Link"), isEnabled: true),
            ]
        }
        if isEditable { entries.append(LinkMenuEntry(choice: .remove, title: String(localized: "Remove Link"), isEnabled: true)) }
        return entries
    }

    /// Pops the menu up at the pointer, for a link of the item and load the page is on. A request from a page that has
    /// since moved on is ignored, as the menu would act on text the person no longer sees.
    func showLinkMenu(for target: LinkMenuTarget, in item: ItemID, generation: Int, at point: CGPoint, viewportHeight: Double) {
        guard item == pageItemID, generation == self.generation, isReady else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let handler = LinkMenuHandler { [weak self] choice in
            self?.perform(choice, on: target, in: item, generation: generation)
        }
        var separated = false
        for entry in Self.linkMenuEntries(for: target, isEditable: isEditable) {
            // What changes the text is set apart from what only opens or copies.
            if !separated, entry.choice == .edit || entry.choice == .remove {
                separated = true
                menu.addItem(.separator())
            }
            let entryItem = NSMenuItem(title: entry.title, action: #selector(LinkMenuHandler.choose(_:)), keyEquivalent: "")
            entryItem.target = handler
            entryItem.tag = entry.choice.rawValue
            entryItem.isEnabled = entry.isEnabled
            menu.addItem(entryItem)
        }
        popUp(menu, under: containerRect(CGRect(origin: point, size: .zero), viewportHeight: viewportHeight), keeping: handler)
    }

    /// Carries out a choice. Open and Copy act wherever the page is; Edit and Remove write to the item, so they wait
    /// for the same page and load the menu was asked on, and for the item to be editable.
    func perform(_ choice: LinkChoice, on target: LinkMenuTarget, in item: ItemID, generation: Int) {
        switch (choice, target) {
        case (.open, .web(_, let href, let openable)):
            if openable { openAddress(href) }
        case (.open, .item(_, let link)):
            Task { await openItemLink(link, from: item) }
        case (.copy, .web(_, let href, _)):
            copyToPasteboard(href)
        case (.copy, .item(_, let link)):
            copyToPasteboard("[[\(link.raw)]]")
        case (.edit, .web(_, let href, _)):
            guard isLinkEditable(in: item, generation: generation) else { return }
            webLinkRequest = WebLinkRequest(itemID: item, generation: generation, removable: true, address: href)
        case (.remove, .web):
            guard isLinkEditable(in: item, generation: generation) else { return }
            call("format", json("link"), "null", String(generation))
        case (.remove, .item(let text, _)):
            guard isLinkEditable(in: item, generation: generation) else { return }
            call("unlinkSelected", json(text), String(generation))
        case (.edit, .item):
            break
        }
    }

    /// Opens a web, mail or phone address in the system's app. The page has already refused what Inkkit's
    /// `canOpenLink` does not allow.
    func openAddress(_ href: String) {
        if let url = URL(string: href) { NSWorkspace.shared.open(url) }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func isLinkEditable(in item: ItemID, generation: Int) -> Bool {
        hasItem && isEditable && isReady && item == pageItemID && generation == self.generation
    }
}

/// Carries a link menu's choice back to the editor. A menu item holds its target weakly, so the menu's owner keeps this
/// until the person has chosen.
private final class LinkMenuHandler: NSObject {
    let chosen: (EditorController.LinkChoice) -> Void
    init(chosen: @escaping (EditorController.LinkChoice) -> Void) { self.chosen = chosen }
    @objc func choose(_ sender: NSMenuItem) {
        guard let choice = EditorController.LinkChoice(rawValue: sender.tag) else { return }
        chosen(choice)
    }
}
