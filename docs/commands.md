---
summary: How a command is added, and every command with its menu, its shortcut and whether it is on main.
paths:
  - MarfaMac/Model/Shortcuts/*.swift
  - MarfaMac/Views/ShortcutCatalogue.swift
  - MarfaMac/Views/*Commands.swift
  - MarfaMac/Views/ItemActions.swift
  - MarfaMac/Views/ItemMoveActions.swift
  - MarfaMac/Model/Browser+Moves.swift
  - MarfaMac/Views/ItemRowMenu.swift
---

# Commands and shortcuts

The menu bar and palette include every toolbar, corner and row command. See `docs/window.md` for their appearance.

## Adding a command

- **A command on the open page or the selection is an `ItemCommand` case.** It gives the title, symbol, `shortcutCommand`, `paletteGroup`, `isEnabled(in:)` and `perform(in:)` once. The palette lists every case; place it in `AppCommands` and in the toolbar's `MoreMenu`.
- **A command that changes items is a button in `ItemActions.swift`**, as Add to Favorites is. It takes the whole selection, files too, leaves alone what it cannot change and says so. Place it in `ItemOrganizeActions`, `ItemMoveActions` or `ItemRemoveActions`.
- **The row menu has one order,** `RowMenuEntry.entries`, for items in use and for the bin. Add a case there and draw it in `ItemRowMenu`; never add to one layout's menu, or menus differ. What only one layout has goes in `layoutActions`.
- **The palette repeats a button's rule in `CommandPalette+Commands.swift`.** Change both, because nothing joins them.
- **Add the command to `ShortcutCommand` and its `all`,** even with no default shortcut, so a person can give it one. A test refuses a shortcut that two commands or the system holds.
- **Never change a command's `id`,** because stored and exported shortcuts name it.
- **Only the menu bar binds a shortcut** (`shortcut(_:_:)` with its bindings). A row's or toolbar's button passes nil, so a key is never registered twice.
- **A Format command's shortcut is the page's too** (`Format.pageKey`), because the page takes keys before the menu.
- **Share and Copy Links take the chosen items as the window draws them, up to 100 at once** (`ItemLinkLimit`). Copy Links writes one link per line; Share hands the picker each link as its own address, so the destination decides how they read.
- **Put the test beside the rule:** `ItemOpeningTests` for the row menu's order, `ShortcutTests` for the catalogue.

## Tier and state

The `ItemLibrary` calls take the whole selection and return a `CommandOutcome` with the planned changes and planner skips. The engine can skip additional items when it queues the writes. Each call gives `moved` the outcome of what was queued once the writes have their first answers.

| Call | Moves | Leaves alone |
| --- | --- | --- |
| `setTier(_:to:undoManager:moved:)` | Each item to the Library or the Feed (`tierPlan`) | An item already there; a collection, view or settings item going to the Feed |
| `archive(_:beneath:undoManager:moved:)` | Each active item, and with `beneath` every active item under it (`archivePlan`) | An item archived or in Recently Deleted |
| `unarchive(_:undoManager:moved:)` | Each archived item (`unarchivePlan`) | An active item |

- **`ItemLibrary.perform(_:on:undoManager:details:)` is the one way a menu runs a move.** It asks first where it must, then calls `Browser.move`.
- **An item menu lists what `ItemMove.inMenu` gives of `selectionCommands`:** each tier move that would change an item, then Archive if any item can be archived, else Unarchive. They end the menu before Delete, with ⌃⌘K, ⌃⌘A and ⌘⌫ beside them. The menu bar and More keep all three, dimmed.
- **Only the row menu draws ⌘⌫.** A real one in the menu bar or More would take it from the editor, where it deletes a line.
- **Archive and Unarchive are one command, ⌃⌘A,** which toggles by state and archives a mixed selection.
- **A toast follows each move** (`Browser.move`), naming the item or giving the count, and shows only what the copy queued. Its Undo is the step the move registered.
- **Archive asks when items are under the selection:** Archive All, Archive Only This Item or Cancel (`ArchiveRequest`).
- **Move to Feed and Unarchive ask when the Feed would let the items go** (`FeedLimitRequest`, from the type's `feedDays` and each item's `created`). It counts only the items the move would leave in the Feed past their window.
- **A collection can be archived and is never moved to the Feed.** A table is not yet kept out of the Feed: the package now says which types hold one, and the app does not use that yet.
- **These queue offline,** so none waits on `reachesServer`.

## Shortcuts

- **Only a person's choices are stored** (`ShortcutBindings`), and a stored command this build does not know is kept.
- **A menu shortcut needs ⌘, ⌃ or ⌥.** A shortcut that a command already has asks to replace it, and one of the system's (`SystemShortcuts`) is refused.
- **Any-app shortcuts are off until set** and stay on their Mac (`AnyAppShortcuts`). They need ⌘ or ⌃, and work while the app runs. New Item opens the line over the app in front (`NewItemAnywhere`), which gives the keyboard back.
- **While the page has the keyboard, Back and Forward give up their keys,** because the page indents lists with them.
- **While an image or a PDF is open, the text-size keys size the file** (`FileViewCommand`).

## Every command

"Yes" is on `main`. "Agreed" is not, and has its row in `docs/agreed.md`. A command with no shortcut shows a dash.

| Menu | Command | Shortcut | On `main` |
| --- | --- | --- | --- |
| Marfa | Settings… | ⌘, | Yes |
| Marfa | Check for Updates… | – | Yes |
| File | New Item | ⌘N | Yes |
| File | New Window | ⌥⌘N | Yes |
| File | Refresh | ⌘R | Yes |
| File | Open in New Window | ⌘O | Yes |
| File | Keep in Library | ⌃⌘K | Yes |
| File | Archive, Unarchive | ⌃⌘A | Yes |
| File | Print… | ⌘P | Yes |
| File | Open, Open Beside the List, Open as Modal, Open as Full Page, Quick Look, Open in Default App, Share… (links for multiple items), Add to Favorites, Add Tag…, Change Type…, Add to Collection…, Version History…, Move to Feed, Delete, Recover, Rename Source…, Choose Source Mark…, Delete Collection…, Export Layouts…, Import Layouts…, Export as PDF… | – | Yes |
| Edit | Copy Link (Copy Links for several, one per line in list order) | ⇧⌘C | Yes |
| Edit | Add Attachment… | ⇧⌘A | Yes |
| Edit | Search Items… | ⇧⌘P | Yes |
| Edit | Command Palette | ⌘K | Yes |
| Edit | Palette Actions | ⌘J | Yes |
| Edit | Search List | ⌥⌘F | Yes |
| Edit | Find… | ⌘F | Yes |
| Edit | Find Next, Find Previous | ⌘G, ⇧⌘G | Yes |
| Edit | Use Selection for Find | ⌘E | Yes |
| View | Focus | ⇧⌘F | Yes |
| View | View as List, Gallery, Table | ⌘1, ⌘2, ⌘3 | Yes |
| View | View as Board, Timeline, Calendar, Digest, Map | ⌘4, ⌘5, ⌘6, ⌘7, ⌘8 | Yes |
| View | Today | ⌘T | Yes |
| View | Previous, Next Week or Month | ⌥⌘←, ⌥⌘→ | Yes |
| View | Show a Week, Show a Month | ⌥⌘1, ⌥⌘2 | Yes |
| View | Show or Hide Month | ⇧⌘D | Yes |
| View | Show or Hide Details | ⌥⌘I | Yes |
| View | Show or Hide Sidebar | ⌃⌘S | Yes |
| View | Back, Forward | ⌘[, ⌘] | Yes |
| View | Previous Item, Next Item | ⌥⌘↑, ⌥⌘↓ | Yes |
| View | Make Text Bigger, Smaller | ⌘+, ⌘- | Yes |
| View | Actual Size | ⌘0 | Yes |
| View | Show Markdown Source or Formatted Text, Show Reader or Original, Show or Hide Formats, Clear Filters, View…, New View…, Revert View, Reset View, Save View, Duplicate View, Delete View…, Collapse All Groups, Expand All Groups, Standard Width, Full Width, Customize Sidebar…, Close Modal, Zoom to Fit, Next Page, Previous Page | – | Yes |
| View | Zoom In, Zoom Out, Fit All Items (the Map) | – | Yes |
| View | Show All Items, Show Library, Show Feed | – | Agreed |
| Format | Heading 1, 2, 3 | ⇧⌘T, ⇧⌘H, ⇧⌘J | Yes |
| Format | Body | ⇧⌘B | Yes |
| Format | Bold, Italic, Strikethrough | ⌘B, ⌘I, ⇧⌘X | Yes |
| Format | Link… | ⇧⌘K | Yes |
| Format | Code Block, Block Quote | ⇧⌘M, ⌘' | Yes |
| Format | Bulleted List, Numbered List, Checklist | ⇧⌘7, ⇧⌘9, ⇧⌘L | Yes |
| Format | Insert Table | ⌃⌘T | Yes |
| Format | Heading 4, 5, 6, Highlight, Code, Table's rows, columns and alignment | – | Yes |
| Go | Each place, view and type | – | Yes |
| Help | Marfa Help, Keyboard Shortcuts, and links | – | Yes |
| Any app | Show Command Palette, Search Items, New Item | Off until set | Yes |
