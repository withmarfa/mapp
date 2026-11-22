# Views and lists

Status: Built in v0.0.43. The list row reading a type's look is built in v0.0.44; the gallery card, the board card and the table reading it are built in v0.0.45. The table's margin, whole-cell hover and add to an empty cell, the palettes' bar, rows and material setting, and the selection and hover greys and the favorite's star as described below, are built, not yet released, as are Items, Collections and Sources as index pages with tabs and a table, the sidebar customized in place, opening an item as a modal, a full page or a window with one row menu for every layout, making an item with quick add and the empty states, and the default view of every place that is not a saved view, with Save as View… and Reset View in View Options. See [Looks](looks.md). Grouping, Properties and filters for every layout are agreed, not built: see [Grouping, Properties and filters](#grouping-properties-and-filters).

Where it lives: `Browser`, `ItemViewMode`, `ItemOpening`, `QuickAdd`, `PlaceEmpty`, `ListNeighbors`, `RowMenuEntry`, `ViewLayouts`, `SidebarLayout`, `IndexPlace`, `IndexTab`, `IndexSort`, `IndexPreferences`, `IndexChoice`, `ItemIndexModel`, `SearchLeaveOuts` and `SearchLeftOutLine` under `MAPP/Model/`, with `IndexRow`, `IndexRows`, `ItemIndexRow`, `CardContents`, `ItemTableLayout`, `ItemTimelineLayout`, `ItemPlacement`, `EventSpan`, `CalendarLayout`, `CalendarCorner` and `SearchNarrowing` under `MAPP/Model/Items/`; `ItemList`, `ItemRow`, `ItemRowMenu`, `ItemModal`, `ItemGallery`, `GalleryCard`, `ItemBoard`, `ItemTable`, `ItemTableCell`, `SoftSelection`, `ChipLine`, `ItemTimeline`, `ItemCalendar`, `SidebarIndex`, `SidebarPlaceMenu`, `SidebarColorPicker`, `IndexPage`, `ItemsIndex`, `IndexInspector`, `IndexViewOptions`, `WindowCorner`, `ViewCorner`, `CalendarCornerView`, `CalendarMonthCard`, `ViewEditPanel`, `FilterRow`, `FilterChipsBar`, `ItemViewOptions` and `CommandPalette` under `MAPP/Views/`.

A view shows a set of items in a layout. This page explains the layouts, what a saved view is, and the controls that change what a list shows.

## Layouts

An item list takes one of six layouts (`ItemViewMode`): list, gallery, table, board, timeline and calendar.

- The list takes the rows described in [Looks](looks.md).
- The gallery's card shows the item's picture, or its opening lines when it has none, then its title on up to two lines (two lines of room on every card) and the one line of context its type's look gives it. An item with neither a picture nor text shows its type's mark. A favorite's star sits on the picture and nothing else does. The panel chooses the preview, fit, shape and size; the look chooses what the card says.
- The board shows its columns, which are the groups of its grouping field. Each lane's header is its status mark (a status field's words, and the four status groups, take the mark of their group), its title and its count, on a quiet rounded lane. The lanes share the window's width, each between 236 and 340 points (200 and 260 in a compact board), so a board of a few lanes stays at the left and one of many scrolls sideways to its last lane. A board of one type groups by that type's own words: a status field's words by their group (Not Started, In Progress, Completed, Canceled) and then as the type declares them, any other field's as declared. A board of a mixed list groups by Marfa's four status groups, which every type shares: Not Started, In Progress, Completed and Canceled, then No Status, which holds the items with no status and the types that have none. Only a saved view's Edit View can hide the groups that have no items. A card is the title, the look's Secondary line and the bottom line (the type only where the board mixes types, the status, two facts and "+N"), without the field the board is grouped by: a board grouped by status leaves the status off every card, and one grouped by priority leaves the priority off. A compact board shows the title alone, with the type's mark where the board mixes types.
- The table's column headings have no dividers between them. A column still resizes by dragging its edge, where the resize cursor shows, and reorders by dragging its heading; the heading keeps its bottom line and the sort mark, which follows the heading's text in every table, whichever side the column aligns it to, and a right-aligned heading keeps the room after it that its numbers do. The line under the headings runs as far as the rows' separators, which is past a last column that has reached its widest. Every heading, in every table including Settings', is in the New row's label font (callout, medium) in the secondary color.
- The table's column headings are drawn by one header view (`QuietHeaderView`) that keeps a heading cell for every column and refreshes it as it draws, so a column SwiftUI adds or replaces after the first layout still shows its heading. Once rows scroll up under the toolbar, a type's or a saved view's table draws the same `ToolbarBand` as every other scrolled view, reported from the table's own scroll (`quietTableHeader(isUnderToolbar:)`), with the headings staying pinned and opaque.
- A table fits the width of its page and follows it as the page changes, such as when the right sidebar opens or closes: its columns shrink toward their minimum widths and grow toward their maximum, and the table scrolls sideways only where even the minimums do not fit. A widths change the person makes by dragging an edge is left as it is until the page's width changes again.
- The table's rows are 36 points high and it has one left edge, shared by the title, chips, headers, group names and rows. A group's chevron hangs in the margin before it, inside the pane with room at its left.
- A table cell whose value is picked from a menu (a status, a priority or a choice), and an empty cell that takes a value, fills with a tint across the whole cell under the pointer, and the chip in it does not move. An empty cell of a date, words, text, number or people value reads "Empty" under the pointer and opens that value's panel on a click, as the item page's row does, where the item's type declares the property and the item can be edited. An empty status, priority or choice changes in place.
- After the name the table shows the look's status and facts as columns drawn with the same chips as a row (a status, an option, a person's initials and name, the type as a chip, a plain value with no label), then the look's date. A status and a priority stay chips in a table, not the plainer marks a board card uses. Every other property sits behind View Options and starts hidden. A table of several types shows the union of their looks, the status first. A column no row has a value in starts hidden. Columns a saved view chose win over the look, and the person can show, order and size any of them. Agreed, not built: the columns become the view's Properties list ([Properties](#properties)).
- A list of several types draws each item from its own type's look in every layout.
- The timeline groups items by day, from today on, then an Earlier header, then the days before it, the latest first. Each item sits on the date its type's look names (`ItemPlacement`): an event by its start, a task by its due date, any other type by its look's date; only an item with no such date goes under No Date. A picker pointed at one field places every item by that field. An event's span (zone, all-day, end) is read in one place, `EventSpan`, for its page header and for placement. A row is the shared row (title, Secondary line, chips) beside a time column, with no second date; only an item placed by its start with no time says "All day", and a Secondary-line time is left out only where it is the field the timeline places by. The timeline starts from today's agenda and uses the window's width, and choosing a row opens the right sidebar. Agreed, not built: the row is drawn as [The timeline's row](#the-timelines-row) says.
- The calendar (`ItemCalendar`, laid out by `CalendarLayout`) shows a week or a month, and is offered wherever the timeline is: where a type has a date field. Items sit as on the timeline (`ItemPlacement`, `EventSpan`). A week has a column for each day, seven in view, the hour rows opening at the working day, a red line for now, and the weekend tinted. It is one strip of days that scrolls both ways, as Calendar's does: a two-finger swipe along it moves the days continuously, past the edge of a week, and lets go on a day's edge, so the week shown can begin on any day, while a swipe down moves the hours. Only the columns in and beside view are built, so a calendar of thousands of items stays light. The title, the month, and the corner's Today, back and forward follow the days shown; back and forward move seven days, and Today and the first view start on the first weekday of the week that holds today. A pinch on the trackpad changes the height of an hour, from 24 to 160 points, keeping the hour under the pointer where it is; the height is a MAPP setting (`calendarHourHeight`), synced with the rest. The All Day row sits above the hours only while a shown day holds an all-day or multi-day item, so a calendar of timed items starts its hours at the top. A timed event is a block over each day it covers, side by side with those it overlaps, and a timed event with no end lasts one hour. A block shows its title on up to two lines and its time, drops the time first when the block is too short for both or too narrow, and uses a taller block's room for more lines of its title. A month is a grid of whole weeks with the days of the next and previous months muted, each day listing its items by title up to what fits and then "+N"; a multi-day item is on each of its days. An item with no date is not shown. The title is the month and the subtitle the week number, or the count of items in the month. Today, back, forward, Week or Month and the month are in the window's corner ([The bottom-right corner](#the-bottom-right-corner)), not the toolbar. The layout and the Week or Month choice are MAPP settings, kept with the view's other choices and synced through the settings item ([Settings storage](settings-storage.md)); a window shows the days or month it was moved to, which is not kept. Choosing an event opens the right sidebar. The arrow keys move the chosen event: left and right to the nearest day beside it that has events, up and down through a day's events in time order (`CalendarNavigation`), crossing into the next or previous week or month at the edge; Return opens it, Escape clears it, and a week scrolls to it. Today, back and forward count from the library's clock (`ItemLibrary.now`). Dragging, drawing a new event and a day view are not built.
- A gallery, table or board has no row of new-item chips above it.

## The bottom-right corner

Built, not yet released.

The window's bottom-right corner (`WindowCorner`) holds how a person views the screen, and nothing that changes items. A screen gives it its buttons and, where a button opens one, a card.

- The buttons are the system's Liquid Glass (`glassEffect` in a `GlassEffectContainer`), like the toolbar's, each on its own: no bar with dividers. Only back and forward share one capsule, with no line between them. A button that is on is gray, never the accent color.
- The corner sits over the content column and ends where the right sidebar begins, so it moves when the sidebar opens, closes or is dragged. It is empty, and draws nothing, on a screen with nothing to set: the list, the table and the board.
- A card the corner opens shows above the buttons at their width, right-aligned, and the buttons stay. The card is solid, not glass, and as tall as its content. A screen can place its card at the foot of the column instead, centered on the content and clear of the buttons: an item's formats bar is Liquid Glass and floats there. A button that is on, and a chosen segment of a segmented control, are gray, never the accent color. A layout change, or a change of place, closes it.
- A toast rises from the foot of the same column, so the corner lifts above it while one shows.
- The calendar, timeline and gallery end above the corner's buttons, so their last row or card scrolls clear of them.
- Every control is also a View menu command and a palette entry, so a hidden toolbar or a person who prefers the keyboard loses nothing.
- **Calendar:** Today, back and forward, Week or Month (a segmented control in the corner's own Liquid Glass, with the chosen segment gray) and a month button. The month opens above the buttons with today in red and, while the calendar shows a week, the seven days it shows marked in gray, joined where they run on, even where they cross a week's end (a month marks nothing, since the whole month is on screen); its arrows change the month the card shows without moving the calendar until the calendar moves, when the card follows it, and choosing a day shows that day's week (or month, in a month) and closes the card. The button reads Show Month, and Hide Month while the card is open, as the View menu does. Under 860 points of content width (`CalendarCorner.foldsBelow`), which the right sidebar counts against, Week or Month folds into one glass button with a menu. The View menu has Today (⌘T), Previous and Next Week or Month (⌥⌘←, ⌥⌘→), Week (⌥⌘1), Month (⌥⌘2) and Show Month (⇧⌘D).
- **Timeline:** Today scrolls to today's agenda, which is the top of the timeline. The View menu has Today (⌘T).
- **Gallery:** the card size by name (Small, Medium or Large) as one button with a menu. It is the size Edit View's Cards section holds, so either changes the other. The View menu has Small Cards, Medium Cards and Large Cards.
- **An item's page:** Focus, Aa on a page that can be written, the text size and a web page's Reader or Original ([Item page](item-page.md#the-pages-corner)). The image and PDF controls use this component and are not built yet ([Agreed designs](agreed-designs.md)).

## Opening an item

Built, not yet released. The page itself is in [Item page](item-page.md#opened-as-a-modal-or-a-full-page).

- Return, a double-click and Open open an item the way Settings > General > Open Items says (`ItemOpening`): **Over the List** (the default, a modal), **Full Page** or **New Window**. It is a MAPP setting kept in one key in the defaults (`openItemsIn`) and synced with the rest ([Settings storage](settings-storage.md)). Changing it does not close a modal that is open; it reads at the next open.
- Every layout opens an item the same way: the table, board, gallery, timeline, calendar and the list. A list with the page beside it keeps the page there: Return moves the keyboard to the page, and a double-click and Open follow the setting.
- A modal and a full page show one item, so Open does nothing for a selection of several. New Window opens a window for each item, and asks first when there are more than 10 (`ItemWindows`).
- One row menu serves every layout (`ItemRowMenu`, ordered by `RowMenuEntry`). It starts with Open, which follows the setting, then the other two ways (Open as Modal, Open as Full Page or Open in New Window), then Quick Look and Share…, then Add to Favorites, Add Tag, Add to Collection, what the layout adds (a board's Move To), Change Type, Customize Layout and Version History, and Delete last. The menu of items in Recently Deleted holds Recover in their place. It shows no key glyphs for Return and Space.
- Open, Open as Modal, Open as Full Page, Previous Item, Next Item and Close Modal are menu commands and palette entries. Previous Item and Next Item are Option-Command-Up Arrow and Option-Command-Down Arrow, and work only while a modal is open.
- A link to an item in an item's text follows the setting too (`Browser.follow(link:in:order:)`): the item is chosen where the window lists it, then opens as Return would, except that an item reached from the modal stays in the modal. Links in the property block and Linked From still show the item in the list.
- Not built: the modal's up and down arrows in a board, a timeline or a calendar follow the list's sort order, not the layout's own.

## Making an item

Built, not yet released. Quick add (`QuickAddPanel`, its draft in `QuickAdd`) is the one way to make an item: New Item on the Items page, the sidebar's New, Command-N and the palette's New row open it. The toolbar has no New Item.

- **The type it opens in** (`QuickAdd.startingType`): the sidebar's New and Command-N are also New in a type's list, so they behave the same everywhere. In a type's own place (a type's list, Collections or Files) they hold that type, whatever was used last. In every other place (Items, Inbox, Favorites, a saved view) they open in the type last used, or a note when that type is deleted or no longer offered. The type menu still changes it.
- **What the type gives it:** only what the type says. Its status shows as a chip, set to the first word in its not-started group, because Marfa declares no default status; a type with no status or no not-started word gives none. No other value is invented. Changing the type replaces a status the person did not touch and keeps one they chose. A status the person removes stays removed when the type changes.
- **A required field quick add cannot edit** (`QuickAdd.unsettableRequired`) is named under the title as soon as the type is chosen, before anything is typed: "Adding will be refused: this kind of item needs <Field>, which MAPP can't fill in. Choose another kind." The note is true because Add stays enabled and the library refuses the create (`MarfaEngine.creationProperties`), tells the person, and leaves the draft as typed. No other part of MAPP makes such an item either.
- **A value the type gave is not the person's content.** A panel holding only these values is empty: Escape discards it and closing the window raises no "Item Not Added".
- **The panel's height.** The text area starts at about two lines and grows as a person types, up to a limit, then scrolls; the panel is only as tall as its content, with no empty body below the text. A file item's drop area keeps its own larger height.
- **Add and Open** is the main button (Command-Return). The new item opens as Settings > General > Open Items says ([Opening an item](#opening-an-item)): a modal or a full page takes the insertion point in the text where it was in quick add, or the title when the item has no text; a new window opens the item there and leaves the list as it was. A refused or failed write never drops what was typed: the panel stays open with it.

## Empty states

Built, not yet released. Every layout draws an empty place from one rule (`PlaceEmpty`, drawn by `PlaceEmptyState`): a title, one line under it of fewer than 40 characters, and a button only where there is something to do.

- A type's place has New and the type's name, such as New Task, which opens quick add holding that type. There is no button when the library cannot be written to or the type is not offered. Favorites, Inbox and every other place have no button.
- In the list layout the empty message is drawn in the middle of the window's content, where the page would be, and the list column stays blank under its title and "No items". The same holds for filters that hide every item and for a search with no match. The other layouts fill the window's content, so they say it in the middle of that.
- Filtered to nothing, the list says "No Matching Items" with "No items match the filters." and Clear Filters is its button. A search with no match says "No Results" with "Nothing matches your search."
- The titles and lines: Inbox "Inbox Is Empty" and "Items from your apps wait here."; Favorites "No Favorites" and "Items you favorite show here."; Recents "No Recent Items" and "Items you edit show here."; Files "No Files" and "Files you add show here."; Items "No Items" and "Items you make show here."; a collection "No Items" and "Items you add show here."; a source "No Items" and "Nothing from this source yet."; a saved view "No Items" and "No items match this view."; a type "No <Plural>" and "<Plural> you make show here.", or "Nothing here yet." when a long plural would make that line 40 characters or more.

## Selection and hover

- A chosen row, card or table row is gray at 8% of the label color, and a row under the pointer is gray at 4.7%. Neither is ever blue. The list, the item table, the timeline, the index pages' tables, Settings' page list, Recently Deleted's list, and Version History's list take the 8%, and the sidebar's pending New View row does too; the list, both tables, the timeline and Recently Deleted's list take the 4.7% as well.
- `SoftSelection` draws both as layers beneath the table's row views, and the 4.7% follows the pointer from the table's own mouse events, so that mark runs no row's body. A row that is chosen, or that each list names as not an item (a date heading, the timeline's Earlier and now lines, a table's group header), gets no hover mark: a heading is not clickable, and the pointer does not change over it. In the item table a group's chevron is the only control in its header, folds the group, and is the only part that reacts to the pointer.
- A table cell that changes or adds a value keeps its own tint across the whole cell, which shows over the row's.
- A chosen gallery card and a chosen board card keep a soft 3-point ring in that gray, touching the card, with no fill and no plate behind it.
- A chosen calendar event keeps its color, and the palettes keep their own selection.
- A table row under the pointer shows its open control as the arrow alone, in the secondary label color, with no tile.
- The favorites mark is a star everywhere, in the system yellow: `star.fill` on a favorite in the table and the gallery card, and `star` and `star.slash` for Add to Favorites and Remove from Favorites in the menus, the toolbar and the palette.

## Saved views

A saved view splits between Marfa and the Mac. The rules for each side, and for deleting a view, are in [`MAPP/Model/AGENTS.md`](../MAPP/Model/AGENTS.md).

- **Marfa holds** the view's title, query, sort and group.
- **The Mac holds** the layout, the table's columns, whether the board hides empty groups, the gallery's cards, the calendar's Week or Month, the list's density and the table's widths (`ViewMacSettings`). See [Settings storage](settings-storage.md).

A type's list, and the other places that are not views, can become one with Save as View…, which is in View Options and the View menu and opens New View's panel filled in. The view keeps the filters, the sort and the grouping the window shows:

- A type's place saves what the window lists: with Include Subtypes on, the type alone as the view's types (Marfa lists it with its subtypes); with it off, the type's own items, as the type plus an exact-type condition where it has subtypes.
- A Type filter is saved as the view's types, so the view lists the types the window chose: they replace the types the place listed and a type's own exact-type condition. Marfa lists a type with its subtypes, so a chosen type that has any is also saved as an exact-type condition in the view's filter, which lists the same items as the window.
- An existing view's own Type filter is different: a chosen type within the types the view lists leaves them as they are, and is saved as an exact-type condition (`type eq`), so the view keeps its types and the filter stays a chip that can be removed or undone. A view of several types opens with those types as a Type filter only while its filter has no condition on the type. A chosen type outside the view's types replaces them.
- A list's sections by date (Today, Yesterday and the months) are not kept, and the Save as View sheet says so. A view groups by a field's value or a bucket of it, and Today, Yesterday and Previous 7 Days move with the day, so no grouping stands for them.

## Default views

Every place opens in a default view. A person can change the default view, but can't rename or delete it. A saved view has none: its choices are its own, as above. The three indexes, Items, Collections and Sources, have no default view: each keeps its own tab and sort (`IndexPreferences`) and has no layout to choose.

- **What it keeps.** The filters, the sort, the grouping, the layout and the layout's Mac settings: the timeline's date field, the board's compact cards, the gallery's cards, the calendar's Week or Month, the density and the table's columns. A place with no change keeps nothing, and choosing the layout a place opens in is not a change.
- **Where it is kept.** In the defaults on this Mac, and synced with MAPP's other settings except a table's columns and widths, so every window and every launch opens a place as it was left. [Settings storage](settings-storage.md) says where. An entry that cannot be read is kept aside, and the other places' entries go on working.
- **Two windows on one place.** Both write the one entry, so the last change wins. A window keeps what it shows until it opens the place again, and then shows the other window's change.
- **What has gone stale.** An entry for a type, collection or favorite that no longer exists is forgotten, but only once the server's copy has been read whole and is current, so a copy that is still filling or another server's never forgets one. A condition, sort or grouping on a field that no type of the place declares any more is dropped and the rest is kept. A layout the place no longer offers is not taken, and the place opens in its own.
- **Save as View…** is the last item of View Options and a View menu command, and it is no longer in the toolbar. It shows only when there is something to keep, and opens New View's panel filled in with what the window shows. While that panel is open the default view keeps nothing, and Escape puts the place back as it was.
- **Reset View** sits above Save as View… once a default view is changed, by a filter, a table's sort or grouping, the layout's own choices or the columns, and is not offered while New View's panel is open. It is also a View menu command and a palette command. It puts back the place's own layout, columns, density and cards, closes a filter row that was left open with nothing in it, and one Undo brings the choices back. A saved view keeps Revert View. Today the list's own Sort by and Group by are one setting for every place (Settings > Lists), not part of a place's default view, so changing them never offers Reset View. That is agreed to change: see [One Sort by and Group by for a place](#one-sort-by-and-group-by-for-a-place).

## Edit View

Edit View opens in the right sidebar, and New View uses the same panel. It holds the view's Name, Layout (a Show As pop-up), Density (a list only), Sort, Group, and Columns or Cards.

- A change applies as it is made, in the window beside the panel. Undo takes changes back.
- One Done closes the panel.
- Filters are not in the panel.
- Density holds a pop-up of As in Settings, Standard and Compact.
- Sort holds a handle, the fixed property, a direction pop-up and an x in a circle, with a gray Add Sort. Add Sort lists the fields of the types the view shows after its filters, and the columns every item has: the name and the type first, then the status and the other fields in the order the looks give them, then the parent and the dates.
- Group holds Group by and a Hide Empty Groups switch.
- Agreed, not built: Group and Columns change as [Edit View's Group section](#edit-views-group-section) and [Properties](#properties) say.
- Columns (a table) or Cards (a gallery) comes last. Cards has Preview, Size and Shape pop-ups and a Fit Picture switch; Shape is off when the preview is None, Fit Picture is off unless the preview can show a picture, and a gallery has no Density; what a card says comes from its type's look, not from the view.

## How an edit is saved

The funnel that writes each part where it belongs, and what it does when a write is refused, are in [`MAPP/Model/AGENTS.md`](../MAPP/Model/AGENTS.md). Column widths differ from the rest: they are kept only from a drag of a divider (`Browser.keepWidths`), because `TableColumnCustomization` cannot separate the column order and visibility from the widths, so the app owns those two.

## Filters

Filters live in one row above the list (`FilterRow` and `FilterChipsBar`) as squared 26-point chips: the field in gray, is or is not, the values and an x, then a square plus of the same height. A chip opens its value panel, with no counts, and the plus opens Filter By under it. A saved view opens with its row hidden.

Agreed, not built: every field kind has operators, the row can join its filters by All or Any, and more of what a person means can be saved: see [Filters for every field](#filters-for-every-field) and [The filter row](#the-filter-row).

There is no filter button in the list's toolbar, which holds Search and View Options. View Options opens with Show Filters or Hide Filters, then Sort by, Group by and Edit View. When filters apply, its button shows the count and is tinted while the window is active; in an inactive window it dims with the other toolbar buttons. The View menu has Show or Hide Filters, Add Filter and Clear Filters.

View Options also holds Include Subtypes, which lets a type's list show the items of its subtypes. The choice is stored for each type as `includedSubtypes`.

## Grouping, Properties and filters

Status: Agreed, not built. Drawn on MAPP Pages' Views tab. Where this section differs from [Edit View](#edit-view), [Filters](#filters) or the table's columns above, this is the agreed rule; each part moves up to those sections as it is built. The list is in [Agreed designs](agreed-designs.md#grouping-properties-and-filters).

### Which fields a place offers

One rule serves Group by, Properties and Filter By. The fields come from the types the place lists, never only from the items on screen, so a field no item has filled yet can still be chosen and a filter can never hide a choice.

- A type's place lists that type, and with Include Subtypes on its subtypes. A saved view lists its types and their subtypes, and a view of every type lists the types of the items it shows. Inbox, Recents, Favorites, a collection and a source list the types of the items they show.
- A menu offers only what a field's kind supports, in this order: Status, then the fields the types' looks show, then the item's own parts (Type, Parent, Collection, Tags, Created, Edited and Happened), then More Fields for the rest. A field no item in the place fills goes under More Fields.
- A field is listed once, by its key, under the label of the first type that declares it. Where two types give one key different kinds, the most specific kind wins: status, then priority, then the rest.

### View Options

One shape for every layout, which leaves out what does not apply:

- Show Filters (Hide Filters), then Sort by, Group by and Properties.
- The layout's own items: a board's Compact Cards, a gallery's card size, a timeline's Date Field and Today, a table's Rows at a Time.
- Include Subtypes.
- Edit View, Reset View and Save as View…

### Group by

The same menu serves every layout and every place. The timeline keeps Date Field as its only grouping, since its groups are days, and the calendar has none.

- **None** comes first, and a board has none: a board always has lanes.
- **Status** is one item where the grouping has one way to go, and opens Words and Groups where it has two. Words groups by the type's own words in the type's order; MAPP writes that order to Marfa, so another app does not list them A to Z. Groups uses Marfa's four groups (Not Started, In Progress, Completed, Canceled) and then No Status. Words is offered only where every type in the place has the same words. A status that is a plain choice, with no groups, is one item.
- **Each choice field and each yes or no field** is one item: a choice groups by its options in declared order, a yes or no by Yes, No and No Value.
- **Each date field** opens Day, Week, Month, Year, then **Set or Not Set**. A week begins on Monday, as Marfa fixes it for a saved view, whatever Settings > General > Week Starts On says. Created, Edited and Happened open Day, Week, Month and Year only, since every item has them. A bucket's groups follow the sort where the view sorts by that date and run newest first otherwise, and an item with no date sits in No Value, last.
- **Set or Not Set** makes two groups, Not Set first and then Set. It is offered for a date field and for any other optional field, on every layout, so a type whose start stays empty until it happens can be grouped as not started and started.
- **Type** is offered wherever the place shows more than one type. **Parent** groups by the parent item. **Collection** and **Tags** are offered in a list and a table only, and an item sits in each of its collections or tags. A grouping by collection needs the copy to hold that edge whole, and is refused, and said, when it does not.
- **More Fields** holds every other field the types declare. Each opens Set or Not Set, and a field of a kind with more ways to group (a choice, a yes or no, a date) keeps them there.
- A number, free text, a list of people and a list of words are not offered by value: one group for each value is noise, and Marfa cannot group by the members of a list.
- A field only some types declare gives those types' items their groups and every other item one Not Applicable group.
- After a divider: **Hide Empty Groups** (a tick), and, on a list and a table only, **Collapse All Groups** and **Expand All Groups**.

**Hide Empty Groups** is offered in every place and layout, and is kept on this Mac, in a saved view's Mac part and in a place's default view. **Collapsed groups** are the window's own choice, kept for each place, and reach the list as well as the table.

**A board's lanes.** A Not Set lane takes a card dropped on it and clears the field, where the type does not require the field. A Set lane and a lane of a date bucket (Day, Week, Month, Year) take no drop, since MAPP would have to invent a value ([Making an item](#making-an-item)).

**What a saved view keeps.** A saved view's grouping is only what Marfa holds, so every app shows the view grouped the same way. Marfa holds a field's value, a date's Day, Week, Month or Year, a type, tags, a parent and a collection. It does not yet hold Set or Not Set or the status groups: a Marfa change to let a view keep them is agreed and not built. Until it is, a place's default view keeps them on this Mac and Save as View names them as not kept ([Save as View](#save-as-view)).

### Edit View's Group section

Edit View's sections run Name, Layout, Density (a list), Sort (not on a timeline or a calendar), **Group**, **Properties** and Cards (a gallery). Group holds:

- **Group by**, a pop-up with the same menu as View Options.
- **By**, a second pop-up, shown only for a date field (Day, Week, Month, Year or Set or Not Set) or for a status that offers Words and Groups.
- **The groups**, one row for each in order, with a handle to drag the order and an eye to show or hide it. In a saved view they are Marfa's `group.order` and `group.hidden`, so they sync and other apps honor them. Dragging a board's lanes by their headers to reorder them, which would write the same order, is not built and waits.
- **Hide Empty Groups**, a switch, with "This Mac" in the section's note style.

MAPP reads and writes all four parts of a view's group (the field, the bucket, the order and the hidden groups) and drops none it did not change, including a field or bucket it cannot read. Choosing another field drops the old field's order and hidden groups, and writes the new field's declared order where it has one (a status's words, a choice's options).

### One Sort by and Group by for a place

- A place has one Sort by and one Group by, the same in View Options and Edit View, and the list in a place takes them as every other layout does. They are kept in the place's default view, so changing them offers Reset View.
- Settings > Lists' Sort By and Group By are the starting order for a place nobody has changed ([Settings pages](settings.md#lists)). This replaces the rule that the list's own Sort by and Group by were one setting for every place ([Rejected designs](rejected-designs.md#reversed)).
- Sort by lists the fields, then the two directions in the column's own words (Newest First). It is left out on the timeline and the calendar, whose order is time, in View Options and in Edit View. A board's cards follow the sort, which then syncs; today they sort by title whatever the sort says.

### Properties

One Properties list serves every layout of a view or a place, and replaces the table's Columns. It names what shows after the title: Status, Type and any field, tag, relation or count the place's types offer.

- **How a layout draws it.** A table shows the shown properties as columns in the list's order, with Name first and locked. A list row, a board card, a gallery card and a timeline row show the first two after the status as chips and count the rest in "+N", as a look's facts are shown. Switching layout keeps the same choice. A board grouped by a field never shows that field on its cards, and a timeline never repeats the time it places by.
- **It falls back to each type's look.** Until the list is changed, Edit View's Properties section is marked "As in Layouts" and every item shows its own type's look, as a view does today. Once it is changed the section is marked "This Mac", the view holds its own list for all its types, and a property a type does not declare is skipped for that type's items. **Use Layouts** at the section's foot, shown once the list is changed, puts the fallback back.
- **The look stays the default.** The Secondary line and the date stay the type's: each is one line, the look already chooses them, and a view that chose them too would give the same choice a second place.
- **Edit Layout of Events…** (for a place of one type, naming it) or **Edit Layouts…** (for several, asking which type from the place's types) opens Settings > Layouts at that type ([Settings pages](settings.md#layouts)). It is at the foot of Edit View's Properties section and of View Options > Properties, and the row menu has it beside Customize Layout.
- **View Options > Properties** has a tick for each property the layout can show, then Edit Layouts….
- **Edit View's Properties section** has a row for each property with its icon, its name, a handle and an eye, and Show More for the ones not shown.
- **Where it is kept.** On this Mac only, in a saved view's Mac part and in a place's default view, never in Marfa: a view holds no layout. Reset View puts it back.
- **Table column widths** stay the table's own ([How an edit is saved](#how-an-edit-is-saved)).

### The timeline's row

The timeline's row is as drawn on the timeline boards (V5 and V6). Every row is two lines and one height.

- The title is regular weight, on one line, with the row's chips at the trailing edge of the same line and a person's initials last.
- The second line is caption size, light gray. Where the list mixes types it starts with the type's name in plain gray text, and then comes the look's Secondary line. A source's name is not shown: a look cannot say one.
- The day rail, the time column, the red Now line, the rule between days and Today in the corner are unchanged.

### Filters for every field

Filter By lists every field a place offers in two sections: the fields of the place's types under their names (such as Tasks and Projects), Status first and then in the looks' order, and **Every Item** (Type, Tags, Collection, Parent, Source, Created, Edited and Happened). Its search field stays. A field already filtered can take a second condition.

Each chip's panel takes its field's operators, with the value control the kind needs: a value list, a date panel with its quick days (Today, Tomorrow, Next Week, In Two Weeks) and a month, a number field or a text field, or nothing for is set and is empty. A chip reads as a sentence: "Starts is set", "Due is before 30 Nov 2026", "Assignees include Rui Alves", "Status is not Completed, Canceled".

| Kind | Operators | Notes |
| --- | --- | --- |
| Status | is, is not (a word or a group); is set, is empty | The value list shows the words under their four group headings, and choosing a heading means the whole group. In a place of several types the four groups show first, which work across every type's words. |
| Choice, priority | is, is not; is set, is empty | |
| Yes or no | is Yes, is No, is empty | |
| Date field | is on, is before, is after, is between, is set, is empty | Then the relative operators below. |
| Created, Edited, Happened | is on, is before, is after, is between | No is set or is empty: every item has them. Then the relative operators below. |
| Number | =, ≠, <, ≤, >, ≥; is set, is empty | |
| Text, URL, email | contains, starts with, is, is not; is set, is empty | |
| People | include (by name or email); is set, is empty | No "does not include": Marfa cannot say it. |
| Tags | include, has any tag, has no tags | No "does not include": Marfa cannot say it. |
| Parent | is, is not, has one, has none | |
| Collection | in, not in, in any, in none | |
| Type | is, is not | The type exactly, not its subtypes. |
| Source | is, is not | |

A list of words has no filter, since Marfa's grammar does not say one.

### The filter row

- **All or Any.** Once the row holds two or more filters, a pop-up at its leading edge reads All or Any, and its menu is titled "All of these". With All, every chip applies together. With Any, every condition joins by OR, and a chip of several "is" values already joins its values by OR, so it stays savable.
- **What a view cannot hold.** Marfa joins a view's conditions all by AND or all by OR, never both (`filter-mixed-logic`). A row that needs both is named at once, under the row, in the filter row's note: "This view can save only filters that all apply, or all of which any one may apply". It is not left for Save as View to find. Under Any, a chip of several "is not" values beside other chips is such a row, since its values join by AND.
- **The "is not" rewrite.** Where a chip of a closed field (a status, a choice or a yes or no) holds several "is" values beside other chips, MAPP saves it as "is not" the other values, which Marfa joins with AND. The two select the same items, except an item that holds a word its type does not declare, which "is not" keeps. A row this rewrite cannot save is named under the row at once.
- **Relative dates.** A date operator under "Relative to Today" is worked out on the Mac each day: is before today, is after today, is in the last… and is in the next…. Marfa's filter has no relative date, and a fixed date would go stale, so a saved view cannot keep one: the row's note at its trailing end says so ("A saved view can’t keep “in the last 7 days”"), and Save as View names it as not kept. A relative date works in the window and in a place's default view, which stays on this Mac.
- **The limit of 10.** A view keeps up to 10 conditions; each value of each chip and each bound of "between" counts. The plus stays enabled in the window, and Filter By's foot says how many the row holds ("A view keeps up to 10 conditions; this one has 9") as the row nears the limit.
- **Unchanged.** The row above the list, its squared 26-point chips and square plus, no filter button in the toolbar, a saved view opening with its row hidden, and a saved view's own condition the row cannot show as a locked chip.

### Save as View

New View's panel has a section, **Not Saved in the View**, with a count and a row for each choice the view will not keep: a grouping Marfa cannot hold yet ("Group by Starts: Set or Not Set"), a relative date ("Edited in the last 30 days") and a list's sections by date. The section is not shown when nothing is left out.

## Index pages

Built, not yet released. Items, Collections and Sources are index pages: a table under tabs, with no list, gallery or other layout. Views and types keep the list column and their layouts. Tabs and a New button on the page appear only on these three pages: a view or a type is split by the sidebar, its filters and saved views, and New is the sidebar's New and Command-N.

Each page is a large title, then the tabs with Search, Filter and New (+) as plain symbol buttons at their trailing end, then the table (`IndexScaffold`, `IndexPageTop`). The title, the tabs and whatever stands under them (Items' New row or the filter row) scroll away with the rows. Once the title and tabs have scrolled out of view, the tabs (the system's segmented control, in the middle of the toolbar), Search, Filter and New come into the window's toolbar, and are absent at rest. Edit, on Items, is an ordinary toolbar item at rest as well, since the page has no button for it, but only while the New row shows; the column headings stay pinned under the toolbar. Rows that scroll up under the toolbar are blurred by the same band as every other scrolled view's (`ToolbarBand`, drawn by `IndexScaffold` once the rows are past the headings), never seen clear through the toolbar. The headings have the same background as the table and a thin line under them, so rows that scroll under them never show through, and the band behind the title and tabs has no fill of its own: the whole page is drawn on the table's own background, in light and in dark. The Filter button is the one exception to a button that is on being tinted: it is drawn gray while it is on, never in the accent color. Search opens into a field in place at the tabs' trailing end, about 240 points wide, filters as it is typed in, and closes on Escape or when it is cleared; the toolbar's Search is the same field, so the two never show together.

The three index tables look as the item table does: rows 36 points high with the text centered, no line between the column headings, and one line under them that runs from where the first column's cells start to where the last one's end, as the rows' separators do, including under an icon. The headings look the same whether or not the window is the key one.

### Items

- Items (`ItemsIndex`, its rows worked out by `ItemIndexModel`) has the tabs All, Yours (the library tier) and From Apps (the feed tier), each with its count, and the tab chosen is kept for the page on this Mac (`indexTab.items`). New Item (+) is at the trailing edge of the tabs and opens quick add.
- **New** is a row of tiles under the tabs, shown only while Show Quick Add Options is on in Settings > Lists (off until turned on; the toolbar's New and the View menu's New Item are there either way), each about 132 by 78 points with a 12 point radius, tinted with the type's color, with the type's icon and its name under it in that type's icon color, medium weight (`NewTiles`), set a clear 20 points under the tabs. A tile opens quick add in that type. The row starts with Note, Table, Task, Bookmark, Event, Person and Place, skipping any the library lacks. **Edit**, an ordinary toolbar item with no fill and in the toolbar on Items while the row shows (the View menu's Edit New Row… and the palette's likewise), opens a popover of the types a person can make: those in New, ticked and in New's order, which dragging reorders, then the others, unticked. While it is open each tile shows a minus badge that takes its type out. Which types New holds, and their order, is a MAPP setting (`indexNewTypes`), synced with the rest ([Settings storage](settings-storage.md)).
- **Filter** shows or hides the filter row ([Filters](#filters)), which stands where the New row does, with no count of items beside it and the tiles hidden. The table keeps what the filters allow. Turning Filter off clears the filters.
- **New Table** has no column chooser: a table's `columns` property is required and quick add cannot set it (`QuickAdd.unsettableRequired`), so the Table tile opens quick add with the note it shows for any such type.
- The table has the columns Name (with the type's icon in its color), Type, Source and Updated. A column's header sorts it and the sort is kept (`indexSort.items`); Items starts with the latest change first. While a search is under way the rows keep the library's relevance order, with no arrow on a header, until the person clicks a column or chooses a Sort By column; Sort by Relevance in the palette and Relevance in View Options bring it back. A window has no View As for Items, so a layout kept for Items by an earlier version is ignored.
- Rows are chosen as in the other tables: a click, Command-click, Shift-click and Command-A. The row's menu, Delete, Favorite and Add to Collection act on every row chosen. The right sidebar shows one item's details with Open at its top when one row is chosen, and says how many are chosen when there are several. Return, a double click and Open in the row's menu open an item as Settings > General > Open Items says ([Opening an item](#opening-an-item)). The item leaves the choice when it is deleted or goes on a sync, never pointing at an item that is gone, and its row leaves the table at once; one that moves to the other tier stays chosen. An item opened as a full page from Items, and then deleted, gives way to the next row, as in the other layouts.
- A reveal on Items, from the Search palette or a link, for an item under the tab that does not list it switches to All and scrolls to the row. Down in the search field moves into the table.
- With nothing in the library the page says "No Items" with "Items you make or apps send show here." and no button, since New Item stays on the page. A tab with nothing in it says so in one short line.
- A library may hold tens of thousands of items, so the rows are worked out once for the items and the sort, off the main thread above 2,000 items, and a change of tab reads one list of rows. The table draws 200 rows at a time. The page's body never reads the choice, so choosing a row runs no other row's body. The rows stay when the person leaves Items, so coming back shows them at once while they are worked out again, less any item deleted meanwhile; the first time shows a loading state, never a blank page. A change to the library does not move the row of the item chosen, so editing it in the right sidebar under a sort by the latest change leaves it where it is until another item is chosen.

### Collections and Sources

- Collections and Sources are one kind of page, an index of containers, drawn as a table (`IndexPage`) the window's full width, as Items is, with the large title, the tabs and the table and no New row. Collections are not grouped by kind. Collections has the columns Name, Source (the source that wrote it, left empty when none did), Items and Updated (when the collection itself last changed). Sources has Source, Writes (the types it writes, each as the type chip item pages draw, at row size, three at most with the rest counted as "+N"), Items and Latest (its latest item's change). A column's header sorts the table, and the sort is kept for each page on this Mac (`indexSort.<place>`). Collections start by name and Sources by how many items they hold.
- Collections has the tabs All, Yours (the library tier) and From Apps (the feed tier). Sources has All, Apps (signed in) and Keys. A source is an app when its code starts with `oauth:` and a key otherwise (`SourceCode`). Each tab shows how many rows it holds, the tab chosen is kept for each page on this Mac (`indexTab.<place>`), and a tab with nothing in it says so.
- A collection's icon is gray. A type's icon in a table is in the type's color, with no tile, and a type with no icon has the neutral color and mark.
- The chosen container shows in the right sidebar (`IndexInspector`), with no buttons there: its latest items, the types in it, and its details: a collection's Created, Updated and Source (left out when no source wrote it), a source's Kind and Code. The table takes the window's width when the right sidebar is closed. The choice is held in `IndexChoice`, not in a view's state, so choosing a row runs no other row's body, and it clears when the container is deleted or goes on a sync.
- A double click, Return or Open in the row's menu opens the container. A collection's menu and the Delete key delete it, except a read-only collection, which offers no Delete; a source's menu renames it or chooses its mark.
- Deleting a collection asks with Apple's alert, then moves it to Recently Deleted and shows the toast with Undo ([Components](components.md)). Its items are kept: they hold their own place in the collection, so Undo brings it back with them.
- Collections has Search, Filter and New Collection (+) at the tabs' trailing end; its filter row holds the Source filter, which narrows the table to the sources chosen. Sources has only its tabs. View Options sorts the table.

## Sidebar

Status: the sidebar customized in place is built, not yet released.

The sidebar is a list of sections. A new library has four, in one tab: the shortcuts New and Search, Library (Items, Sources and Collections), Views (Inbox, Recents, Favorites and the saved views) and Types. The arrangement is kept for each server (`sidebarLayouts`).

- **Tabs.** There is one tab, Home, and no tab bar. Once a person has a second tab, tabs show at the top: each is its symbol, the chosen one also shows its name, and a plus button adds one. A tab's context menu renames or removes it. Removing a tab moves its sections to the end of the first tab, so none is lost. Each window keeps its own chosen tab.
- **Customize Sidebar** is in the context menu of the sidebar and of each row and heading, and in the View menu, and has no button in the sidebar. While a window customizes, the foot shows Done in place of the instance, rows and headings have a handle at the trailing edge, and the rows drag to reorder. Customizing is one window's state: the layout is shared by every window, and Done ends it only in the window where it was pressed.
- **A section's menu** (at its heading while customizing) has Show (which rows the section lists), Rename, Move Up, Move Down, Move to Tab (including a new tab) and Hide Section. A section's handle drags it onto another section of the tab. Hiding a built-in section keeps it, and Add Section brings it back; hiding a section of the person's own removes it. Add Section also adds a new section, alone or holding a collection or a source.
- **Rows.** A section of Library, Views or the person's own can hold views, collections and sources. A row whose view, collection or source is gone, or has not synced yet, is left out and the section stays; the layout still holds it, so the row returns with it. A section that holds only its own places keeps the order of the sidebar's blocks (the Library's three, then Inbox, Recents and Favorites, then the saved views); once a row is dragged or moved into it, the section is one list in the person's order. Removing a section the person made frees the collections and sources in it to be added again. A row's context menu has Move to Section and Hide from Sidebar. The Types section lists top-level types while customizing.
- **Shortcuts** are rows that act or go somewhere and never take the selection: New, Search, Settings, a place to go to, or a kind of item to create. A new library has New and Search; no shortcut makes an item of a type the person made. Add Shortcut adds one to the tab, and a shortcut's context menu removes it.
- **A place's mark** is its symbol with no tile, gray until the person chooses a color from the row's context menu. Every view (Inbox, Recents, Favorites and the saved views), Items, Sources and Collections, and a collection or a source in a section of the person's own take a color this way; a type keeps the color of its own mark. The context menu is an AppKit menu (`SidebarPlaceMenu`), because a SwiftUI menu holds only commands and cannot hold the colors, which are one view of their own: one row of swatches no wider than the menu's text entries, which scrolls sideways under a soft edge when they do not fit, and the chosen one shows a check. The choice is kept on this Mac, and a color chosen before gray became the default stays.

Opening and closing sections, and parent types in the sidebar, are not built.

## Menus

Built, not yet released.

The menu bar holds every command the toolbar, the corner and the row menus offer, so each can be reached from the keyboard and from a window with the toolbar hidden. A command that only arranges the sidebar (a row's Choose Icon… or Move to Section) stays in the sidebar's own menus, and Customize Sidebar… in the View menu opens them, showing the sidebar first if it is hidden. Each command is also in the command palette, under the menu it belongs to.

- **Go** lists the places (Items, Sources, Collections, then Inbox, Recents and Favorites), then the saved views, then the types the sidebar lists before Show More, in the sidebar's order and under its names, and All Types, a submenu, for every other type: those after Show More and those hidden in the sidebar, so Go reaches every type with the sidebar hidden. A subtype is named after its parent (Tickets > Bugs), since a menu has no indentation. A saved view hidden in the sidebar is left out, and the places stay. A section with nothing in it, such as the saved views of a library that has none, is left out with its divider (`MenuSeparators`). A view deleted, or a type removed, while the menu is open opens Items. Each place, view and type has its sidebar symbol, a check mark stands by the place the window shows, and the saved views and the types sit under the headings Views and Types. The Go menu has no keys.
- **View** holds Customize Sidebar… (Finish Customizing Sidebar while it is on) and Finish Editing View, which are the sidebar's Done and the Edit View panel's Done. Recently Deleted is not in it.
- **File** holds, on the Sources page, Rename Source… and Choose Source Mark… for the chosen source, and on the Collections page Delete Collection… for the chosen collection, as the row's menu does.
- **The commands of opening, the page and the view** are in the menu bar too. File holds Open, Open as Modal, Open as Full Page and Open in New Window. View holds Focus, Show Formats, Reader and Original, the image's Zoom In, Zoom Out, Actual Size and Zoom to Fit and the PDF's next and previous page, Reset View and Save as View…, and, while an item is open in the modal, Previous Item, Next Item and Close Modal. The toast's one action is Undo, which Edit > Undo runs.
- **Help**, after the system's search field, holds MAPP Help, Keyboard Shortcuts, What's New in MAPP, Marfa Documentation and Report a Problem…. They open in the browser, so there is nothing to handle without a network, except Keyboard Shortcuts, which opens Settings at the Keyboard page.
  - MAPP Help opens this project's README on GitHub (`https://github.com/withmarfa/mapp#readme`), until the app has a help book of its own.
  - Keyboard Shortcuts opens Settings at the Keyboard page, where every command's shortcut is listed and can be changed ([Keyboard shortcuts](keyboard-shortcuts.md)). Back and Forward give their keys up while the page has the keyboard.
  - What's New in MAPP opens the project's releases, and Marfa Documentation opens `https://docs.marfa.so`.
  - Report a Problem… opens a new issue with the app's version and the macOS version in its body, and nothing about the person, their library or their server.
  - The addresses are in one place, `AppLinks`.
- **Recently Deleted** is a page of Settings only, not a place in the sidebar or the menus. A link to a deleted item opens Settings > Recently Deleted, and a window saved while it was a place opens on Items. A stored sidebar layout that names it is read as before, and the entry is ignored.

## Command palette

Command-K and Search Items share one 680-point panel (`CommandPalette`), which sits about an eighth of the way down the window, as quick add does.

- The field has room above and below it and no divider under it. Its magnifying glass sits in the rows' mark column, so the typed words start where the titles do.
- Every row in a list is one height: one line in the command palette, two in Search Items. Both palettes draw a row the same way: the type's small mark, the title in regular weight, and the detail or date at the right. A Search Items row adds a second line under its title, and keeps its mark and date on the title's line: the words around the match, or else the item's own text, or for an item with none, its type (or Inbox) and the collections it is in. The results have sections, with the one that holds the best match first, and a gray selection. With nothing typed, Search Items shows only its Recent section. The count sits at the top right of the field.
- A bar sits at the foot of the results, and rows scroll under it, fading and blurring out with the system's soft scroll edge effect; the last row of a short list sits above it. At its right, Open and Actions are one glass capsule with two segments, as the toolbar groups its buttons: pointing at a segment fills only that segment. Open reads Open for an item (Search Items still opens an item at the match) and Run for a command, with 14-point labels, a point larger than a large control's. Their key caps, and those in Actions, are `KeyCap` (see [Components](components.md)), one glyph to a cap: 16 points high with 4-point corners, a 10-point medium glyph in the label color at 42% opacity, a 1-point outline in the label color at 20%, and no fill. Menus keep the system's plain glyphs. In Search Items only, a round glass button at its left, as tall as the capsule and no wider, shows the palette's filter row, which holds the view's chips for Type, Collection and Updated, with a + as tall as a chip. With filters set, the button shows their number and a soft fill inside its glass, in the bar's neutral color, never the accent. The row takes its room from the list, so showing filters never makes the palette taller. The command palette has no filter button.
- Actions takes the bar's place: it grows up and to the left out of the bar, anchored at the bottom right where Actions stood, and shrinks back into the bar when it closes. It opens with a click on Actions or with Command-J (Edit > Palette Actions, a command in the shortcut catalogue, so Settings > Keyboard changes it and the bar's key caps follow; Command-K opens the palette itself), and its surface is the palette's own. There is no second panel above the bar.
- Nothing in either palette shows a tooltip.
- The two palettes are named for what they search. Search Items (Shift-Command-P, and Edit > Search Items…) searches every item, and its field reads Search Items. Command-K's field reads Search Commands and Items, and its last row reads Search Items for “typed words”. This is built and not yet released.
- With nothing typed, Command-K lists Recent, then its commands in sections that follow the menu bar: Settings (the app menu's), File, Looks (which the File menu holds), Edit, Format, View, Sort and Group, Text Size, Go, and Debug last in a Debug build. A command sits under the menu that holds it, in that menu's order, and a section with no commands is not shown. New Item is the only New row listed; New Task and the other typed ones are found by typing. Once something is typed the commands are one ranked Commands section. This is built and not yet released.
- When nothing matches, either palette stays about 400 points tall (never taller than a full list) and shows No Results in the middle, or Still Looking while the copy is filling or behind, since what matches may not have arrived. The bar's one button reads New Item with the Return key cap and has no Actions segment. Return or a click opens quick add, in the type last used, with the typed words as its title; with nothing typed it opens an empty draft, and a draft already holding content comes back as it was. Search Items keeps its filter button. This is built and not yet released.
- Settings > Appearance > Palettes sets what the palettes and New Item are drawn on: Glass (Liquid Glass, the default), Translucent (the system's popover material) or Solid (the window's own color). It is a MAPP setting (`paletteMaterial`), synced with the rest ([Settings storage](settings-storage.md)).
- **What Search Items keeps and leaves out** (`SearchNarrowing`) goes into the search itself, so the 500 results the copy lists are counted after it, and a filtered search never misses an item the cut would have dropped.
  - Its Type filter is part of the search. A type follows its Include Subtypes choice: off, only the type's own items; on, the type and every type below it. "Is not" skips the type, and its subtypes only with Include Subtypes on. Its Collection and Updated filters still narrow what the search found, and the filter row has no Source filter.
  - The search leaves out the types and sources the person left out of search (`SearchLeaveOuts`, a setting for each server, synced, empty until chosen). A type left out takes its subtypes with it. The command palette's Items list, a list's own search and a place's search leave nothing out.
  - When what is left out matches too, the results end with one line under a rule: a mark, "36 more in GitHub, left out of search.", and Show. Show searches once more with nothing left out, for that search only. The count is one more search of only what is left out, limited to 100, so a full answer reads "At least 100 more". The line names up to three sources or types and otherwise says only how many. Nothing counts while no leave-out is set.
  - More than ten conditions or ten types in one search is refused and shown as Can't Search, which a person fixes by choosing or leaving out less. One type chosen without its subtypes is one condition however many subtypes it has. This is built and not yet released.
- There is no preview pane beside the results. A row carries its own excerpt.

The palette builds its own list of commands. The rule that every toolbar action is also a command is in [`MAPP/Views/AGENTS.md`](../MAPP/Views/AGENTS.md).

## Controls

- Segmented controls are the system's own Liquid Glass capsule, as Apple Music draws it: a pale capsule with round ends and the chosen segment as a capsule inside. MAPP does not draw a flat, squared or hand-drawn one. See [Rejected designs](rejected-designs.md).
- A pop-up button has gray chevrons in a round well. A switch is the system's `Toggle`, at its mini size in Settings, 36 points wide as the boards draw it.
- Buttons and menu items use title case, and the words in the app follow the Writing section of Apple's Human Interface Guidelines. Symbols are SF Symbols at text sizes.
- Agreed, not built: a menu that chooses shows a tick only where a row can be ticked, and the View As menu has no icons, as Finder's has none.

## Large libraries

The rule for large lists is in [`MAPP/Views/AGENTS.md`](../MAPP/Views/AGENTS.md).

## Where things go

The window has three areas: the sidebar, the list pane and the page. What a person moves between goes in the list pane. A screen adds no new kind of column or toolbar, and only the pins sit under a page's title. A screen that needs something this does not allow changes the rule first.

- The toolbar holds the same buttons on every screen: Search, View Options, View As, Share, More and the right sidebar. The right sidebar's button is a glass button of its own, never joined to Share and More, and it is gray, not the accent color, while the sidebar is open. A screen hides a button that does not apply. No screen adds its own controls to the toolbar, and the gaps between its groups are the system's.
- The page holds at most one main action, such as New Collection or New Item.

## Settings

Status: Built, not yet released. Settings is a window of its own, not a place in the main window; [Settings storage](settings-storage.md#the-settings-window) says what it holds and how it is opened.

Where it lives: `SettingsWindowView`, `SettingsSidebar`, `SettingsNavigation`, `SettingsLauncher`, `SettingsTokens`, `SettingsSection`, `SettingsRow`, `SettingsButton`, `SettingsSearchField`, `SettingsHead`, `SettingsProblemRow`, `SettingsPageState`, `SettingsReadOnlyValue`, `SettingsSheet`, `ChoiceTiles`, `SettingsSectionTable` and `SettingsPageTable`, under `MAPP/Settings/`.

The rules every page follows, agreed with August on 19 and 20 November 2026:

- **A window of its own.** One sidebar, the system's sidebar list, lists MAPP's pages, then the Marfa's, in sections with the system's headers and gaps, each page a 28-point row with a 20-point color tile (the system's small row size), and the system's search field at the top finds a page by its name or by the title of a row it holds. A page is listed only once it exists. The content is one column at most 620 points wide, centered, with more room either side as the window widens; the page scrolls as one. The window opens at 1200 by 900 points and remembers the size it was left at.
- **The toolbar** carries Back, Forward and the page's name. There is no back button beside a title. Back and Forward are also the View menu's ⌘[ and ⌘] while Settings is key. A page inside a page, such as a key's own page, is pushed, so Back returns.
- **Rows.** A row is a lead, a title with one line under it (two at most), and one trailing edge. Rows are 44 points, 56 with a line, 36 for a list of words. A text field and a pop-up are 200 points wide and 28 tall (the system's large size), the pop-up the system's menu pop-up, at the row's trailing edge. Text under a title is 12 points, and a card's corners are 12 points. Leads sit in one 24-point column, so text starts at 52 and the divider at the text. An app, a source or a connector takes the well in that column: a white 24-point tile with a hairline round its symbol or mark (`SettingsLead.well`).
- **Sections.** Every section is named; a thing's head card is the one exception. Cards are white with a hairline, never gray. A section has a line under its name and a footer under its card.
- **Changing things.** Something new with several fields is a sheet, in the middle of the window, as an alert is. Apple's alert asks before what can't be undone. A thing with settings of its own is a page.
- **Numbers.** A field with its unit inside.
- **Problems and errors.** A problem row offers only actions that exist: both as buttons where there are two, one button and a menu where there are more. A refusal for want of a permission offers Allow More… (never Try Again), through `OwnerProblemRow`: the lock leads the row as a plain symbol, with its explanation beside it and the button at the trailing edge, and its line names no button. An error is the design system's red: a ring round the field and one line under the title, and what was typed stays.
- **Buttons are the system's bordered buttons** at the large size, 28 points tall (regular inside a table). A default action, such as a sheet's confirm button or an alert's default button, and Update take the system's default look; a destructive button is the system's destructive role, tinted red. No button sits in a section's header: adding is the card's last row, and a table's filter and search are the only controls at a section's name. Switches, pop-ups, search fields, alerts and text fields are the system's, and a click anywhere outside a text field ends editing.
- **Tables.** In a section, a table is light, with no rules between rows and a page at a time; its foot shows how many and a Show All button that opens it as a page. As a page of its own it fills the pane: its count is on the left and its filter and search are together on the right, then a checkbox column and the columns, with how many are selected of how many and the actions for the selection at the foot. Rows are 34 points in a section and 30 on a page of its own. In a section a row action shows on every row; on a page the foot acts on the selection.
- **Words.** "Permanently Delete", never "for good".
- **Named values.** Every color, font and measure is a named value in `SettingsTokens`, never written in a page, so themes can come later.
- **The Marfa's pages** need an owner permission each. With it missing the page is the centered state "Needs a Permission" with Allow More…; its line is one line at the state's measure (420 points); with the server not answering it says so with Try Again; with no copy open or the sign-in ended it says so and points to Connection. MAPP's own pages work in every case.

## The list's rows

A list row is one view for every type, in Standard or Compact. Settings > Lists holds the Density every list follows, Sort and Group; Edit View's Density picks one for a saved view, and a place that is not a saved view keeps its own on this Mac. A gallery card, a board card and a table cell draw the same look in their own layout. See [Presets and densities](presets-and-densities.md).

## Related pages

- [Looks](looks.md)
- [Settings storage](settings-storage.md)
- [Item page](item-page.md)
- [Components](components.md)
