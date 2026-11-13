# Views

Windows, panes, toolbars, commands and Settings. How things are drawn is in `docs/`: read the matching page before you change a list row, a chip, the item page, a panel or a view's controls, and note its status line, because a page marked "Agreed, not built" describes where the code is going, and its "Built today" or "Built, not yet released" says what the code does now.

- Chips and values: [value-components](../../docs/value-components.md).
- Rows, cards and densities: [looks](../../docs/looks.md) and [presets-and-densities](../../docs/presets-and-densities.md).
- The page, pins and Customize Layout: [item-page](../../docs/item-page.md).
- Layouts, Edit View, filters and palettes: [views-and-lists](../../docs/views-and-lists.md).
- Designs already turned down: [rejected-designs](../../docs/rejected-designs.md).

## Commands and the palette

- Every toolbar action is also a menu command, since a toolbar can be hidden.
- The command palette (`CommandPalette.swift`) builds its own list, so add a new command there too.
- With the gallery or table showing, the editor stays mounted but hidden. Offer an editor command in the palette only when `hasVisibleEditor`.

## Toolbars

- A person customizes the toolbar in the system's tray. Every toolbar in a customizable window is `toolbar(id:)`: one plain `toolbar` turns customization off for the whole window.
- Each split view the main window mounts has its own identifier (`WindowToolbarLayout`), because the system reshuffles a layout that one identifier carries between split views. All of that split view's columns use it.
- Replacing a toolbar under its open tray crashes, so `MainView` holds the split view while the tray is open.
- Within a split view, every state declares the same items and hides what does not apply: an item left out is dropped from the saved layout. Only an item with `customizationBehavior(.disabled)` may come and go.

## One split view at a time

`MainView` mounts one `NavigationSplitView` at a time and changes the workspace's identity to switch between them. Never change the column count of a split view that is already mounted. Keep state a person would notice (browser, editor, undo, columns, sidebar scroll) above it.

## Large lists

A view that lists items must not run every row's body for a change of selection or of one item. The types that keep this (`NoteList`, `SelectableList`, `GalleryCard`, `SoftSelection`, `Browser`'s cached content) say how in their doc comments. Read them before you change a list, and measure with the `Measure` plan.

## Code Review Rules

- **Toolbar without an identifier.** Flag a plain `toolbar` in a customizable window, a toolbar item that comes and goes without `customizationBehavior(.disabled)`, or a change to a mounted split view's column count.
- **Toolbar action without a command.** Flag a toolbar action that has no menu command or no palette entry.
- **Row body runs for all.** Flag a change that makes every row's body run on a selection change or a one-item edit. Safe path: follow the doc comments of `NoteList` and `SelectableList`, and measure.
- **Design already rejected.** Flag a drawing that repeats an entry in `docs/rejected-designs.md`.
