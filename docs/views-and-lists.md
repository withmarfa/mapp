# Views and lists

Status: Built in v0.0.43. How a row, card or cell is drawn is agreed to change; see [Looks](looks.md).

Where it lives: `Browser`, `ItemViewMode`, `ViewLayouts` and `SidebarLayout` under `MAPP/Model/`; `NoteList`, `ItemGallery`, `ItemBoard`, `ItemTable`, `ItemTimeline`, `ViewEditPanel`, `FilterRow`, `FilterChips`, `ItemViewOptions` and `CommandPalette` under `MAPP/Views/`.

A view shows a set of items in a layout. This page explains the layouts, what a saved view is, and the controls that change what a list shows.

## Layouts

An item list takes one of five layouts (`ItemViewMode`): list, gallery, table, board and timeline.

- The list takes the rows described in [Looks](looks.md).
- The gallery's card always shows its title.
- The board shows its columns, which are the groups of its grouping field. A person can hide the groups that have no items.
- The table has one left edge, and its columns are the type's properties, shown, ordered and sized as the person arranged them.

## Saved views

A saved view splits between Marfa and the Mac.

- **Marfa holds** the view's title, query, sort and group.
- **The Mac holds** the layout, the table's columns, whether the board hides empty groups, the gallery's cards, the list's rows and the table's widths (`ViewMacSettings`). See [Settings storage](settings-storage.md).

Deleting a view from MAPP removes both. A view that disappears from a list is not removed from the Mac, since a failed read can publish an empty list.

A type's list, and the other places that are not views, can become one with Save as View.

## Edit View

Edit View opens in the right sidebar. It holds the view's Name, Layout, Rows (a list only), Sort, Group, and Columns or Cards.

- A change applies as it is made, in the window beside the panel, and is written to a saved view at once.
- One Done closes the panel.
- Filters are not in the panel.

## How an edit is saved

Every change in Edit View shows in the window at once. `Browser.choicesChanged()` compares the window's choices with the last it saw and writes each part where it belongs.

- **Marfa's part** (name, query, sort and group) is written at once through the library, one write at a time for each view. A write is based on the version the window read, so a change made elsewhere is refused, never overwritten. A refused write keeps the window's choice and tells the person.
- **The Mac's part** is stored as it is made, with its own undo step, and never written to Marfa.
- **Column widths** are the one part kept at once (`Browser.keepWidths`), and only from a drag of a divider. The app owns the column order and visibility, because `TableColumnCustomization` cannot separate them from widths.
- **A layout the Mac holds none of** stays empty and follows the window. The app's own change of layout goes through `Browser.set(layout:)`, so it is never taken for the person's.

## Filters

Filters live in one row above the list (`FilterRow` and `FilterChips`) as squared 26-point chips. There is no filter button in the list's toolbar. View Options opens with Show Filters or Hide Filters, and the View menu has Show or Hide Filters, Add Filter and Clear Filters.

View Options also holds Include Subtypes, which lets a type's list show the items of its subtypes. The choice is stored for each type as `includedSubtypes`.

## Sidebar

The sidebar has three groups of places: Library (Items, Sources and Collections), Views (Inbox, Recents, Favorites and the saved views) and Types. A person hides or moves a place in Settings > Sidebar, and the arrangement is kept for each server (`sidebarLayouts`).

## Command palette

The palette is one 680-point panel (`CommandPalette`). Open and Actions float in a small glass capsule at the bottom right of the results. A round glass button at the bottom left shows the palette's filter row. There is no preview pane beside the results; a row carries its own excerpt.

Every toolbar action is also a command in the menu bar, and the palette builds its own list, so a new command needs adding there too.

## Controls

Segmented controls are the system's own Liquid Glass capsule. MAPP does not draw a flat, squared or hand-drawn one. See [Rejected designs](rejected-designs.md).

## Large libraries

A list must not run every row's body when the selection changes or one item changes. `NoteList`, `SelectableList`, `GalleryCard`, `SoftSelection` and `Browser`'s cached content keep this, and their doc comments say how. Measure a change to a list with the `Measure` plan.

## Built today

A row takes one of six styles, and the gallery, board and table each draw values their own way. The settings are in Settings > Lists (the Row Style tiles) and in Edit View's Rows. When the look is built, the six styles become two densities. See [Presets and densities](presets-and-densities.md).

## Related pages

- [Looks](looks.md)
- [Settings storage](settings-storage.md)
- [Item page](item-page.md)
