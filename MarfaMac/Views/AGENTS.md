# Views

Windows, panes, toolbars and commands. Settings is a window of its own, in `MarfaMac/Settings/`. `docs/window.md` has the window's design; the root table names the page for everything else.

## Commands and the palette

- **Every toolbar action and corner control is also a menu command,** because a person can hide either. The palette builds its own list (`CommandPalette+Commands.swift`), so add a command there too.
- **A command binds its key with `shortcut(_:_:)` from `ShortcutBindings`,** never `.keyboardShortcut` with a literal key, so the person's own choice in Settings drives the menu.
- **Offer an editor command in the palette only when `hasVisibleEditor`,** because the editor stays mounted, hidden, behind a gallery or a table.

## Toolbars

- **Every toolbar is a plain `toolbar`,** with no identifier, because a person cannot customize the window's buttons. The top row (`TopRowFrame`) draws the title and the views in the content, and the toolbar holds only the buttons.
- **Trap:** a hidden `ToolbarSpacer` leaves its gap. Declare each fixed spacer only while the groups on both sides show.
- **Never put a width in the top row.** It measures the toolbar's items (`ToolbarRoomProbe`) and folds by what is left.
- **The sidebar's button stands over the sidebar** (`SidebarToolbar`, whose comment says what keeps it there), and Back and Forward stand beside it, or lead the first column's toolbar while the sidebar is closed. Keep the column's width limits outside its toolbar.

## One split view at a time

- **`MainView` mounts one `NavigationSplitView` and changes the workspace's identity to switch.** Never change the column count of one that is mounted: give the workspace another identity. Layouts that share a column count share the split view, so a change between them keeps the panel's width and costs no new split view; give them no identity of their own.
- **Keep above it the state a person would notice:** browser, editor, undo, columns, the sidebar's scroll.

## Large lists

- **A list must not run every row's body for a change of selection or of one item.** The doc comments of `ItemList`, `SelectableList`, `GalleryCard`, `SoftSelection` and `Browser`'s cached content say how. Read them first, and measure with the `Measure` plan.
- **`ItemRow` takes only plain values worked out once for each item** (`RowContent`, a `Density`, an excerpt). It reads no library, catalogue or look.
- **A row's picture is a view of its own** (`RowPictureView`) that only a row with a picture holds.
- **A layout reads a place's items from the browser** (`Browser.readyArrangement`, `readyTable`, `placed`), worked out off the main actor for a large place, shows `PlaceProgress` until the first answer, and makes no pass over them in its body.
- **Hand a `List` a page of rows, never a whole place** (`Browser.listDrawn`): SwiftUI goes through every row it is given at each change, which at 50,000 rows takes seconds. Select All still takes every item (`selectsAll`), and `ChosenItemDrawn` draws a page around the chosen one, not every row up to it.

## Code Review Rules

- **Toolbar that can be customized.** Flag a `toolbar(id:)`, a `ToolbarItem(id:)` or a width written into the top row, or a change to a mounted split view's column count.
- **Toolbar action without a command.** Flag a toolbar action with no menu command or no palette entry.
- **Row body runs for all.** Flag a change that makes every row's body run on a selection change or a one-item edit. Safe path: the doc comments above, and a measurement.
- **Design already rejected.** Flag a drawing that repeats a line of `docs/rejected.md`.
