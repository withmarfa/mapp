---
summary: The rules for making an item, changing its type and changing a field from its menu.
paths:
  - MarfaMac/Model/QuickAdd*.swift
  - MarfaMac/Model/NewItem*.swift
  - MarfaMac/Views/QuickAdd*.swift
  - MarfaMac/Views/NewItem*.swift
  - MarfaMac/Model/Items/TypeChange*.swift
  - MarfaMac/Model/Items/ItemWrite*.swift
---

# Making and editing

Every change a person makes to an item is an `ItemWrite` through `ItemLibrary`. `docs/value-panels.md` says how a value is edited in its panel. `docs/commands.md` says how a command is added, and `MarfaMac/Model/AGENTS.md` how a write is kept.

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

- **`Browser.openNewItem` is every New's one way in,** the any-app shortcut and the search's New Item among them. It opens the new-item line, or the text form where New Opens says so (`NewOpens`) or the line cannot make the kind (`QuickAdd.lineOffers`).
- **The kind to start with:** a type's own place starts with that type; anywhere else, New Items Are, then the last kind used, then a note (`QuickAdd.startingType`).
- **One create holds the properties, tags and tier** (`Browser.saveQuickAdd`). The parent is a second write, and a refused parent is told. The In row sets the tier, starting from the place.
- **A type gives a new item only its first status that has not started** (`QuickAdd.prefill`).
- **A required field the form cannot set is named at once** (`QuickAdd.unsettableRequired`). The line hands a draft missing a required value to the text form.
- **The title may be left out** where the kind does not require it and the draft holds something else.

### The line

- **Keys:** Tab moves the kind, `#` a tag, `@` a parent, `/` a property. Before typing, each row offers the most recent (`NewItemRecents`).
- **Add (↩) keeps the line open, empty, with the same kind,** and says "Added “name”" with an Undo of that add alone. ⌘↩ adds and opens; ⇧↩ moves the draft to the text form.
- **A tag is `#` and a letter at a word's start** (`NewItemText.takeTags`), taken when a space or Add ends it. `Issue #12` and a reserved tag stay text.
- **A day becomes the due day, else the start day** (`QuickAdd.dayField`), read in the person's locale: `27/11` in Britain, `11/27` in the United States, `Fri 27 Nov`. Its words leave the title. Removing its token keeps them as text.
- **A web address pasted into an empty line makes a bookmark of it** (`QuickAdd.bookmarkKind`).

### Typed text is never lost

`NewItemDrafts` keeps each new item typed and not added, through a closed window, a quit and a refused write. A slot is `Slot.line` or `Slot.inPlace(_:)`; a library is its `serverKey`.

| Call | Does |
| --- | --- |
| `make(_:_:in:)`, `take(_:in:)` | Start a draft, or claim the latest kept one. Two holders never share one |
| `update(_:_:)`, `escape(_:)` | Keep what was typed, and drop a draft that is empty |
| `added(_:as:)`, `settle(in:)` | Hold the draft until the library holds the item; give back one it refused (`takeReturned(_:in:)`) |
| `release(_:)`, `drop(_:)` | The holder went, or the person cleared it |

A kept file no longer on disk is named when its draft comes back.

## Changing type

- **The title and text move to the new type's own keys in one edit** (`TypeChange`), because Marfa reads them from those keys. Marfa keeps every other value, as an unlisted property where the new type has no such field.
- **The current type is a locked chip in the panel's field,** and the types follow in rows: the sidebar's own in its order, then the rest by name under a line.
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
