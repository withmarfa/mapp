---
summary: Which side owns each thing, Marfa or the app, and the word this app uses for it.
paths:
  - MarfaMac/Model/Items/Catalogue.swift
  - MarfaMac/Model/Items/Item.swift
  - MarfaMac/Model/Items/ItemAllows.swift
  - MarfaMac/Model/Items/ItemMoves.swift
  - MarfaMac/Model/SidebarItem.swift
  - MarfaMac/Model/Marfa/MarfaMapping*.swift
---

# What is Marfa's and what is the app's

Read this before you name, store or show a thing. `docs/concepts.md` says what each thing is for.

## What Marfa holds

- **Types, fields and edge types come from the catalogue** (`Catalogue`), so a type that a person or a plugin makes works with no change to the app. A field reaches child types.
- **Read-only is set per item** (`read_only`), not per type or field.
- **A field has a kind and an optional format.** There is no kind for a location, a color or a duration, so those are composed or worded by the app.
- **Status words belong to one of four fixed groups.** A type adds words and never a group.
- **A link between items is an edge**, with a name for each end, which the app shows as worded. A field cannot hold an item.
- **The only presentation a type carries** is its `title_field`, `body_field`, `name_from_body` and icon.
- **Names and previews are worked out by Marfa's core.** The app shows them and parses no item for one.
- **Marfa has no color, no icon or order for a field, and no layout.**

## What the app owns

- **Everything drawn**: marks' colors, chips, symbols, spacing, layouts, and which properties a page or row shows. All of it syncs as this app's settings and touches no item. `docs/settings-sync.md` says where each setting is kept.
- **Its own choices are defaults until a person changes one**, and only the change is stored, so a better default reaches everyone else.
- **An option's color comes from its words, and a mark's from its icon** (`OptionTone`, `TypeTone`), because Marfa holds neither and two Macs must agree without a setting.

## Where the app looks at what a type descends from

Each is a case where a declared field is not enough. Add to this list only where the fields cannot tell.

- `Catalogue.isTask`: a task's row reads its due date and priority.
- `Catalogue.isStartDate`: which date of a task or an event is its start.
- `Catalogue.isFileType`: what has a file behind it.
- `PageHeaderKind`: the nearest ancestor with a header of its own.
- `LookPreset.suggested`: the highlight type, found by walking up.

Two defaults name types: the sidebar's and toolbar's starting set for New, and the type quick add begins with. Both use only types the library offers.

## Tier, state and what an item allows

- **One rule says what an item allows:** `Item.obstacle(to:)`, for each `ItemChange`. Its answer is the `BatchSkips.Reason` a command on several tells.
- **Read only locks the connector-managed title, text, properties, and type.** A natural-key upsert keeps the current tags and tier when the connector omits them (`items/natural-key-tags`, `items/tier-upsert`). A binned item stays in the bin (`items/natural-key-trashed`).
- **Archived blocks nothing.** In Recently Deleted, everything is blocked but Recover and Delete Immediately.
- **The tier and the state are separate.** Keep and Move to Feed send `ItemWrite.retier`. Archive, Unarchive, and Delete send `ItemWrite.transition` through `setStates`. Recover and undo or redo steps that take an item out of Recently Deleted use `ItemWrite.restore`. Each item is its own queued write, and a command is one undo step.
- **`MarfaEngine.judge` checks every state and tier write,** Undo and Redo included, against the copy with its queued writes and its bin. Queue-time skips are told in one notice (`gatheringSkips`).
- **A move command's `CommandOutcome` counts what the copy queued,** given to `moved` once each write is judged.
- **Undo records a state move once its write is judged, and a tier move once the server answers.** Before that, Undo goes back on its stack and Redo says why it did not run (`waitForEarlier`).
- **Known gaps:** a queued write can overwrite a change the copy has not yet learned of (withmarfa/marfa#3523, withmarfa/marfa#3528), including one the copy applies between `judge` and the queue, two package calls.
- **Also open:** two notices when planner and queue skips coincide; one notice per failed rearchive in a bulk Undo of Delete; Delete's toast counts what it planned; Undo of New Item before the item shows.
- **Archive with what is beneath takes every active item under the selection through `parent-of`** (`archivePlan`). Marfa's own archive reaches no child.

## Vocabulary

Use these words in names, strings and comments. A word with "Marfa" is the server's and is used as the server uses it.

| Word | Whose | What it means |
| --- | --- | --- |
| Item | Marfa | One record: a type, properties, text and edges. Say "note" only for a note |
| Type | Marfa | What an item is, with fields, a parent, status words and an icon |
| Catalogue | Marfa | The list of types, fields and edge types (`Catalogue`) |
| Property | Both | A value an item holds. The field or edge is Marfa's; the row is the app's (`PropertyRow`) |
| Composed property | App | One value made of several: Location, Relation, Count |
| Edge | Marfa | A typed link from one item to another |
| Status group | Marfa | One of four that every status word belongs to (`StatusGroup`) |
| Collection | Marfa | An item of a type with the `container` role; `in-collection` edges are its members |
| Source | Marfa | What wrote an item. Its name and mark are Marfa's |
| Saved view | Both | A `system.view` item: title, query, sort and group. The app adds the rest (`ViewMacSettings`) |
| Item link | Marfa | An item's `marfa://` or `https` address (`ItemAppLink`) |
| Place | App | What a sidebar row opens (`SidebarItem`) |
| Layout | App | How a list is drawn (`ItemViewMode`) |
| Look | App | How one type is drawn in every list (`TypeLook`) |
| Preset | App | The look a type starts from (`LookPreset`) |
| Density | App | How much room a row takes (`Density`) |
| Properties list | App | The fields a view shows after the title (`ViewProperties`) |
| Pin | App | A property under an item's title (`PagePins`) |
| Property block | App | The rows under the pins |
| Right sidebar | App | The panel beside a page that lists everything (`ItemInspector`) |
| Corner | App | The controls at a page's or list's lower right (`WindowCorner`) |
| Section, tab | App | A heading over sidebar rows, and a set of sections (`SidebarGroup`, `SidebarTab`) |
| Shortcut | App | A sidebar row that acts and is never selected (`SidebarShortcut`), or a key (`ShortcutCommand`). Say which |
| Chip | App | A word from a set, drawn small (`PageChip`) |
| Type mark, tone | App | A type's icon in its color (`TonedGlyph`, `TypeTile`, `TypeTone`) |
| Toast | App | The short message with Undo (`ToastView`) |
| Keycap | App | A key drawn by the app (`KeyCap`) |
| Settings window | App | The window that holds the app's settings and the Marfa's (`SettingsWindowView`) |

## Storage

- **On this Mac** means a value that never leaves it. `PreferencesMap.staysOnMac` is the whole list, and a test fails if a key is in neither list.
- **Trap:** "the app keeps it" does not mean "this Mac keeps it". Widths of columns, the last place open and per-Marfa export plans stay; nearly everything else a person sets follows them.
