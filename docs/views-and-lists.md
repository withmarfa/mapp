# Views and lists

Status: Built in v0.0.43. The list row reading a type's look is built in v0.0.44; the gallery card, the board card and the table reading it are built in v0.0.45. The table's margin, whole-cell hover and add to an empty cell, the palettes' bar, rows and material setting, and the selection and hover greys and the favorite's heart as described below, are built, not yet released, as is Collections and Sources as a table with tabs. See [Looks](looks.md).

Where it lives: `Browser`, `ItemViewMode`, `ViewLayouts`, `SidebarLayout`, `IndexPlace`, `IndexTab`, `IndexSort`, `IndexPreferences` and `IndexChoice` under `MAPP/Model/`, with `IndexRow`, `IndexRows`, `CardContents`, `ItemTableLayout`, `ItemTimelineLayout`, `ItemPlacement`, `EventSpan` and `CalendarLayout` under `MAPP/Model/Items/`; `ItemList`, `ItemRow`, `ItemGallery`, `GalleryCard`, `ItemBoard`, `ItemTable`, `ItemTableCell`, `SoftSelection`, `ChipLine`, `ItemTimeline`, `ItemCalendar`, `SidebarIndex`, `IndexPage`, `IndexInspector`, `IndexViewOptions`, `CalendarToolbarItems`, `ViewEditPanel`, `FilterRow`, `FilterChipsBar`, `ItemViewOptions` and `CommandPalette` under `MAPP/Views/`.

A view shows a set of items in a layout. This page explains the layouts, what a saved view is, and the controls that change what a list shows.

## Layouts

An item list takes one of six layouts (`ItemViewMode`): list, gallery, table, board, timeline and calendar.

- The list takes the rows described in [Looks](looks.md).
- The gallery's card shows the item's picture, or its opening lines when it has none, then its title on up to two lines (two lines of room on every card) and the one line of context its type's look gives it. An item with neither a picture nor text shows its type's mark. A favorite's heart sits on the picture and nothing else does. The panel chooses the preview, fit, shape and size; the look chooses what the card says.
- The board shows its columns, which are the groups of its grouping field. Each lane's header is its status mark (a status field's words, and the four status groups, take the mark of their group), its title and its count, on a quiet rounded lane. The lanes share the window's width, each between 236 and 340 points (200 and 260 in a compact board), so a board of a few lanes stays at the left and one of many scrolls sideways to its last lane. A board of one type groups by that type's own words: a status field's words by their group (Not Started, In Progress, Completed, Canceled) and then as the type declares them, any other field's as declared. A board of a mixed list groups by Marfa's four status groups, which every type shares: Not Started, In Progress, Completed and Canceled, then No Status, which holds the items with no status and the types that have none. A person can hide the groups that have no items. A card is the title, the look's Secondary line and the bottom line (the type only where the board mixes types, the status, two facts and "+N"), without the field the board is grouped by: a board grouped by status leaves the status off every card, and one grouped by priority leaves the priority off. A compact board shows the title alone, with the type's mark where the board mixes types.
- The table's column headings have no dividers between them. A column still resizes by dragging its edge, where the resize cursor shows, and reorders by dragging its heading; the heading keeps its bottom line and the sort mark.
- The table's rows are 36 points high and it has one left edge, shared by the title, chips, headers, group names and rows. A group's chevron hangs in the margin before it, inside the pane with room at its left.
- A table cell whose value is picked from a menu (a status, a priority or a choice), and an empty cell that takes a value, fills with a tint across the whole cell under the pointer, and the chip in it does not move. An empty cell of a date, words, text, number or people value reads "Empty" under the pointer and opens that value's panel on a click, as the item page's row does, where the item's type declares the property and the item can be edited. An empty status, priority or choice changes in place.
- After the name the table shows the look's status and facts as columns drawn with the same chips as a row (a status, an option, a person's initials and name, the type as a chip, a plain value with no label), then the look's date. A status and a priority stay chips in a table, not the plainer marks a board card uses. Every other property sits behind View Options and starts hidden. A table of several types shows the union of their looks, the status first. A column no row has a value in starts hidden. Columns a saved view chose win over the look, and the person can show, order and size any of them.
- A list of several types draws each item from its own type's look in every layout.
- The timeline groups items by day, from today on, then an Earlier header, then the days before it, the latest first. Each item sits on the date its type's look names (`ItemPlacement`): an event by its start, a task by its due date, any other type by its look's date; only an item with no such date goes under No Date. A picker pointed at one field places every item by that field. An event's span (zone, all-day, end) is read in one place, `EventSpan`, for its page header and for placement. A row is the shared row (title, Secondary line, chips) beside a time column, with no second date; only an item placed by its start with no time says "All day", and a Secondary-line time is left out only where it is the field the timeline places by.
- The calendar (`ItemCalendar`, laid out by `CalendarLayout`) shows a week or a month, and is offered wherever the timeline is: where a type has a date field. Items sit as on the timeline (`ItemPlacement`, `EventSpan`). A week has a column for each day from the Mac's first weekday, an All Day row above, hour rows opening at the working day, a red line for now, and the weekend tinted. A timed event is a block over each day it covers, side by side with those it overlaps, and a timed event with no end lasts one hour. A month is a grid of whole weeks with the days of the next and previous months muted, each day listing its items by title up to what fits and then "+N"; a multi-day item is on each of its days. An item with no date is not shown. The title is the month and the subtitle the week number, or the count of items in the month. The toolbar has Today, back, forward and a Week or Month choice, each also a View menu command and a palette entry. The layout and the Week or Month choice are Mac settings and are never written to Marfa; a window shows the week or month around the day it was moved to, which is not kept. Choosing an event opens the right sidebar. The arrow keys move the chosen event: left and right to the nearest day beside it that has events, up and down through a day's events in time order (`CalendarNavigation`), crossing into the next or previous week or month at the edge; Return opens it, Escape clears it, and a week scrolls to it. Today, back and forward count from the library's clock (`ItemLibrary.now`). Dragging, drawing a new event and a day view are not built.
- A gallery, table or board has no row of new-item chips above it.

Agreed, not built:

- The timeline starts from today's agenda and uses the window's width, and choosing a row, card or event opens the right sidebar.

## Selection and hover

- A chosen row, card or table row is gray at 8% of the label color, and a row under the pointer is gray at 4.7%. Neither is ever blue. The list, the item table, the timeline, the index pages' tables, Settings' page list, Recently Deleted's list, Version History's list and the Add to Collection sheet's list take the 8%, and the sidebar's pending New View row does too; the list, both tables, the timeline and Recently Deleted's list take the 4.7% as well.
- `SoftSelection` draws both as layers beneath the table's row views, and the 4.7% follows the pointer from the table's own mouse events, so that mark runs no row's body. A row that is chosen, or that the table will not select, such as a heading, gets no hover mark.
- A table cell that changes or adds a value keeps its own tint across the whole cell, which shows over the row's.
- A chosen gallery card and a chosen board card keep a soft 3-point ring in that gray, touching the card, with no fill and no plate behind it.
- A chosen calendar event keeps its color, and the palettes keep their own selection.
- A table row under the pointer shows its open control as the arrow alone, in the secondary label color, with no tile.
- The favorites mark is a heart everywhere. The table draws it in pink and the gallery card in gray, and Add to Favorites and Remove from Favorites use `heart` and `heart.slash` in the menus and the palette. The sidebar's Favorites view takes the same pink when the sidebar's own colors are built.

## Saved views

A saved view splits between Marfa and the Mac. The rules for each side, and for deleting a view, are in [`MAPP/Model/AGENTS.md`](../MAPP/Model/AGENTS.md).

- **Marfa holds** the view's title, query, sort and group.
- **The Mac holds** the layout, the table's columns, whether the board hides empty groups, the gallery's cards, the calendar's Week or Month, the list's density and the table's widths (`ViewMacSettings`). See [Settings storage](settings-storage.md).

A type's list, and the other places that are not views, can become one with Save as View in the toolbar. The view keeps the filters, the sort and the grouping the window shows:

- A type's place saves what the window lists: with Include Subtypes on, the type alone as the view's types (Marfa lists it with its subtypes); with it off, the type's own items, as the type plus an exact-type condition where it has subtypes.
- A Type filter is saved as the view's types, so the view lists the types the window chose: they replace the types the place listed and a type's own exact-type condition. Marfa lists a type with its subtypes, so a chosen type that has any is also saved as an exact-type condition in the view's filter, which lists the same items as the window.
- An existing view's own Type filter is different: a chosen type within the types the view lists leaves them as they are, and is saved as an exact-type condition (`type eq`), so the view keeps its types and the filter stays a chip that can be removed or undone. A view of several types opens with those types as a Type filter only while its filter has no condition on the type. A chosen type outside the view's types replaces them.
- A list's sections by date (Today, Yesterday and the months) are not kept, and the Save as View sheet says so. A view groups by a field's value or a bucket of it, and Today, Yesterday and Previous 7 Days move with the day, so no grouping stands for them.

## Edit View

Edit View opens in the right sidebar, and New View uses the same panel. It holds the view's Name, Layout (a Show As pop-up), Density (a list only), Sort, Group, and Columns or Cards.

- A change applies as it is made, in the window beside the panel. Undo takes changes back.
- One Done closes the panel.
- Filters are not in the panel.
- Density holds a pop-up of As in Settings, Standard and Compact.
- Sort holds a handle, the fixed property, a direction pop-up and an x in a circle, with a gray Add Sort. Add Sort lists the fields of the types the view shows after its filters, and the columns every item has: the name and the type first, then the status and the other fields in the order the looks give them, then the parent and the dates.
- Group holds Group by and a Hide Empty Groups switch.
- Columns (a table) or Cards (a gallery) comes last. Cards has Preview, Size and Shape pop-ups and a Fit Picture switch; Shape is off when the preview is None, Fit Picture is off unless the preview can show a picture, and a gallery has no Density; what a card says comes from its type's look, not from the view.

## How an edit is saved

The funnel that writes each part where it belongs, and what it does when a write is refused, are in [`MAPP/Model/AGENTS.md`](../MAPP/Model/AGENTS.md). Column widths differ from the rest: they are kept only from a drag of a divider (`Browser.keepWidths`), because `TableColumnCustomization` cannot separate the column order and visibility from the widths, so the app owns those two.

## Filters

Filters live in one row above the list (`FilterRow` and `FilterChipsBar`) as squared 26-point chips: the field in gray, is or is not, the values and an x, then a square plus of the same height. A chip opens its value panel, with no counts, and the plus opens Filter By under it. A saved view opens with its row hidden.

There is no filter button in the list's toolbar, which holds Search and View Options. View Options opens with Show Filters or Hide Filters, then Sort by, Group by and Edit View. When filters apply, its button shows the count and is tinted while the window is active; in an inactive window it dims with the other toolbar buttons. The View menu has Show or Hide Filters, Add Filter and Clear Filters.

View Options also holds Include Subtypes, which lets a type's list show the items of its subtypes. The choice is stored for each type as `includedSubtypes`.

## Collections and Sources

Built, not yet released.

- Collections and Sources are one kind of page, an index of containers, drawn as a table (`IndexPage`). Collections has the columns Name, Source (the source that wrote it, left empty when none did), Items and Updated (when the collection itself last changed). Sources has Source, Writes (the types it writes), Items and Latest (its latest item's change). A column's header sorts the table, and the sort is kept for each page on this Mac (`indexSort.<place>`). Collections start by name and Sources by how many items they hold.
- Collections has the tabs All, Yours (the library tier) and From Apps (the feed tier). Sources has All, Apps (signed in) and Keys. A source is an app when its code starts with `oauth:` and a key otherwise (`SourceCode`). Each tab shows how many rows it holds, the tab chosen is kept for each page on this Mac (`indexTab.<place>`), and a tab with nothing in it says so.
- A collection's icon is gray. A type's icon in a table is in the type's color, with no tile, and a type with no icon has the neutral color and mark.
- The chosen container shows in the right sidebar (`IndexInspector`), with no buttons there: its latest items, the types in it, and its details: a collection's Created, Updated and Source (left out when no source wrote it), a source's Kind and Code. The table takes the window's width when the right sidebar is closed. The choice is held in `IndexChoice`, not in a view's state, so choosing a row runs no other row's body, and it clears when the container is deleted or goes on a sync.
- A double click, Return or Open in the row's menu opens the container. A collection's menu and the Delete key delete it, except a read-only collection, which offers no Delete; a source's menu renames it or chooses its mark.
- Deleting a collection asks with Apple's alert, then moves it to Recently Deleted and shows the toast with Undo ([Components](components.md)). Its items are kept: they hold their own place in the collection, so Undo brings it back with them.
- Search and View Options are in the toolbar, as on every screen. View Options sorts the table. New Collection is on the page, at the trailing edge of the tabs.

## Sidebar

The sidebar has three groups of places, under New and Search: Library (Items, Sources and Collections), Views (Inbox, Recents, Favorites and the saved views) and Types. A person hides or moves a place in Settings > Sidebar, and the arrangement is kept for each server (`sidebarLayouts`).

## Command palette

Command-K and Search Items share one 680-point panel (`CommandPalette`), which sits about an eighth of the way down the window, as quick add does.

- The field has room above and below it and no divider under it. Its magnifying glass sits in the rows' mark column, so the typed words start where the titles do.
- Every row in a list is one height: one line in the command palette, two in Search Items. Both palettes draw a row the same way: the type's small mark, the title in regular weight, and the detail or date at the right. A Search Items row adds a second line under its title, and keeps its mark and date on the title's line: the words around the match, or else the item's own text, or for an item with none, its type (or Inbox) and the collections it is in. The results have sections, with the one that holds the best match first, and a gray selection. With nothing typed, Search Items shows only its Recent section. The count sits at the top right of the field.
- A bar sits at the foot of the results, and rows scroll under it, fading and blurring out with the system's soft scroll edge effect; the last row of a short list sits above it. At its right, Open and Actions are one glass capsule with two segments, as the toolbar groups its buttons: pointing at a segment fills only that segment. Open reads Open for an item (Search Items still opens an item at the match) and Run for a command, with 14-point labels, a point larger than a large control's. Their key caps, and those in Actions, are `KeyCap` (see [Components](components.md)), one glyph to a cap: 16 points high with 4-point corners, a 10-point medium glyph in the label color at 42% opacity, a 1-point outline in the label color at 20%, and no fill. Menus keep the system's plain glyphs. In Search Items only, a round glass button at its left, as tall as the capsule and no wider, shows the palette's filter row, which holds the view's chips for Type, Collection and Updated, with a + as tall as a chip. With filters set, the button shows their number and a soft fill inside its glass, in the bar's neutral color, never the accent. The row takes its room from the list, so showing filters never makes the palette taller. The command palette has no filter button.
- Actions takes the bar's place: it grows up and to the left out of the bar, anchored at the bottom right where Actions stood, and shrinks back into the bar when it closes. It opens with a click on Actions or with Command-K, and its surface is the palette's own. There is no second panel above the bar.
- Nothing in either palette shows a tooltip.
- The two palettes are named for what they search. Search Items (Shift-Command-P, and Edit > Search Items…) searches every item, and its field reads Search Items. Command-K's field reads Search Commands and Items, and its last row reads Search Items for “typed words”. This is built and not yet released.
- With nothing typed, Command-K lists Recent, then its commands in sections that follow the menu bar: Settings (the app menu's), File, Looks (which the File menu holds), Edit, Format, View, Sort and Group, Text Size, Go, and Debug last in a Debug build. A command sits under the menu that holds it, in that menu's order, and a section with no commands is not shown. New Item is the only New row listed; New Task and the other typed ones are found by typing. Once something is typed the commands are one ranked Commands section. This is built and not yet released.
- When nothing matches, either palette stays about 400 points tall (never taller than a full list) and shows No Results in the middle. The bar's one button reads New Item with the Return key cap and has no Actions segment. Return or a click opens quick add, in the type last used, with the typed words as its title; with nothing typed it opens an empty draft, and a draft already holding content comes back as it was. Search Items keeps its filter button. This is built and not yet released.
- Settings > Appearance > Palettes sets what the palettes and New Item are drawn on: Glass (Liquid Glass, the default), Translucent (the system's popover material) or Solid (the window's own color). It is a Mac setting (`paletteMaterial`), never written to Marfa.
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
- [Components](components.md)
