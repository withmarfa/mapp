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
  - MarfaMac/Model/AlreadyInMarfa.swift
  - MarfaMac/Views/AlreadyInMarfaAlert.swift
  - MarfaMac/Views/WindowFiles.swift
  - MarfaMac/Model/InPlaceRow.swift
  - MarfaMac/Model/Browser+InPlace.swift
  - MarfaMac/Views/InPlaceRowViews.swift
---

# Making and editing

Item changes use `ItemLibrary` and `ItemWrite` (`docs/value-panels.md`, `MarfaMac/Model/AGENTS.md`).

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

- **`Browser.openNewItem` opens each New command.** In a window, **New item opens as** (`NewOpens`) chooses the form. The any-app shortcut uses the line when the type supports it (`QuickAdd.lineOffers`).
- **The kind to start with:** a type's own place starts with that type; anywhere else, New Items Are, then the last kind used, then a note (`QuickAdd.startingType`).
- **One create holds properties, tags and tier** (`Browser.saveQuickAdd`). In starts at the place's tier. The parent is a second write, with refusals or loss reported by name (`ParentLinkStore`).
- **A type gives a new item only its first status that has not started** (`QuickAdd.prefill`).
- **A required field the form cannot set is named at once** (`QuickAdd.unsettableRequired`). The line hands a draft missing a required value to the text form.
- **The title may be left out** where the kind does not require it and the draft holds something else.

### In place

- **New puts the caret in a table's last row or a board's first lane** (`Browser.beginInPlace`); so do a lane's plus and a calendar drag. Elsewhere, and among files, the line opens.
- **A row holds what its place implies** (`Browser.inPlaceValues`), untyped, so alone it adds nothing. It joins the group under the pointer, or the first. A block takes a kind with a time.
- **Return adds and starts the next row; leaving adds; Escape keeps only typed text.** Each add is one undo step, held where typed until the row is left (`RowHold`).

### The line

- **Keys:** Tab moves the kind, `#` a tag, `@` a parent, `/` a property. Rows offer the most recent first.
- **Add (↩) keeps the line open with the same kind,** with an Undo. ⌘↩ adds and opens; ⇧↩ opens the text form.
- **Words stay in the title until Add or ⇧↩ take out what was read** (`QuickAdd.finishLine`); chips show it (`QuickAdd.lineChips`).
- **Delete on a chip stops it being read** (`QuickAdd.Draft.decline`).
- **A tag is `#` and a letter at a word's start** (`NewItemText.tags`); reserved tags are never read.
- **A date in the person's locale sets the due day,** or the start day (`QuickAdd.dayField`).
- **A kind change keeps the title and sets aside values it cannot hold** (`QuickAdd.tellSetAside`).

### Typed text is never lost

`NewItemDrafts` keeps drafts by slot and instance through a window close, quit or refusal. Editing a submitted draft starts another. An interrupted draft returns if its item is absent. Cancel keeps the Add Again warning (`mayBeInMarfa`).

### Dropping

- **Files dropped on a list join the place in view** (`Browser.fileDropTarget`): a collection, the Feed, else the Library.
- **A collection's row, card or sidebar row takes items and files** (`dropsInto`).
- **A drop is one undo step and one toast;** Undo unlinks, then moves them to Recently Deleted.
- **One duplicate alert covers the batch, including pasted images.** Open shows the matches and adds each file whose match cannot be opened. In Quick Add, a file added while Open fetches stays in the draft. No answer still adds. A pasted image stays with the item that was open.

## Changing type

- **The title and text move to the new type's own keys in one edit** (`TypeChange`), because Marfa reads them from those keys. Marfa keeps every other value, as an unlisted property where the new type has no such field.
- **The current type is a locked chip in the panel's field,** then rows: the sidebar's first five, then the rest by name under a line.
- **A required field the items lack is asked for first** (`TypeValuesSheet`), once for the selection. It is the one sheet in editing. The title it needs starts as the item's name, for one item.
- **Never offered:** a file's type, a type with no text for an item with text, or one whose field cannot hold the value under its key.

## A field's menu

A right click on a property's name opens a menu with two parts (`FieldMenu`).

- **The app's part is pin, move and hide.** It writes nothing to the item or the type, so a read-only item offers it too.
- **Marfa's part is renaming a field or a choice, adding and removing choices, and removing the field** (`TypeDefinitionEdit`). It needs the server and is never queued: a type's definition has no version.
- **The type is read again just before it is sent**, and the change is refused if the field changed.
- **Only a field that the type itself declares, and no type above it does, can change** (`FieldLock`). A type Marfa ships, or one under `common`, changes nothing. A plugin's own root reads as editable until the server refuses.
- **A choice word is never renamed**, only added, moved or removed: items hold the word.
- **A field's key never changes**: items hold values under it. A rename changes its label.
- **A removed choice stays on the items that have it**, and the last choice cannot be removed.
- **Removing a field asks first and keeps the values** on the items, as unlisted properties. The title, text and source-link fields cannot be removed.
