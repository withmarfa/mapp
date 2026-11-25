---
summary: The rules for making an item, changing its type and changing a field from its menu.
paths:
  - MarfaMac/Model/QuickAdd*.swift
  - MarfaMac/Model/NewItem*.swift
  - MarfaMac/Views/QuickAdd*.swift
  - MarfaMac/Views/NewItem*.swift
  - MarfaMac/Model/Items/TypeChange*.swift
  - MarfaMac/Model/Items/ItemWrite*.swift
  - MarfaMac/Model/FileImport.swift
  - MarfaMac/Model/FileDropTarget.swift
  - MarfaMac/Model/Browser+Drops.swift
  - MarfaMac/Views/WindowFiles.swift
---

# Making and editing

Every change a person makes to an item is an `ItemWrite` through `ItemLibrary`. `docs/value-panels.md` says how a value is edited in its panel. `MarfaMac/Model/AGENTS.md` says how a write is kept.

## What an item allows

Every editor asks `Item.allows(_:)` for the `ItemChange` it writes (`ValueEditKind.change`), so a value is locked by one rule. `docs/model.md` says why.

| The item is | Locked |
| --- | --- |
| Read only | Title, text, fields and type |
| A file | Text and type, and the facts the server reads from the bytes (`MarfaMapping.fileFacts`) |
| Unreadable in part (`problem`) | Title, fields, type and tier, and the text where it could not be read |
| Archived | Nothing |
| In Recently Deleted | Everything |

## Making an item

- **`Browser.openNewItem` opens each New command.** In a window, New Opens (`NewOpens`) chooses the line or the text form. The any-app shortcut requests the line. A kind that the line cannot make opens in the text form (`QuickAdd.lineOffers`).
- **The kind to start with:** a type's own place starts with that type; anywhere else, New Items Are, then the last kind used, then a note (`QuickAdd.startingType`).
- **One create holds the properties, tags and tier** (`Browser.saveQuickAdd`). The parent is a second write, and a refused parent is told. The In row sets the tier, starting from the place.
- **A type gives a new item only its first status that has not started** (`QuickAdd.prefill`).
- **A required field the form cannot set is named at once** (`QuickAdd.unsettableRequired`). The line hands a draft missing a required value to the text form.
- **The title may be left out** where the kind does not require it and the draft holds something else.

### The line

- **Keys:** Tab moves the kind, `#` a tag, `@` a parent, `/` a property. Rows offer the most recent first.
- **Add (↩) keeps the line open with the same kind,** with an Undo. ⌘↩ adds and opens; ⇧↩ opens the text form.
- **Words stay in the title until Add or ⇧↩,** which take out what was read (`QuickAdd.finishLine`). Chips show what is read (`QuickAdd.lineChips`); the board draws words leaving.
- **Delete on a chip stops it being read** (`QuickAdd.Draft.decline`). An offer chosen for a typed word keeps the word (`QuickAdd.Mark`).
- **A tag is `#` and a letter at a word's start** (`NewItemText.tags`). Favorite, reserved tags and `Issue #12` are never read; Return alone never swaps them for another tag.
- **A day becomes the due day, else the start day** (`QuickAdd.dayField`), in the person's locale: `27/11` or `Fri 27 Nov` in Britain.
- **A web address pasted into an empty line makes a bookmark** (`QuickAdd.bookmarkKind`).
- **A kind change keeps the title and sets aside values it cannot hold** (`QuickAdd.tellSetAside`).

### Typed text is never lost

`NewItemDrafts` keeps each new item not added through a closed window, a quit and a refusal. A slot is `Slot.line` or `Slot.inPlace(_:)`; a library is its instance (`serverKey`). New Item waits for it (`QuickAdd.isAvailable`).

| Call | Does |
| --- | --- |
| `make(_:_:in:)`, `take(_:in:)` | Start or claim a draft, never shared |
| `update(_:_:)`, `escape(_:)` | Keep what was typed; drop an empty draft |
| `sending(_:as:)`, `settle(in:)` | Write the item's ID first, or make nothing. Hide the draft until Marfa accepts or refuses it (`ItemLibrary.refusedCreates`), even after its row shows |
| `release(_:)`, `drop(_:)` | The holder went, or the person cleared it |

## Dropping on a place

- **Files dropped on a list join the place in view** (`Browser.fileDropTarget`). A collection makes them members, the Feed keeps them in the Feed, and any other place adds them to the Library, as the pill says.
- **A gray ring runs round a list while files are held over it** (`takesDroppedFiles`), with a pill, "Add 3 Files to Glaze tests", counting them; folders alone show none. The sidebar takes none, and an item dragged from the app is never imported again.
- **Where files go is fixed at the drop,** so a place that changes meanwhile does not move them.
- **A folder is refused and told,** never opened. A file named twice is added once, and one the server refuses is told.
- **A drop is one undo step and one toast** ("Added 3 Files", "Added 2 of 3 Files"). Undo takes the items out of the collection, then moves them to Recently Deleted.
- **The toast waits for the library to hold the items.** Where it does not in time, the toast has no Undo and the person is told; one that did not join is counted ("Added 3 Files, 1 not in Glaze tests").
- **A collection's row, card or sidebar row takes items and files** (`dropsInto`). Items already in it get no second edge, and the toast counts them. Nothing else in the sidebar takes a drop, and sub-items do not drag. Add to Collection… needs no drag.

## Changing type

- **The title and text move to the new type's own keys in one edit** (`TypeChange`), because Marfa reads them from those keys. Marfa keeps every other value, as an unlisted property where the new type has no such field.
- **The current type is a locked chip in the panel's field,** and the types follow in rows: the sidebar's first five in its order, then the rest by name under a line.
- **A required field the items lack is asked for first** (`TypeValuesSheet`), once for the selection. It is the one sheet in editing: Change Type, "Task needs these values:", a field for each, then Cancel and Change Type. The title it needs starts as the item's name, for one item.
- **Some changes are never offered:** a file's type, a type with no text for an item that has some, and a type whose field cannot hold the value under its key.

## A field's menu

A right click on a property's name opens a menu with two parts (`FieldMenu`).

- **The app's part is pin, move and hide.** It writes nothing to the item or the type, so a read-only item offers it too.
- **Marfa's part is renaming a field or a choice, adding and removing choices, and removing the field** (`TypeDefinitionEdit`). It needs the server and is never queued, because a type's definition has no version to queue against.
- **The type is read again just before it is sent**, and the change is refused if the field is no longer as it was shown. That narrows the race and does not close it.
- **Only a field that the type itself declares, and no type above it does, can change** (`FieldLock`). A type Marfa ships, or one under `common`, changes nothing. A plugin's own root reads as editable until the server refuses.
- **A choice word is never renamed**, only added, moved or removed, because items hold the word itself.
- **A field's key never changes**, because items hold values under it. A rename changes its label.
- **A removed choice stays on the items that have it**, and the last choice cannot be removed.
- **Removing a field asks first and keeps the values** on the items, as unlisted properties. The title, text and source-link fields can be renamed and not removed.
