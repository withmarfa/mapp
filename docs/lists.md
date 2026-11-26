---
summary: The rules of views, layouts, grouping, filters, properties, indexes and search, and what Marfa can save of them.
paths:
  - MarfaMac/Model/Browser+*.swift
  - MarfaMac/Model/EarlierPlaces.swift
  - MarfaMac/Model/View*.swift
  - MarfaMac/Model/ItemViewMode.swift
  - MarfaMac/Model/Items/Filter*.swift
  - MarfaMac/Model/Items/Search*.swift
  - MarfaMac/Model/Items/*Group*.swift
  - MarfaMac/Model/Items/ItemPlacement.swift
  - MarfaMac/Model/Items/ItemNesting.swift
  - MarfaMac/Model/RowHold.swift
  - MarfaMac/Views/Filter*.swift
  - MarfaMac/Views/ItemTable*.swift
  - MarfaMac/Views/ItemBoard*.swift
  - MarfaMac/Views/ItemDigest.swift
  - MarfaMac/Views/ItemRowQuickActions.swift
  - MarfaMac/Views/ItemTimeline*.swift
  - MarfaMac/Views/ItemCalendar*.swift
  - MarfaMac/Views/ItemMap*.swift
  - MarfaMac/Model/Items/MapLayout.swift
  - MarfaMac/Model/Items/DigestLayout.swift
  - MarfaMac/Views/PlaceIndex.swift
  - MarfaMac/Model/Items/IndexRow.swift
  - MarfaMac/Views/ColumnSearch*.swift
  - MarfaMac/Views/ViewPanel*.swift
  - MarfaMac/Views/Selection*.swift
  - MarfaMac/Model/SelectionSummary.swift
---

# Views and lists

A place lists items. Its layout, filters, sort, grouping and properties are its view.

## Two kinds of view

- **The app saves changes to a place's default view immediately** (`PlaceDefaults`). Reset View restores it. Types, Collections and Sources have none.
- **A saved view is an item in Marfa.** Marfa holds its title, query, sort and group. The app holds the rest, such as layout and properties (`ViewMacSettings` in `ViewLayouts`).
- **Saved view writes name the changed settings and use the current row** (`Browser+ViewWrites`).
- **A write that Marfa has not taken stays in the window.** Save View resends it (`hasViewChanges`). Offline, it waits by setting (`PendingViewChanges`), through closing and quitting. A refused one goes to the clipboard in words.
- **Revert View writes back each setting the window changed as it was at opening** (`openedView`), Marfa's whole. One changed elsewhere since stays, and the person is told.
- **While a change waits, the window lists its preview** (`viewPreview`).
- **Undo takes back only its own step.**
- **An entry for a thing that is gone is forgotten only when the copy is whole and current.**
- **New View… saves what Marfa can hold and names the rest first** (`ViewDraft.Unkept`). A type's place saves the type with its kinds; a Type filter takes its place. The window's From and Archived Items become the view's tier and states, and back (`ViewDraft`).
- **A draft from a saved view owns the window,** settings and widths (`ViewPanel.mac`). Revert View is off and a returning write leaves it. Cancel writes nothing and shows the original as it is now.
- **A changed or submitted view draft stays open;** leaving it, or a late refusal, gives it back in words. A rename never replaces another app's; deleting asks.
- **Starting points preview in the window's layout** (`NewViewStart`). Create View applies the draft's layout. This Search comes first, saving supported tokens and unchanged From. An existing view asks before discarding changes.
- **A saved view belongs to one place** (`Place.home(of:catalogue:)`). Its sole type, then its sole required collection (by the outbound edge) or source, else the Feed or the Library by its tier.
- **The Library and the Feed list their own tier.** The Feed's first view is All. A type, a collection and a source choose From (`ListScope`).
- **Favorites starts on Library,** with the usual From choices.
- **Include Kinds defaults on.** A saved view with no state shows archived items (`ArchivedItems`).

## Layouts

- **The Library opens as a table, and as a list while it holds ten items or fewer** (`Browser.naturalLayout`). It and the Archive list Name, Type, Source and Edited, latest first (`listsByOrigin`).
- **The Feed opens in Digest, newest created first.** Any list offers it. Cards show type, source, title, text, and pictures.
- **Digest stacks messages by `in-thread` and excerpts by `excerpt-of`** (`DigestLayout`). Piles span sources, sort by newest visible member, and open from earlier cards.
- **Digest and board lanes draw by page.** Counts and Select All cover all.
- **Several chosen items show a command capsule** (`SelectionCapsule`), a pile beside a list (`SelectionPile`). Escape clears them.
- **⌘⌫ deletes chosen items** on a board, timeline, Digest or map (`ChosenItemDeletion`). Changing the calendar span clears selections outside it.
- **Calendar and Timeline use each type's date** (`ItemPlacement`) or a chosen field.
- **An event's span is one rule** (`EventSpan`); all-day events ignore the Mac's zone.
- **Map needs both coordinate fields and valid values** (`MapLayout`). No Location lists the rest.
- **Board lanes default to status.** Types with different status names use the four status groups.
- **A row stays where seen until the pointer or keys leave** (`RowHold`).
- **A drop in a lane is one edit.** Not Set clears the field; Set and date lanes refuse a drop.
- **Table text aligns with the title** (`TopRowSpace.titleLead`). Widths sample 120 rows (`ItemTableFit`). Name fills spare space until resized. A column keeps the width its words fit, up to its style's widest; the last hide whole if others do not fit (`ItemTableRoom`).

## Sub-items

- **The table and the list nest items under a listed parent** (`ItemNesting`). The table's "1 of 3" counts finished sub-items, from Marfa.
- **A child whose parent is unlisted or in another group stands at the top,** as does a cycle's first item.
- **A chosen sub-item opens its parents;** closing one moves the choice off them. Pages and arrows count drawn rows.
- **A sub-item does not drag.**

## The View panel

- **Digest choices** are Stack Related Items and Pictures (both on), and Lines of Text (three).
- **Quick Actions** are on by default in the Feed, Archive, and saved views whose From is Feed. Table, List, Digest, and Gallery offer Keep, Archive or Unarchive, and Delete where applicable, on hover and through VoiceOver.

## Grouping

- **Group offers come from the listed types** (`GroupOffer`), including fields that no item fills.
- **A grouping has a mode** (`GroupMode`): each value, a date's span, set or not set, or the four status groups.
- **A saved view keeps every grouping offered,** order and hidden groups too. Hide Empty Groups stays on the Mac.
- **A saved view's weeks start on Monday,** as in every app. A place's own follow Settings.
- **Not Applicable is last.** In a saved view, presence grouping treats missing fields as Not Set, and status groups treat unknown words as No Status.
- **A hidden group leaves the layout and not the count.**

## Filters

A filter is a `FilterClause`: a field, a `FilterOp` and values, shown as a chip.

| Part | Where |
| --- | --- |
| Which fields a place offers | `FilterOffer`, `FilterTarget` |
| The operators of a kind of field, in order | `FilterOp.offered(for:)` |
| The View panel's Filter page and a condition's panel | `ViewPanelFilter`, `FilterConditionEditor`, `FilterClausePanel` |
| What a chip says | `FilterWording` |
| Which rows a filter keeps in the window | `FilterMatching` |
| To and from a saved view's query | `ViewDraft` in `ViewDraft+Filters.swift` |

- **Filter changes reach every part above.** Test that local matching and queries keep the same items (`FilterClauseTests`, `ViewDraftTests`).
- **Marfa's filter is one list, joined all by and or all by or.** A mix is refused before it is sent (`search-and-filters/filter-mixed-logic`), except that "is" several words of a closed field is written as "is not" the others.
- **An untouched Type condition stays in the filter,** as does every type in an Any filter, whatever the view's types.
- **A view takes ten conditions.** Each value and each bound of a date counts.
- **Marfa has no relative date or filter group,** so the Filter page offers neither. A default view still reads relative dates it already holds (`FilterOp.isRelative`).
- **Marfa has no "does not include"** for people and tags, and cannot ask about a list of words, so neither is offered.
- **Datetime filters use the Mac's clock and offset.** Date-only filters use UTC (`FilterTarget.isDateOnly`).
- **A condition the window cannot show is a locked row,** kept whenever the view is written.
- **What a view cannot keep is said on the Filter page** before the person saves.
- **An unfinished filter hides nothing** and is dropped when its panel closes.

## Properties

- **One list serves every layout** (`ViewProperties`): columns in a table, chips elsewhere.
- **Until the person changes it, each item shows its type's look**, and Use Layouts goes back to that. The first change makes the list the view's.
- **The date and the second line stay the type's.** Switching off a field they say takes it out.
- **A stored property that a place lacks is kept**, because another place may have it.

## Indexes

- **Library › Types, Collections, and Sources** (`PlaceIndex`) show places, searched by name, with no View button.
- **Types nest kinds under their type.** Made By waits for the package's provenance.
- **Source kind** shows App for `oauth:` codes and Connector for `GET /plugins` sources (`SourceKind`).
- **Above 2,000 items, layouts work off the main actor.** First open shows progress; an update keeps the layout.
- **A row's count is of what the place lists.** A file attached to an item shows on its page, so no list or count but search takes it. The Feed's row has none.

## Search

- **Tokens narrow the query** (`SearchNarrowing`), with unsupported tokens applied locally (`ItemTableContent`). Excess conditions are named and refused.
- **What a search leaves out is said** (`SearchLeaveOuts`), with a way to include it.
- **The list's search is tokens and words** (`ColumnSearch`). Return on an offer (`SearchOffers`) makes a token; a change of place clears it. A Type token narrows within the place's types; in Archive it searches archived items.
- **A search in the list is sorted by relevance until the person sorts it.** The gallery and the table keep their own sorts until relevance is picked (`Browser.ordersByRelevance`).
