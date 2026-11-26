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
  - MarfaMac/Views/WindowFiles.swift
  - MarfaMac/Model/InPlaceRow.swift
  - MarfaMac/Model/Browser+InPlace.swift
  - MarfaMac/Views/InPlaceRowViews.swift
---

# Making and editing

Item changes go through `ItemLibrary` as `ItemWrite` values. See `docs/value-panels.md` for value editing and `MarfaMac/Model/AGENTS.md` for write storage.

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
- **One create holds the properties, tags and tier** (`Browser.saveQuickAdd`). The parent is a second write; a refusal or unanswered loss is told by name (`ParentLinkStore`). The In row sets the tier, starting from the place.
- **A type gives a new item only its first status that has not started** (`QuickAdd.prefill`).
- **A required field the form cannot set is named at once** (`QuickAdd.unsettableRequired`). The line hands a draft missing a required value to the text form.
- **The title may be left out** where the kind does not require it and the draft holds something else.

### In place

- **New puts the caret in a table's last row or a board's first lane** (`Browser.beginInPlace`); so do a lane's plus and a calendar drag. Elsewhere New opens the line.
- **A row holds what its place implies** (`Browser.inPlaceValues`), joining the group under the pointer, or the first.
- **Return adds and starts the next row; leaving adds; Escape keeps only typed text.** Each add is one undo step, standing where typed until the row is left (`RowHold`).

### The line

- **Keys:** Tab moves the kind, `#` a tag, `@` a parent, `/` a property. Rows offer the most recent first.
- **Add (↩) keeps the line open with the same kind,** with an Undo. ⌘↩ adds and opens; ⇧↩ opens the text form.
- **Words stay in the title until Add or ⇧↩ take out what was read** (`QuickAdd.finishLine`); chips show it (`QuickAdd.lineChips`).

### Typed text is never lost

`NewItemDrafts` keeps each unadded new item through a closed window, quit or refusal (kept at once), by slot (`Slot.line`, `Slot.inPlace(_:)`, `InPlaceRow.slot`) and instance (`serverKey`). A sent draft is frozen; edits make a new one. One cut off by a quit returns unless its item is in the copy; its Add asks first (`QuickAdd.mayBeInMarfa`).

| Call | Does |
| --- | --- |
| `make(_:_:in:)`, `take(_:in:)` | Start or claim an unshared draft |
| `update(_:_:)`, `escape(_:)` | Keep what was typed; drop an empty, unsent draft |
| `sending(_:as:)`, `sendingFile(_:)`, `settle(in:)` | Write the ID or mark first, or send nothing; hide it until Marfa answers (`ItemLibrary.refusedCreates`) |
| `giveBack(_:)` | Return a failed file's draft |
| `release(_:)`, `drop(_:)` | The holder left, or the person cleared it |

### Dropping

- **Files dropped on a list join the place in view** (`Browser.fileDropTarget`): a collection, the Feed, else the Library.
- **A collection's row, card or sidebar row takes items and files** (`dropsInto`).
- **A drop is one undo step and one toast;** Undo unlinks, then moves them to Recently Deleted.

## Changing type

- **The title and text move to the new type's own keys in one edit** (`TypeChange`), because Marfa reads them from those keys. Marfa keeps every other value, as an unlisted property where the new type has no such field.
- **The current type is a locked chip in the panel's field,** then rows: the sidebar's first five, then the rest by name under a line.
- **A required field the items lack is asked for first** (`TypeValuesSheet`), once for the selection. It is the one sheet in editing: Change Type, "Task needs these values:", a field for each, then Cancel and Change Type. The title it needs starts as the item's name, for one item.
- **Never offered:** a file's type, a type with no text for an item with text, or one whose field cannot hold the value under its key.

## A field's menu

A right click on a property's name opens a menu with two parts (`FieldMenu`).

- **The app's part is pin, move and hide.** It writes nothing to the item or the type, so a read-only item offers it too.
- **Marfa's part is renaming a field or a choice, adding and removing choices, and removing the field** (`TypeDefinitionEdit`). It needs the server and is never queued: a type's definition has no version.
- **The type is read again just before it is sent**, and the change is refused if the field changed. It narrows the race without closing it.
- **Only a field that the type itself declares, and no type above it does, can change** (`FieldLock`). A type Marfa ships, or one under `common`, changes nothing. A plugin's own root reads as editable until the server refuses.
- **A choice word is never renamed**, only added, moved or removed: items hold the word.
- **A field's key never changes**: items hold values under it. A rename changes its label.
- **A removed choice stays on the items that have it**, and the last choice cannot be removed.
- **Removing a field asks first and keeps the values** on the items, as unlisted properties. The title, text and source-link fields cannot be removed.
