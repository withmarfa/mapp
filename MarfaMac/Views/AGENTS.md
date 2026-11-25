# Views

Windows, panes, toolbars and commands. Settings is a window of its own, in `MarfaMac/Settings/`. `docs/window.md` has the window's design; the root table names the page for everything else.

## Commands and the palette

- **Every toolbar action and corner control is also a menu command,** because a person can hide either. The palette builds its own list (`CommandPalette+Commands.swift`), so add a command there too.
- **A command binds its key with `shortcut(_:_:)` from `ShortcutBindings`,** never `.keyboardShortcut` with a literal key, so the person's own choice in Settings drives the menu.
- **Offer an editor command in the palette only when `hasVisibleEditor`,** because the editor stays mounted, hidden, behind a gallery or a table.

## Toolbars

- **Every toolbar in a customizable window is `toolbar(id:)`,** and each split view has an identifier of its own, which all its columns use.
- **Trap:** replacing a toolbar under its open tray crashes, so `MainView` holds the split view while the tray is open.
- **Trap:** a hidden `ToolbarSpacer` leaves its gap. Declare each fixed spacer only while the groups on both sides show, with `customizationBehavior(.disabled)`.
- **Every state of a split view declares the same items and hides what does not apply,** because an item left out is dropped from the saved layout.
- **An item that comes and goes has `customizationBehavior(.disabled)`** and never returns to a toolbar the person has customized, so it holds only what they can do without.
- **The sidebar's button, Back and Forward stand over the sidebar** (`SidebarToolbar`, whose comment says what keeps them there). Keep the column's width limits outside its toolbar.

## One split view at a time

- **`MainView` mounts one `NavigationSplitView` and changes the workspace's identity to switch.** Never change the column count of one that is mounted: give the workspace another identity.
- **Keep above it the state a person would notice:** browser, editor, undo, columns, the sidebar's scroll.

## Large lists

- **A list must not run every row's body for a change of selection or of one item.** The doc comments of `ItemList`, `SelectableList`, `GalleryCard`, `SoftSelection` and `Browser`'s cached content say how. Read them first, and measure with the `Measure` plan.
- **`ItemRow` takes only plain values worked out once for each item** (`RowContent`, a `Density`, an excerpt). It reads no library, catalogue or look.
- **A row's picture is a view of its own** (`RowPictureView`) that only a row with a picture holds.

## Code Review Rules

- **Toolbar without an identifier.** Flag a plain `toolbar` in a customizable window, an item that comes and goes without `customizationBehavior(.disabled)`, or a change to a mounted split view's column count.
- **Toolbar action without a command.** Flag a toolbar action with no menu command or no palette entry.
- **Row body runs for all.** Flag a change that makes every row's body run on a selection change or a one-item edit. Safe path: the doc comments above, and a measurement.
- **Design already rejected.** Flag a drawing that repeats a line of `docs/rejected.md`.
