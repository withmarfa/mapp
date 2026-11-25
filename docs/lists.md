---
summary: The rules of views, layouts, grouping, filters, properties, indexes and search, and what Marfa can save of them.
paths:
  - MarfaMac/Model/Browser+*.swift
  - MarfaMac/Model/EarlierPlaces.swift
  - MarfaMac/Model/View*.swift
  - MarfaMac/Model/ItemViewMode.swift
  - MarfaMac/Model/Items/Filter*.swift
  - MarfaMac/Model/Items/*Group*.swift
  - MarfaMac/Model/Items/ItemPlacement.swift
  - MarfaMac/Views/Filter*.swift
  - MarfaMac/Views/ItemTable*.swift
  - MarfaMac/Views/ItemBoard*.swift
  - MarfaMac/Views/ItemTimeline*.swift
  - MarfaMac/Views/ItemCalendar*.swift
  - MarfaMac/Views/Index*.swift
---

# Views and lists

A place lists items. Its layout, filters, sort, grouping and properties are its view.

## Two kinds of view

- **A place's default view is the app's** (`PlaceDefaults`). Every change is kept as it is made, and Reset View puts the place back. The index pages have none: they keep a tab and a sort (`IndexPreferences`).
- **A saved view is an item in Marfa.** Marfa holds its title, query, sort and group. The app holds the rest (`ViewMacSettings` in `ViewLayouts`): layout, properties, cards, density, week or month and column widths.
- **A change to a saved view is written as it is made** (`Browser+ViewWrites`), naming only the settings that changed, so it never writes over another app's.
- **A write that Marfa has not taken stays in the window.** Until it is taken, Save View sends it again and Revert View drops it (`hasViewChanges`).
- **The window lists what it shows while a change waits.** While its filters, From or Archived Items differ from the view's own, it reads the view's query with the window's choices (`viewPreview`).
- **Undo takes back only the settings of its own step**, so another app's change stays.
- **An entry for a thing that is gone is forgotten only when the copy is whole and current**, because a copy that is filling also lacks things.
- **Save as View saves what Marfa can hold and names the rest first** (`ViewDraft.Unkept`). A type's place saves the type, which Marfa takes with its kinds, and an exact-type condition only with Include Kinds off; a Type filter takes its place. The window's From and Archived Items become the view's tier and states, and a view's become the window's (`ViewDraft`).
- **Making, renaming and deleting a view needs the server.** A view has no bin, so deleting one asks.
- **A saved view belongs to one place** (`Place.home(of:catalogue:)`). Use its sole type, else the sole collection or source its filter requires. Collection membership uses the item's outbound edge. For the feed tier alone, use the Feed. Otherwise use the Library.
- **The Library and the Feed list their own tier.** A type, a collection and a source choose a From (`ListScope`), starting on `lists.defaultScope`.
- **Favorites has an ordinary From,** starting on Library; a person may choose All Items. Its row counts what that From lists.
- **A type counts and lists its kinds** unless Include Kinds is off. A saved view that names no state shows archived items (`ArchivedItems`).
- **What earlier copies kept is read in to new keys** (`EarlierPlace.readIn`), at launch and after each settings sync, where the new keys leave it unset. Each earlier entry is read in once on each Mac, and stays for those copies. The Library takes All Items' settings, filled from Recents'. Include Subtypes is not read in.

## Layouts

- **The Archive, reached from the Library page's tabs and Go, opens as a table of Name, Type, Source and Edited.** Its title is the Library's, with its count ("10 of 213" when narrowed); empty, it says "Nothing is archived."
- **Unarchive and Delete stand on an Archive row under the pointer** (`RowQuickActions`).
- **A layout draws the list it is given** (`ItemViewMode`) and never changes which items show.
- **One row menu, one density and one drag serve every layout.**
- **An item's date is its own type's** (`ItemPlacement`), so a place of several types puts each where it belongs. A person can point the view at one field.
- **An event's span is one rule** (`EventSpan`): all-day events sit on the days they are lived in, whatever the Mac's zone.
- **A board always has lanes.** With no grouping chosen it takes the status. Types with different words make the four status groups.
- **A drop in a lane is one edit.** A drop in Not Set clears the field; Set and date lanes refuse a drop, because no single value is meant.
- **A table's widths are stored only from a drag of a divider** (`keepWidths`). AppKit's own layout of columns is never stored, because it changes without the person.

## View Options

- **The order is fixed:** filters, sort, group, properties, the layout's own options, Include Kinds, then the view's commands. The menu bar and palette have the same (`ViewOptionCommand`).
- **An option that a place or layout lacks is absent.**

## Grouping

- **The offer comes from the types a place lists, never from the items on screen** (`GroupOffer`), so a field no item fills can be chosen.
- **A grouping has a mode** (`GroupMode`): each value, a date's span, set or not set, or the four status groups.
- **Marfa saves values and spans.** Set or Not Set, and status groups, stay in a default view and are named when a view is saved.
- **A saved view's weeks start on Monday,** as Marfa fixes them for every app. A place's own follow Settings.
- **Not Applicable is last**, for items whose type lacks the field. It is the app's and is never written.
- **A hidden group leaves the layout and not the count.**

## Filters

A filter is a `FilterClause`: a field, a `FilterOp` and values, shown as a chip.

| Part | Where |
| --- | --- |
| Which fields a place offers | `FilterOffer`, `FilterTarget` |
| The operators of a kind of field, in order | `FilterOp.offered(for:)` |
| The row, its chips and their panels | `FilterRow`, `FilterChips`, `FilterClausePanelHost` |
| What a chip says | `FilterWording` |
| Which rows a filter keeps in the window | `FilterMatching` |
| To and from a saved view's query | `ViewDraft` in `ViewDraft+Filters.swift` |

- **A new operator or kind changes every row of that table.** `FilterMatching` and the query must keep the same items; test both directions (`FilterClauseTests`, `ViewDraftTests`).
- **Marfa's filter is one list, joined all by and or all by or.** A mix is refused before it is sent (`search-and-filters/filter-mixed-logic`), except that "is" several words of a closed field is written as "is not" the others.
- **A view takes ten conditions.** Each value and each bound of a date counts.
- **Marfa has no relative date.** "Is in the last…" and the like (`FilterOp.isRelative`) stay in a default view and are left out of a saved one.
- **Marfa has no "does not include"** for people and tags, and cannot ask about a list of words, so neither is offered.
- **A day is the person's day.** A date with a time is bounded by the Mac's clock, with its offset. A date alone is midnight UTC in Marfa, so it is counted in UTC (`FilterTarget.isDateOnly`).
- **A condition the window cannot show is a locked chip,** kept whenever the view is written.
- **What a view cannot keep is said in the row** before the person saves.
- **An unfinished filter hides nothing** and is dropped when its panel closes.
- **A saved view opens with its filter row hidden**, and View Options counts the filters. Whether the row shows is never saved.

## Properties

- **One list serves every layout** (`ViewProperties`): columns in a table, chips elsewhere.
- **Until the person changes it, each item shows its type's look**, and Use Layouts goes back to that. The first change makes the list the view's.
- **The date and the second line stay the type's.** A field one of them already says is not listed again.
- **A stored property that a place lacks is kept**, because another place may have it.

## Indexes

- **The Library's index, Collections and Sources are lists of things, not of items of one view** (`IndexPage`). The Library's tabs are All, Library and Feed. A long list of items is worked out off the main actor (`ItemIndexModel`).
- **Trap:** an index page's body must not read the choice, or choosing a row draws every row.
- **A row's count is of what the place lists.** A file attached to an item the library holds shows on that item's page, so no list or count but search takes it, Archive, a collection and Favorites included. The Feed's row has none. Counts are worked out once for each change of membership (`MarfaLibrary.scopeCounts`).
- **The Library's Feed tab holds what a search finds there.** An Items page left on From Apps opens on All once.

## Search

- **A search is narrowed in the query, never after it** (`SearchNarrowing`), because Marfa limits how many it answers, and a limit counted first would hide matches. More conditions than a query takes are refused and named.
- **What a search leaves out is said** (`SearchLeaveOuts`), with a way to include it.
- **A search in the list and in Items is sorted by relevance until the person sorts it.** The gallery and the table keep their own sorts until relevance is picked (`Browser.ordersByRelevance`).
