---
summary: What each thing is in Marfa and in the app, and what the app holds to when it uses it.
paths:
  - MarfaMac/Model/**/*.swift
  - MarfaMac/Views/**/*.swift
---

# Concepts

This is the model the app is being built to. The parts of it that are not on `main` are listed in `docs/agreed.md`; the other pages describe `main`. Where this page and the code differ and `docs/agreed.md` has no row for it, the difference is a fault.

## The short version

An **item** is one thing a person keeps. Six questions can be asked of any item, and each has one answer:

| Question | Answer | Who sets it |
| --- | --- | --- |
| What is it? | Its **type** | Chosen when it is made, and can be changed |
| What is known about it? | Its **properties** | The type defines them |
| What loose words describe it? | Its **tags** | Anyone, on any item |
| What does it belong with? | Its **collections**, and its **links** to other items | The person |
| How close is it kept? | **Library** or **Feed** | The person, or whatever wrote it |
| Is the person done with it? | **Active**, **archived** or **deleted** | The person |

A **view** sits over all six: a saved list that answers "show the items where…".

- **None of the six is a folder.** An item is never inside a type, a collection or the Library as a file is inside a folder. Each is a value the item has, and a list is the answer to a question about values.
- **The six are independent.** Changing one answer never changes another. Archiving an item leaves it in the Feed; keeping it leaves it archived.

## The Marfa

The server one person owns, and the source of every item the app shows.

- The app works over a **copy** of the Marfa on the Mac, so reading and editing need no connection. Work done without one waits in a queue and is sent in order.
- What only the server can do (a type's definition, a view made or renamed, a permanent removal, the owner's settings) needs a connection, is never queued, and says so where it cannot run.
- Marfa decides what things are. The app decides how they look. Where both could decide, Marfa does, so that another app agrees.

## Item

**In Marfa:** the one unit of storage. It has an id, a type, properties, tags, a tier, a state, a source, a version, and edges to other items.

**In the app:** a row, a card, an entry, a pin on a map or a block on a calendar, and a page when opened. It looks different by layout, never by the place it was opened from.

- **One command, everywhere.** Keep, Move to Feed, Archive, Delete, Favorite, Add Tag, Add to Collection and Change Type are the same command in a row's menu, a page's More menu, the menu bar, the palette and the capsule for several items.
- **What a person may change does not depend on who keeps the item.** Library, Feed, Archive, Delete, Favorite, tags, collections and links work on an item its connector keeps and on an archived item.
- **On a read-only item the title, text and fields are locked**, and the page gives the reason. Read-only is Marfa's advice to apps, not a wall.

## Type

**In Marfa:** every item has exactly one type: one of Marfa's own, one a plugin brings, or one the person made. It defines the properties its items have, and may have a parent whose properties it takes. It gives them no order and no color. It may limit how long its items stay in the Feed; none does unless someone sets it.

**In the app:** a place, which lists its items and has views. A type's child types are its **kinds**. Its **mark** is a small symbol, whose icon Marfa holds and whose color the app picks.

- **The app names no type.** It asks what a type declares, so a type that a plugin brings is first class.
- **A type shown as a fact about an item is its mark and its name**, never a chip.
- **A type has one count**, of all its items, in the sidebar and in Library › Types.
- **A type opens on All Items**, quietly. A setting says what types open on: All Items or Library. No rule of the app's picks one.
- **Changing type edits one value.** It is not a move, and the item keeps its id, its links and its history.

## Property

**In Marfa:** a named value that the type defines: text, a number, a date, a choice, a yes or no, a list. A status is a choice whose words belong to one of four groups. An edge field names other items.

**In the app:** a row on a page, a column in a table, a line on a card.

- **One look for each kind of value.** A word from a set is a chip, an item is its mark and name, and anything else is text.
- **A row shows when its property has a value**, and the person can say always or never for a type.
- **Every edge field that an item's type may hold is a row**, edited in the same panel as any value.
- **A file's title, and every field Marfa lets a person change, is editable.**

## Tag

**In Marfa:** a free word on any item of any type. Nothing is set up first. It is not a property, and changing tags makes no new version. A favorite is the tag `favorite`.

**In the app:** a gray chip after a number sign. A click lists everything that carries it, across types.

- **A tag is the one thing that cuts across types with no setup.** Never turn tags into a property of each type, or ask a person to make a tag before using it.
- **Favorite is a star**, and the tag behind it is never shown as a tag.

## Collection

**In Marfa:** an item of a type with the container role. A member is an edge to it with a position, so it has an order. An item can be in many collections; a collection is never in another.

**In the app:** a place that lists its members and has views.

- **A collection is chosen and ordered by hand; a view is worked out by a rule.** A collection's page has a description and its own menu; a view has neither.
- **Adding to a collection takes the item out of nothing.**
- **Deleting a collection says that its items stay.**

## Links

**In Marfa:** an edge of a type from one item to another, with a label for each end. A link written in text is an edge too.

**In the app:** links in text and as rows, and everything that points at an item, gathered beside its page.

- **Links in text, rows, panels and cards follow the opening preference** (General’s Open items in setting or the place’s Open Items choice).
- **A link to an item is its mark and its current name.** A link that cannot be resolved stays as it was written.
- **Opening a link never changes anything.**

## Library and Feed

**In Marfa:** every item has a tier, `library` or `feed`. The library is what a person chose to keep; the feed is what arrives in volume. The tiers behave differently in one way: a type may limit how long its items stay in the feed. Moving between them is an ordinary edit, either way.

**In the app:** Library and Feed, and no other words. The Library is what a person works with. The Feed is what flows in and stays within reach: newsletters, an agent's logs, records that a connector syncs.

- **It is a value on the item, like a property**, so the page shows and changes it and the item's menu has Keep in Library and Move to Feed.
- **The Feed is never a pile to clear**: no count on its row, no badge, no read mark, nothing about waiting, no reward for emptying it. Marfa has no seen mark, so the app shows none.
- **A list never mixes Feed items in unmarked.** In a list of all items, each item in the Feed has the Feed's mark.
- **A list never leaves Feed items out without a visible way to see them.**
- **A count says what it counts.** The Library's row counts the Library. A count beside a title is of what the control after it names.
- **Info says when an item leaves the Feed** only where its type sets a window, the item is active in the Feed and its creation is known: its creation plus the window's days of 24 hours.
- **Move to Feed and Unarchive ask first** only where that moment has passed for the item they would make an active Feed item, since Marfa would bin it within the hour. An archived item stays archived, and so does one whose type is unknown or keeps its feed items.
- **A date to leave the Feed is when the item is due, not a promise.** Marfa holds an item while something it would take with it is not yet due, and Info shows no date once it has passed.

## Archive and Recently Deleted

**In Marfa:** an item's state is active, archived or trashed, whatever its tier. An archived item stays readable, editable, linkable and searchable when asked for, and is left out of a list that names no state. Archiving does not reach an item's children. Deleting does, and the bin is emptied after the Marfa's limit.

**In the app:** a state, not a place.

- **Archive means "done with it, and keeping it"; Delete means "not wanted".** Never blur them, and never use Archive as a second Feed.
- **Any view can show archived items**, or only those. Library › Archive is the one page of everything archived.
- **An archived page says so and can still be edited.**
- **Archiving an item with sub-items asks**, and counts everything beneath it, because Marfa leaves the sub-items where they are.
- **Open Trash in Settings** to see recently deleted items.

## Source

**In Marfa:** what wrote the item: an app, a connector or a key. It never changes. A connector names the types it does not carry back to its service, and Marfa answers those items as read-only.

**In the app:** a quiet fact in an item's details, a filter, and a page under the Library.

- **A source is where an item came from, not where it is.** Never use it in place of Library or Feed.
- **The panel says once who else keeps an item**: read only, synced with a service, or nothing.

## View

**In Marfa:** a saved list, which is itself an item, so every app shows it. It stores a title, what it lists (types, tier, state, a filter, and optionally everything beneath one item), a sort and a group. It stores no layout.

**In the app:** a pill in the row of views on the page of the place it lists. A view can also be pinned; opening it opens that place with the view chosen.

- **A view is a question, not a container.** Nothing is in a view.
- **A view says which it lists**: all items, the Library or the Feed. A new one lists all items unless it says otherwise.
- **A place's own first view is kept in the app's settings**, and the foot of the View panel says so. Only a saved view says it is saved in Marfa.
- **A change to a saved view is written to Marfa as it is made.** Its pill has a dot while it differs from how it was when last opened on that Mac, and Revert View puts that back.
- **Changing a view never makes another one quietly.** Making one is a short setup of its own, not a form of filters.
- **What Marfa cannot save is not offered in a view.** Filter groups, and dates relative to the current day, wait for it.
- **Quick Actions puts actions such as Keep, Archive and Delete on the row under the pointer.** It is on by default in the Archive, the Feed and saved views whose From is Feed.
- **An inbox is a view a person makes.** The app ships none, and the word never names the Feed.

## Layout

**In Marfa:** nothing. **In the app:** eight ways to draw one list: List, Table, Board, Gallery, Calendar, Timeline, Digest and Map.

- **A layout draws the list it is given.** It never changes which items are shown.
- **A layout that needs a kind of value is offered only where the items have one**: a date, a status, a location.
- **A layout never writes an item by being looked at.** Dragging an item in one is an edit, with one undo.

## Places and the sidebar

A place is a page that lists: the Library, the Feed, a type, a collection, a source, the archive, and the pages of types, collections and sources that the Library holds.

- **The Library is the whole of what is kept**, and its page leads to Types, Collections, Sources and Archive. They are indexes: rows of places, not of items.
- **The sidebar is a set of shortcuts**, not a tree of folders: Search and New, Library and Feed, what the person pinned, types, and sections the person made.
- **A row looks like what it is**: a place, a view or an item. Unpinning deletes nothing.
- **Recents, Favorites, Inbox and Files are not places.** Recents is the Library sorted by when it was edited, and Favorites is a view.

## Page

An item opened, with its title, its rows, its text and a panel beside it.

- **One page serves every type.** A type decides which rows show and what leads, so no page is built for a type.
- **What a kind of item is made of comes first.** A highlight's text is the passage, and its note is a property. A message has no title field, so its text leads.
- **The rows hold every property**, so nothing lives only in a panel.
- **One notice at a time** stands on a page, for what the person should know before editing.

## Search

- **Search finds across the whole Marfa from anywhere**, or narrows the place it is opened on. It says which.
- **What search is narrowed by is a token in its field**, so a search reads as what it asks.
- **A search is not a view until the person makes one** with the plus, which starts from the search.
- **What search leaves out is said**, with a way to include it.

## Making an item

- **An item is made where it will live.** A new item takes the type, collection, status or date of the place it was made in, and says so before it is made.
- **A new item is in the Library** unless it is made in the Feed or the person says otherwise.
- **Nothing typed is lost.** A refused item keeps its panel and its text.

## What is saved where

| Saved in Marfa, for every app | Kept by the app, for every Mac of the person's |
| --- | --- |
| An item's type, properties, tags, links, tier and state | A mark's color, and the order of a type's properties |
| A collection and its members' order | A view's layout, columns, card properties and Quick Actions |
| A view's title, what it lists, its sort and its group | A place's own first view |
| A type's limit in the Feed | What is pinned, and the sidebar's sections and look |
| A source's name and mark | The app's settings |

A table item's own order of rows is kept by the app until Marfa can hold one.
