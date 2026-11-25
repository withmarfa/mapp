import SwiftUI

extension CommandPalette {
    var commands: [Entry] {
        // Writing and Version History act on notes; a file selected takes neither.
        let everything = browser.selectedHeaderItems(in: library)
        let selected = everything.filter { !$0.isFile }
        let one = browser.selection.count == 1 && selected.count == 1 ? selected.first : nil
        let hasVisibleEditor = browser.showsPage && one?.id == editor.pageItemID && editor.hasItem
        var entries: [Entry] = []
        func add(_ title: String, _ systemImage: String, _ shortcut: String? = nil, in group: PaletteSections.CommandGroup, id: String? = nil, action: @escaping () -> Void) {
            entries.append(Entry(id: id ?? "command:" + title, title: title, icon: .symbol(systemImage), shortcut: shortcut, group: group, action: action))
        }

        // The page keeps ⌘[ and ⌘] while it has the keyboard (see AppCommands), so the palette does not suggest them.
        func historyKey(_ key: String) -> String? { returnFocus == .page ? nil : key }

        if library.isLoaded {
            add(String(localized: "Search List"), "magnifyingglass", keys(.searchList), in: .edit) { browser.focusRequest = .search }
            let modes = browser.showsPlaceIndex ? [] : browser.availableViewModes(in: library)
            func addLayout(_ mode: ItemViewMode, _ title: String, _ systemImage: String, _ command: ShortcutCommand) {
                if modes.contains(mode) { add(title, systemImage, keys(command), in: .view) { browser.chooseLayout(mode) } }
            }
            addLayout(.list, String(localized: "View as List"), "list.bullet", .viewAsList)
            addLayout(.gallery, String(localized: "View as Gallery"), "square.grid.2x2", .viewAsGallery)
            addLayout(.table, String(localized: "View as Table"), "tablecells", .viewAsTable)
            addLayout(.board, String(localized: "View as Board"), "rectangle.split.3x1", .viewAsBoard)
            addLayout(.timeline, String(localized: "View as Timeline"), ItemViewMode.timeline.symbol, .viewAsTimeline)
            addLayout(.calendar, String(localized: "View as Calendar"), ItemViewMode.calendar.symbol, .viewAsCalendar)
            addLayout(.map, String(localized: "View as Map"), ItemViewMode.map.symbol, .viewAsMap)
            if browser.kindsType(in: library) != nil {
                let isOn = browser.listing.includesKinds
                add(isOn ? String(localized: "Show This Type Only") : String(localized: "Include Kinds"), IncludeKinds.symbol, in: .view) {
                    browser.setIncludesKinds(!isOn)
                }
            }
            if browser.isCollectionItemPresented {
                add(String(localized: browser.viewMode.backTitle), "chevron.backward", historyKey("⌘["), in: .go) { browser.returnToCollection() }
            } else {
                if browser.canStepBack(in: library) {
                    add(String(localized: "Back"), "chevron.backward", historyKey("⌘["), in: .go) { browser.stepBack(in: library) }
                }
                if browser.canStepForward(in: library) {
                    add(String(localized: "Forward"), "chevron.forward", historyKey("⌘]"), in: .go) { browser.stepForward(in: library) }
                }
            }
            if browser.isModalPresented {
                let neighbors = browser.modalNeighbors(in: library, order: order)
                if neighbors.previous != nil {
                    add(String(localized: "Previous Item"), "chevron.up", "⌥⌘↑", in: .go) { browser.moveModal(.previous, in: library, order: order) }
                }
                if neighbors.next != nil {
                    add(String(localized: "Next Item"), "chevron.down", "⌥⌘↓", in: .go) { browser.moveModal(.next, in: library, order: order) }
                }
                add(String(localized: "Close Modal"), "xmark", in: .go) { browser.closeModal() }
            }
            if let libraries {
                add(String(localized: "Export Layouts…"), "square.and.arrow.up", in: .looks) { LooksFiles.export(from: libraries) }
                add(String(localized: "Import Layouts…"), "square.and.arrow.down", in: .looks) { LooksFiles.importLooks(into: libraries) }
            }
            // An image's or a PDF's page holds ⌘+, ⌘− and ⌘0 for the file, so the text sizes are not offered then
            // (`FileViewCommand`).
            if let fileView = browser.showsPage ? details?.fileViewing(of: browser.selection.count == 1 ? browser.selection.first : nil) : nil {
                for command in FileViewCommand.offered(for: fileView.kind) where command.isEnabled(on: fileView) {
                    add(String(localized: command.title), command.systemImage, keys(command.shortcutCommand), in: .view) { command.perform(on: fileView) }
                }
            } else {
                // The palette holds the keyboard itself, so the page counts as focused where it was when the palette opened.
                let zoom = TextZoom.acting(pageFocused: returnFocus == .page)
                let size = UserDefaults.standard.object(forKey: zoom.key) as? Int ?? zoom.defaultSize
                if zoom.size(after: .bigger, from: size) != nil {
                    add(String(localized: "Make Text Bigger"), "textformat.size.larger", keys(.makeTextBigger), in: .textSize) { zoom.apply(.bigger) }
                }
                if zoom.size(after: .smaller, from: size) != nil {
                    add(String(localized: "Make Text Smaller"), "textformat.size.smaller", keys(.makeTextSmaller), in: .textSize) { zoom.apply(.smaller) }
                }
                add(String(localized: "Actual Size"), "textformat.size", keys(.actualSize), in: .textSize) { zoom.apply(.actual) }
            }
            entries.append(Entry(id: "command:newItem", title: String(localized: "New Item"), icon: .symbol("plus"), shortcut: keys(.newItem),
                                 takesFocus: true) {
                browser.openNewItem(in: library)
            })
            for type in QuickAdd.types(in: library) {
                entries.append(Entry(id: "command:new:" + type.id.rawValue, title: String(localized: "New \(type.label)"),
                                     icon: .type(library.catalogue.icon(for: type.id)), takesFocus: true, group: nil) {
                    browser.openNewItem(kind: type.id.rawValue, in: library)
                })
            }
            // After New Item and the typed ones, so the commands "new" finds lead with New Item.
            add(String(localized: "New Window"), "macwindow.badge.plus", keys(.newWindow), in: .file) { openWindow(id: MarfaMacApp.mainWindowID) }
            if let host, host.canRefresh {
                add(String(localized: "Refresh"), "arrow.clockwise", keys(.refresh), in: .file) { host.refresh() }
            }
            if browser.selection.count == 1, let details {
                add(details.isPresented ? String(localized: "Hide Details") : String(localized: "Show Details"), "sidebar.right", keys(.toggleDetails), in: .view) { details.isPresented.toggle() }
            }
        }
        let search = String(localized: "Search Items")
        entries.append(Entry(id: "command:" + search, title: search, icon: .symbol("magnifyingglass"), shortcut: keys(.searchItems), takesFocus: true, group: .edit) {
            browser.palette = .search
        })

        #if DEBUG
        // Dev-only and not a toolbar action, so it is not localized and has no toolbar button or shortcut.
        add("Show Tuning Panel", "slider.horizontal.3", in: .debug) { openWindow(id: TuningPanel.windowID) }
        #endif

        if let one, one.allows(.text) {
            if hasVisibleEditor {
                for format in [Format.title, .heading, .subheading, .heading4, .heading5, .heading6, .body, .bold, .italic,
                               .strikethrough, .highlight, .code, .link, .codeBlock, .quote, .bulletList, .orderedList, .checklist, .table]
                where format != .table || !editor.caret.inTable {
                    add(ShortcutCommand.format(format).title, "textformat", keys(.format(format)), in: .format) { editor.apply(format) }
                }
            }
        }
        // The same commands, titles and rules as the menu bar and the More menu (`ItemCommand`).
        let itemContext = ItemCommandContext(library: library, ids: browser.selection, browser: browser, editor: editor, details: details)
        for command in ItemCommand.allCases where command.isEnabled(in: itemContext) {
            let sourceMode = command == .toggleSource ? editor.caret.sourceMode : nil
            add(String(localized: command.title(in: itemContext, sourceMode: sourceMode)), command.systemImage, keys(command.shortcutCommand), in: command.paletteGroup) {
                command.perform(in: itemContext, editor: editor) { openWindow(value: $0) }
            }
        }
        let shareID = one?.id
        let shareFile = shareID.flatMap { browser.fileURL(of: $0) }
        // Presence only. The text is read when Share is chosen, so opening the palette does not follow a keystroke.
        let canShare = shareFile != nil || (shareID.map { library.bodyText($0) != nil } ?? false)
        if canShare {
            add(String(localized: "Share…"), "square.and.arrow.up", in: .file) {
                let item = shareID.flatMap { library.item($0) }
                ItemShare(item: item, fileURL: shareFile ?? shareID.flatMap { browser.fileURL(of: $0) }, in: library)
                    .present(near: hasVisibleEditor ? editor.webView : nil)
            }
        }

        if let details, details.history != nil {
            add(String(localized: "Exit Version History"), "xmark", in: .file) { details.leaveHistory() }
            if details.history?.canRestore(in: library) == true {
                add(String(localized: "Restore Version"), "arrow.uturn.backward", in: .file) {
                    details.restoreFromHistory(in: library, undoManager: undoManager)
                }
            }
        } else if let details, selected.count == 1, let only = selected.first {
            add(String(localized: "Version History…"), "clock.arrow.circlepath", in: .file) {
                details.showHistory(of: only.id, in: library)
            }
        }
        // These act on the whole selection, files too; what an item can't take is left alone and the person is told.
        let ids = Set(everything.map(\.id))
        let active = everything.filter { $0.state == .active }
        if !everything.isEmpty, everything.allSatisfy({ $0.state == .trashed }) {
            add(String(localized: "Recover"), "arrow.uturn.backward", in: .file) { library.recover(ids, undoManager: undoManager) }
        } else if !everything.isEmpty {
            let allFavorites = !active.isEmpty && active.allSatisfy(\.isFavorite)
            if !active.isEmpty {
                add(allFavorites ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"), allFavorites ? "star.slash" : "star", in: .file) {
                    library.setFavorite(ids, !allFavorites, undoManager: undoManager)
                }
            }
            if let details, library.canTag(ids) {
                add(String(localized: "Add Tag…"), "tag", in: .file) {
                    details.tagRequest = TagRequest(ids: ids, undoManager: undoManager)
                }
            }
            if let details, library.offersTypeChange(for: ids) {
                add(String(localized: "Change Type…"), "square.on.square", in: .file) {
                    details.typeChange = TypeChangeRequest(ids: ids, undoManager: undoManager)
                }
            }
            for move in ItemMove.inMenu(library.selectionCommands(ids)) {
                add(move.name, move.symbol, keys(move.shortcutCommand), in: .file) {
                    library.perform(move, on: ids, undoManager: undoManager, details: details)
                }
            }
            add(String(localized: "Delete"), "trash", in: .file) {
                library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
            }
        }
        let members = library.collectionMembers(browser.selection)
        if !members.isEmpty {
            if let details, !library.collections.isEmpty {
                add(String(localized: "Add to Collection…"), "rectangle.stack.badge.plus", in: .file) {
                    details.collectionPick = CollectionPickRequest(ids: browser.selection, undoManager: undoManager)
                }
            }
            for collection in library.collections(holding: members) {
                add(String(localized: "Remove from “\(collection.displayTitle)”"), "rectangle.stack.badge.minus", in: .file, id: "command:removeFrom:\(collection.id)") {
                    library.removeFromCollection(browser.selection, collection.id, undoManager: undoManager)
                }
            }
        }

        if library.isLoaded {
            for command in ViewOptionCommand.commands(for: browser, in: library) {
                add(command.title, command.systemImage, keys(command.key), in: command.group, action: command.action)
            }
            for type in browser.layoutTypes(in: library) {
                add(String(localized: "Edit Layout of \(type.plural)…"), "slider.horizontal.3", in: .view, id: "command:editLayout:\(type.id)") {
                    browser.showLayouts(of: type)
                }
            }
            for command in SavedViewCommand.commands(for: browser, in: library, order: order) {
                add(command.title, command.systemImage, in: .view, action: command.action)
            }
            if let sidebar = sidebarVisibility {
                add(sidebar.wrappedValue ? String(localized: "Hide Sidebar") : String(localized: "Show Sidebar"), "sidebar.left", keys(.toggleSidebar), in: .view) {
                    withAnimation { sidebar.wrappedValue.toggle() }
                }
            }
            if browser.customizesSidebar {
                add(String(localized: "Finish Customizing Sidebar"), "checkmark", in: .view) { browser.customizesSidebar = false }
            } else {
                add(String(localized: "Customize Sidebar…"), "sidebar.squares.leading", in: .view) { browser.customizesSidebar = true }
            }
        }
        if fullWidth {
            add(String(localized: "Standard Width"), "arrow.left.and.right", in: .view) { fullWidth = false }
        } else {
            add(String(localized: "Full Width"), "arrow.left.and.right", in: .view) { fullWidth = true }
        }
        let settingsTitle = String(localized: "Settings…")
        entries.append(Entry(id: "command:" + settingsTitle, title: settingsTitle, icon: .symbol("gearshape"), shortcut: keys(.settings), takesFocus: true, group: .settings) {
            browser.showSettings()
        })
        for page in SettingsPage.all {
            let title = String(localized: "Settings: \(page.title)")
            // Only typing finds a page, so ⌘K with nothing typed lists Settings… once.
            entries.append(Entry(id: "command:" + title, title: title, icon: .symbol(page.symbol), takesFocus: true, group: nil) {
                browser.showSettings(page)
            })
        }
        for item in HelpItem.allCases {
            add(String(localized: item.title), item.systemImage, in: .help) {
                item.perform(openSettings: { browser.showSettings($0) }, openURL: openURL)
            }
        }
        // Whatever else shares a title, such as two table columns of one label, is told apart by its place.
        let distinctIDs = PaletteSections.distinct(entries.map(\.id))
        for index in entries.indices { entries[index].id = distinctIDs[index] }
        return entries
    }

    var places: [Entry] {
        browser.paletteIndex(in: library).places.map { place in
            Entry(id: "place:\(place.item)", title: place.title ?? library.name(of: place.item), detail: String(localized: "Show"), icon: place.icon) {
                browser.show(place.item, in: library, order: order)
                browser.focusRequest = .list
            }
        }
    }
}
