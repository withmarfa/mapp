import SwiftUI

/// View choices remain in the menu when no document window is in front.
struct ItemViewOptions: View {
    /// Nil while no window is in front, which leaves the choices in the menu, dimmed.
    let browser: Browser?
    /// The layouts the window's place can show; all of them while no window is in front.
    var modes = ItemViewMode.allCases

    var body: some View {
        Group {
            choice("as List", systemImage: ItemViewMode.list.symbol, .list, key: "1")
            choice("as Gallery", systemImage: ItemViewMode.gallery.symbol, .gallery, key: "2")
            choice("as Table", systemImage: ItemViewMode.table.symbol, .table, key: "3")
            choice("as Board", systemImage: ItemViewMode.board.symbol, .board, key: "4")
            choice("as Timeline", systemImage: ItemViewMode.timeline.symbol, .timeline, key: "5")
        }
        .disabled(browser == nil)
    }

    private func identifier(_ mode: ItemViewMode) -> String {
        switch mode {
        case .list: "ViewAsList"
        case .gallery: "ViewAsGallery"
        case .table: "ViewAsTable"
        case .board: "ViewAsBoard"
        case .timeline: "ViewAsTimeline"
        }
    }

    @ViewBuilder
    private func choice(_ title: LocalizedStringKey, systemImage: String, _ mode: ItemViewMode, key: KeyEquivalent) -> some View {
        if modes.contains(mode) {
            Toggle(title, systemImage: systemImage, isOn: Binding { browser?.viewMode == mode } set: { _ in browser?.viewMode = mode })
                .keyboardShortcut(key)
                .accessibilityIdentifier(identifier(mode))
        }
    }
}

/// One pop-up button stays at the window's trailing side whichever view is shown.
struct ViewModeMenu: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        // The tray names an item by the title of its label, which a bare representable has none of, so the pop-up button
        // is the body of a label's style and keeps the label's title for the tray.
        Label("View As", systemImage: browser.viewMode.symbol)
            .labelStyle(ViewModePopUpStyle(modes: browser.availableViewModes(in: library), selection: $browser.viewMode))
            .help("View As")
            .accessibilityIdentifier("ViewModeMenu")
    }
}

private struct ViewModePopUpStyle: LabelStyle {
    let modes: [ItemViewMode]
    @Binding var selection: ItemViewMode

    func makeBody(configuration: Configuration) -> some View {
        ViewModePopUp(modes: modes, selection: $selection).frame(width: 58)
    }
}

/// A pop-up button whose face is the current layout's icon and whose menu is a tick and words, as Finder's View button.
/// SwiftUI's menu picker takes the button's face from the selected row, so the two cannot differ there; the pop-up
/// button's cell can show a menu item of its own (`usesItemFromMenu`) while the menu keeps the rows.
private struct ViewModePopUp: NSViewRepresentable {
    let modes: [ItemViewMode]
    @Binding var selection: ItemViewMode

    private static let titles: [ItemViewMode: String] = [
        .list: String(localized: "as List"), .gallery: String(localized: "as Gallery"), .table: String(localized: "as Table"),
        .board: String(localized: "as Board"), .timeline: String(localized: "as Timeline"),
    ]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.setAccessibilityLabel(String(localized: "View As"))
        (button.cell as? NSPopUpButtonCell)?.usesItemFromMenu = false
        return button
    }

    /// The menu is rebuilt only when the choices change and the face only when the layout does, so a menu that is open
    /// is never replaced while it tracks.
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.selection = $selection
        if coordinator.modes != modes {
            coordinator.modes = modes
            coordinator.shown = nil
            button.removeAllItems()
            for mode in modes {
                let item = NSMenuItem(title: Self.titles[mode] ?? "", action: nil, keyEquivalent: "")
                item.representedObject = mode
                button.menu?.addItem(item)
            }
        }
        guard coordinator.shown != selection else { return }
        coordinator.shown = selection
        if let index = modes.firstIndex(of: selection) { button.selectItem(at: index) }
        let title = Self.titles[selection] ?? ""
        let face = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        face.image = NSImage(systemSymbolName: selection.symbol, accessibilityDescription: nil)
        (button.cell as? NSPopUpButtonCell)?.menuItem = face
        (button.cell as? NSPopUpButtonCell)?.imagePosition = .imageOnly
        button.setAccessibilityValue(title)
    }

    final class Coordinator: NSObject {
        var selection: Binding<ItemViewMode>?
        var modes: [ItemViewMode] = []
        var shown: ItemViewMode?

        @objc func choose(_ sender: NSPopUpButton) {
            if let mode = sender.selectedItem?.representedObject as? ItemViewMode { selection?.wrappedValue = mode }
        }
    }
}

/// The options of the view a window shows, in one menu at the same place on every view's toolbar: after Search
/// (and the table's Filter), before View As. The View menu holds the same options (`CurrentViewOptions`), since a
/// toolbar can be hidden or customized.
struct ViewOptionsMenu: View {
    let browser: Browser

    var body: some View {
        Menu("View Options", systemImage: "slider.horizontal.3") {
            CurrentViewOptions(browser: browser)
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}

/// What can be set about the view a window shows: the order of the list and the gallery, the table's sort,
/// grouping and columns, the board's lanes and cards, and the timeline's dates. Each choice belongs to the place
/// and is kept for the window, except the list's order, which is the app's.
struct CurrentViewOptions: View {
    /// Nil while no window is in front, when the list's order is still the app's to change.
    let browser: Browser?

    var body: some View {
        switch browser?.viewMode {
        case .table: if let browser { ItemTableViewOptions(browser: browser) }
        case .board: if let browser { ItemBoardOptions(browser: browser) }
        case .timeline: if let browser { ItemTimelineOptions(browser: browser) }
        // A collection keeps the order Marfa gives its members, so the app's order does not apply there.
        case .list, .gallery, nil:
            // A saved view has its own sort and group, which the list and the gallery take as the table does.
            if let browser, browser.isViewPlace {
                ItemTableViewOptions(browser: browser, columns: false)
            } else {
                OrderOptions(browser: browser).disabled(browser?.keepsPlaceOrder == true)
            }
            if let browser {
                Divider()
                IncludeSubtypesOption(browser: browser)
            }
        }
    }
}

/// The lanes a board sorts its cards into, and how much each card shows.
struct ItemBoardOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let fields = browser.boardFieldChoices(in: library)
        let field = ItemBoardLayout.selectedField(browser.boardFieldKey(in: browser.item), available: fields)
        Picker("Group by", systemImage: "rectangle.split.3x1", selection: Binding { field?.key ?? "" } set: {
            browser.setBoardField($0, in: browser.item)
        }) {
            ForEach(fields) { Text(verbatim: $0.label).tag($0.key) }
        }
        .pickerStyle(.menu)
        .disabled(fields.isEmpty)
        .accessibilityIdentifier("BoardGroupBy")
        Picker("Card Density", systemImage: "rectangle.compress.vertical", selection: Binding {
            browser.compactBoards[browser.item, default: false]
        } set: { browser.compactBoards[browser.item] = $0 }) {
            Text("Comfortable").tag(false)
            Text("Compact").tag(true)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("BoardCardDensity")
        Divider()
        IncludeSubtypesOption(browser: browser)
    }
}

/// The date a timeline places each item on.
struct ItemTimelineOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let fields = browser.timelineFieldChoices(in: library)
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[browser.item], fields: fields)
        Picker("Date Field", systemImage: "calendar", selection: Binding { field ?? "" } set: {
            browser.setTimelineField($0, in: library)
        }) {
            ForEach(fields) { Text(verbatim: $0.label).tag($0.key) }
        }
        .pickerStyle(.menu)
        .disabled(fields.isEmpty)
        .accessibilityIdentifier("TimelineDateField")
    }
}
