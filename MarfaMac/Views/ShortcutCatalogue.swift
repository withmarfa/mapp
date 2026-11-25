import SwiftUI

/// Every menu command the app adds that a person can give a shortcut, in the order of the menus. The menus bind these
/// through `ShortcutBindings`, and Settings > Keyboard lists them, so the two cannot differ. A command the system adds
/// (Copy, Quit) is not here.
nonisolated extension ShortcutCommand {
    private static let arrows: [String: String] = [
        "up": String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!), "down": String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!),
        "left": String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!), "right": String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!),
    ]

    static let settings = ShortcutCommand("settings", in: .app, String(localized: "Settings…"), ",")

    static let newItem = ShortcutCommand("newItem", in: .file, String(localized: "New Item"), "n")
    static let newWindow = ShortcutCommand("newWindow", in: .file, String(localized: "New Window"), "n", [.command, .option])
    static let refresh = ShortcutCommand("refresh", in: .file, String(localized: "Refresh"), "r")
    static let open = ShortcutCommand("open", in: .file, String(localized: "Open"))
    static let openAsModal = ShortcutCommand("openAsModal", in: .file, String(localized: "Open as Modal"))
    static let openAsFullPage = ShortcutCommand("openAsFullPage", in: .file, String(localized: "Open as Full Page"))
    static let openInNewWindow = ShortcutCommand("openInNewWindow", in: .file, String(localized: "Open in New Window"), "o")
    static let quickLook = ShortcutCommand("quickLook", in: .file, String(localized: "Quick Look"))
    static let openOriginal = ShortcutCommand("openOriginal", in: .file, String(localized: "Open Original"))
    static let openInBrowser = ShortcutCommand("openInBrowser", in: .file, String(localized: "Open in Browser"))
    static let favorite = ShortcutCommand("favorite", in: .file, String(localized: "Add to Favorites"))
    static let addTag = ShortcutCommand("addTag", in: .file, String(localized: "Add Tag…"))
    static let changeType = ShortcutCommand("changeType", in: .file, String(localized: "Change Type…"))
    static let customizeLayout = ShortcutCommand("customizeLayout", in: .file, String(localized: "Customize Layout…"))
    static let versionHistory = ShortcutCommand("versionHistory", in: .file, String(localized: "Version History…"))
    static let keepInLibrary = ShortcutCommand("keepInLibrary", in: .file, String(localized: "Keep in Library"), "k", [.control, .command])
    static let moveToFeed = ShortcutCommand("moveToFeed", in: .file, String(localized: "Move to Feed"))
    static let archive = ShortcutCommand("archive", in: .file, String(localized: "Archive or Unarchive"), "a", [.control, .command])
    static let delete = ShortcutCommand("delete", in: .file, String(localized: "Delete"))
    static let exportPDF = ShortcutCommand("exportPDF", in: .file, String(localized: "Export as PDF…"))
    static let print = ShortcutCommand("print", in: .file, String(localized: "Print…"), "p")

    static let copyLink = ShortcutCommand("copyLink", in: .edit, String(localized: "Copy Link"), "c", [.command, .shift])
    static let addAttachment = ShortcutCommand("addAttachment", in: .edit, String(localized: "Add Attachment…"), "a", [.command, .shift])
    static let searchItems = ShortcutCommand("searchItems", in: .edit, String(localized: "Search Items…"), "p", [.command, .shift])
    static let commandPalette = ShortcutCommand("commandPalette", in: .edit, String(localized: "Command Palette"), "k")
    static let paletteActions = ShortcutCommand("paletteActions", in: .edit, String(localized: "Palette Actions"), "j")
    static let searchList = ShortcutCommand("searchList", in: .edit, String(localized: "Search List"), "f", [.command, .option])
    static let find = ShortcutCommand("find", in: .edit, String(localized: "Find…"), "f")
    static let findNext = ShortcutCommand("findNext", in: .edit, String(localized: "Find Next"), "g")
    static let findPrevious = ShortcutCommand("findPrevious", in: .edit, String(localized: "Find Previous"), "g", [.command, .shift])
    static let useSelectionForFind = ShortcutCommand("useSelectionForFind", in: .edit, String(localized: "Use Selection for Find"), "e")

    static let toggleSource = ShortcutCommand("toggleSource", in: .view, String(localized: "Show Markdown Source or Formatted Text"))
    static let toggleReader = ShortcutCommand("toggleReader", in: .view, String(localized: "Show Reader or Original"))
    static let toggleFormats = ShortcutCommand("toggleFormats", in: .view, String(localized: "Show or Hide Formats"))
    static let focus = ShortcutCommand("focus", in: .view, String(localized: "Focus"), "f", [.command, .shift])
    static let viewAsList = ShortcutCommand("viewAsList", in: .view, String(localized: "View as List"), "1")
    static let viewAsGallery = ShortcutCommand("viewAsGallery", in: .view, String(localized: "View as Gallery"), "2")
    static let viewAsTable = ShortcutCommand("viewAsTable", in: .view, String(localized: "View as Table"), "3")
    static let viewAsBoard = ShortcutCommand("viewAsBoard", in: .view, String(localized: "View as Board"), "4")
    static let viewAsTimeline = ShortcutCommand("viewAsTimeline", in: .view, String(localized: "View as Timeline"), "5")
    static let viewAsCalendar = ShortcutCommand("viewAsCalendar", in: .view, String(localized: "View as Calendar"), "6")
    static let toggleFilters = ShortcutCommand("toggleFilters", in: .view, String(localized: "Show or Hide Filters"))
    static let addFilter = ShortcutCommand("addFilter", in: .view, String(localized: "Add Filter…"))
    static let clearFilters = ShortcutCommand("clearFilters", in: .view, String(localized: "Clear Filters"))
    static let today = ShortcutCommand("today", in: .view, String(localized: "Today"), "t")
    static let previousPeriod = ShortcutCommand("previousPeriod", in: .view, String(localized: "Previous Week or Month"), arrows["left"], [.command, .option])
    static let nextPeriod = ShortcutCommand("nextPeriod", in: .view, String(localized: "Next Week or Month"), arrows["right"], [.command, .option])
    static let showWeek = ShortcutCommand("showWeek", in: .view, String(localized: "Show a Week"), "1", [.command, .option])
    static let showMonthScale = ShortcutCommand("showMonthScale", in: .view, String(localized: "Show a Month"), "2", [.command, .option])
    static let toggleMonth = ShortcutCommand("toggleMonth", in: .view, String(localized: "Show or Hide Month"), "d", [.command, .shift])
    static let newView = ShortcutCommand("newView", in: .view, String(localized: "New View"))
    static let editView = ShortcutCommand("editView", in: .view, String(localized: "Edit View"))
    static let saveAsView = ShortcutCommand("saveAsView", in: .view, String(localized: "Save as View…"))
    static let resetView = ShortcutCommand("resetView", in: .view, String(localized: "Reset View"))
    static let duplicateView = ShortcutCommand("duplicateView", in: .view, String(localized: "Duplicate View"))
    static let toggleDetails = ShortcutCommand("toggleDetails", in: .view, String(localized: "Show or Hide Details"), "i", [.command, .option])
    static let customizeSidebar = ShortcutCommand("customizeSidebar", in: .view, String(localized: "Customize Sidebar…"))
    static let back = ShortcutCommand("back", in: .view, String(localized: "Back"), "[")
    static let forward = ShortcutCommand("forward", in: .view, String(localized: "Forward"), "]")
    static let previousItem = ShortcutCommand("previousItem", in: .view, String(localized: "Previous Item"), arrows["up"], [.command, .option])
    static let nextItem = ShortcutCommand("nextItem", in: .view, String(localized: "Next Item"), arrows["down"], [.command, .option])
    static let makeTextBigger = ShortcutCommand("makeTextBigger", in: .view, String(localized: "Make Text Bigger"), "+")
    static let makeTextSmaller = ShortcutCommand("makeTextSmaller", in: .view, String(localized: "Make Text Smaller"), "-")
    static let actualSize = ShortcutCommand("actualSize", in: .view, String(localized: "Actual Size"), "0")
    static let zoomToFit = ShortcutCommand("zoomToFit", in: .view, String(localized: "Zoom to Fit"))
    static let nextPage = ShortcutCommand("nextPage", in: .view, String(localized: "Next Page"))
    static let previousPage = ShortcutCommand("previousPage", in: .view, String(localized: "Previous Page"))

    /// A Format command, with the shortcut Notes gives it where Notes has one.
    static func format(_ format: Format) -> ShortcutCommand {
        let id = "format." + String(describing: format)
        // The menu's Table submenu opens with Insert Table, and the page names the command the same way.
        let title = format == .table ? String(localized: "Insert Table") : String(localized: format.title)
        guard let shortcut = format.shortcut else { return ShortcutCommand(id, in: .format, title) }
        return ShortcutCommand(id, in: .format, title, String(shortcut.key), ShortcutModifiers(shortcut.modifiers))
    }

    /// Every command, in the order of the menus.
    static var all: [ShortcutCommand] {
        let commands: [ShortcutCommand] = [
            settings, newItem, newWindow, refresh, open, openAsModal, openAsFullPage, openInNewWindow, quickLook, openOriginal, openInBrowser,
            favorite, addTag, changeType, customizeLayout, versionHistory, keepInLibrary, moveToFeed, archive, delete, exportPDF, print,
            copyLink, addAttachment, searchItems, commandPalette, paletteActions, searchList, find, findNext, findPrevious, useSelectionForFind,
            toggleSource, toggleReader, toggleFormats, focus, viewAsList, viewAsGallery, viewAsTable, viewAsBoard, viewAsTimeline, viewAsCalendar,
            toggleFilters, addFilter, clearFilters, today, previousPeriod, nextPeriod, showWeek, showMonthScale, toggleMonth,
            newView, editView, saveAsView, resetView, duplicateView, toggleDetails, customizeSidebar, back, forward, previousItem, nextItem,
            makeTextBigger, makeTextSmaller, actualSize, zoomToFit, nextPage, previousPage,
        ]
        return commands + Format.allCases.map { format($0) }
    }
}

nonisolated extension ShortcutModifiers {
    init(_ modifiers: EventModifiers) {
        var result: ShortcutModifiers = []
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.command) { result.insert(.command) }
        self = result
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if contains(.control) { result.insert(.control) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.command) { result.insert(.command) }
        return result
    }
}

nonisolated extension Shortcut {
    /// What a menu item binds, or nil for a shortcut with no key.
    var keyboardShortcut: KeyboardShortcut? {
        guard key.count == 1, let character = key.first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers.eventModifiers)
    }
}

extension View {
    /// Binds the key the person chose for `command`, in the menu bar: with no `bindings` (the toolbar's copy of a command, a
    /// row's menu), none, so a key is never registered twice.
    func shortcut(_ command: ShortcutCommand, _ bindings: ShortcutBindings?) -> some View {
        keyboardShortcut(bindings?.shortcut(for: command)?.keyboardShortcut)
    }
}
