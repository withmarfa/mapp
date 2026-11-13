# Views and lists

Status: Built in v0.0.43. The list row, the gallery card, the board card and the table reading a type's look are built, not yet released; see [Looks](looks.md).

Where it lives: `Browser`, `ItemViewMode`, `ViewLayouts` and `SidebarLayout` under `MAPP/Model/`, with `CardContents` and `ItemTableLayout` under `MAPP/Model/Items/`; `NoteList`, `ItemRow`, `ItemGallery`, `GalleryCard`, `ItemBoard`, `ItemTable`, `ItemTableCell`, `ChipLine`, `ItemTimeline`, `ViewEditPanel`, `FilterRow`, `FilterChipsBar`, `ItemViewOptions` and `CommandPalette` under `MAPP/Views/`.

A view shows a set of items in a layout. This page explains the layouts, what a saved view is, and the controls that change what a list shows.

## Layouts

An item list takes one of five layouts (`ItemViewMode`): list, gallery, table, board and timeline.

- The list takes the rows described in [Looks](looks.md).
- The gallery's card shows the item's picture, or its opening lines when it has none, then its title on up to two lines and the one line of context its type's look gives it. An item with neither a picture nor text shows its type's mark. A favorite's star sits on the picture and nothing else does. The panel chooses the preview, fit and size; the look chooses what the card says.
- The board shows its columns, which are the groups of its grouping field. A person can hide the groups that have no items. A card is the title, the look's context line and the bottom line (the type only where the board mixes types, the status, two facts and "+N"), without the field the board is grouped by: a board grouped by status leaves the status off every card, and one grouped by priority leaves the priority off. A compact board shows the title alone, with the type's mark where the board mixes types.
- The table has one left edge. After the name it shows the look's status and facts as columns drawn with the same chips as a row (a status, an option, a person's initials and name, the type as a chip, a plain value with no label), then the look's date. A status and a priority stay chips in a table, not the plainer marks a board card uses. Every other property sits behind View Options and starts hidden. A table of several types shows the union of their looks, the status first. A column no row has a value in starts hidden. Columns a saved view chose win over the look, and the person can show, order and size any of them.
- A list of several types draws each item from its own type's look in every layout.
- The timeline groups items by day. A calendar is a separate view that is not built.
- A gallery, table or board has no row of new-item chips above it.

Agreed, not built:

- A table keeps one left edge for the title, chips, headers, group names and rows, and a group's chevron hangs in the margin.
- The timeline starts from today's agenda and uses the window's width, and choosing a row, card or event opens the right sidebar.

## Saved views

A saved view splits between Marfa and the Mac. The rules for each side, and for deleting a view, are in [`MAPP/Model/AGENTS.md`](../MAPP/Model/AGENTS.md).

- **Marfa holds** the view's title, query, sort and group.
- **The Mac holds** the layout, the table's columns, whether the board hides empty groups, the gallery's cards, the list's density and the table's widths (`ViewMacSettings`). See [Settings storage](settings-storage.md).

A type's list, and the other places that are not views, can become one with Save as View in the toolbar.

## Edit View

Edit View opens in the right sidebar, and New View uses the same panel. It holds the view's Name, Layout (a Show As pop-up), Density (a list only), Sort, Group, and Columns or Cards.

- A change applies as it is made, in the window beside the panel. Undo takes changes back.
- One Done closes the panel.
- Filters are not in the panel.
- Density holds a pop-up of As in Settings, Standard and Compact.
- Sort holds a handle, the fixed property, a direction pop-up and an x in a circle, with a gray Add Sort.
- Group holds Group by and a Hide Empty Groups switch.
- Columns (a table) or Cards (a gallery) comes last. Cards has Preview and Size pop-ups and a Fit Picture switch; what a card says comes from its type's look, not from the view.

## How an edit is saved

The funnel that writes each part where it belongs, and what it does when a write is refused, are in [`MAPP/Model/AGENTS.md`](../MAPP/Model/AGENTS.md). Column widths differ from the rest: they are kept only from a drag of a divider (`Browser.keepWidths`), because `TableColumnCustomization` cannot separate the column order and visibility from the widths, so the app owns those two.

## Filters

Filters live in one row above the list (`FilterRow` and `FilterChipsBar`) as squared 26-point chips: the field in gray, is or is not, the values and an x, then a square plus of the same height. A chip opens its value panel, with no counts, and the plus opens Filter By under it. A saved view opens with its row hidden.

There is no filter button in the list's toolbar, which holds Search and View Options. View Options opens with Show Filters or Hide Filters, then Sort by, Group by and Edit View. When filters apply, its button is tinted and shows the count. The View menu has Show or Hide Filters, Add Filter and Clear Filters.

View Options also holds Include Subtypes, which lets a type's list show the items of its subtypes. The choice is stored for each type as `includedSubtypes`.

## Sidebar

The sidebar has three groups of places, under New and Search: Library (Items, Sources and Collections), Views (Inbox, Recents, Favorites and the saved views) and Types. A person hides or moves a place in Settings > Sidebar, and the arrangement is kept for each server (`sidebarLayouts`).

## Command palette

Command-K and Search Notes share one 680-point panel (`CommandPalette`).

- A row takes one line, or two in Search Notes. The results have sections, with the one that holds the best match first, and a gray selection. The count sits at the top right of the field.
- A round glass button at the bottom left shows the palette's filter row, which holds the view's chips for Type, Collection and Updated.
- Open and Actions float in a small glass capsule at the bottom right, with key caps, and an Actions panel opens above them.
- There is no preview pane beside the results. A row carries its own excerpt.

The palette builds its own list of commands. The rule that every toolbar action is also a command is in [`MAPP/Views/AGENTS.md`](../MAPP/Views/AGENTS.md).

## Controls

- Segmented controls are the system's own Liquid Glass capsule, as Apple Music draws it: a pale capsule with round ends and the chosen segment as a capsule inside. MAPP does not draw a flat, squared or hand-drawn one. See [Rejected designs](rejected-designs.md).
- A pop-up button has gray chevrons in a round well. A switch is the system's `Toggle`, as Settings draws it.
- Buttons and menu items use title case, and the words in the app follow the Writing section of Apple's Human Interface Guidelines. Symbols are SF Symbols at text sizes.
- Agreed, not built: a menu that chooses shows a tick only where a row can be ticked, and the View As menu has no icons, as Finder's has none.

## Large libraries

The rule for large lists is in [`MAPP/Views/AGENTS.md`](../MAPP/Views/AGENTS.md).

## Where things go

The window has three areas: the sidebar, the list pane and the page. What a person moves between goes in the list pane. A screen adds no new kind of column or toolbar, and only the pins sit under a page's title. A screen that needs something this does not allow changes the rule first.

## Settings

Settings is a place in the sidebar. See [Settings storage](settings-storage.md) for its pages. Its measurements, measured on the built app, which gets them from the system's grouped form:

- The pages list is the Settings column, 280 points by default (see [Settings storage](settings-storage.md)), and a page's column is 580 points.
- Rows are 37 points high, rows of buttons are 44 points, and boxes sit 56 points apart.
- Push buttons are gray with no edge.
- The density setting is in the Lists pane, after Appearance.

## The list's rows

A list row is one view for every type, in Standard or Compact. Settings > Lists holds the Density every list follows, Sort and Group; Edit View's Density picks one for a saved view, and a place that is not a saved view keeps its own on this Mac. A gallery card, a board card and a table cell draw the same look in their own layout. See [Presets and densities](presets-and-densities.md).

## Related pages

- [Looks](looks.md)
- [Settings storage](settings-storage.md)
- [Item page](item-page.md)
