---
summary: The rules for making an item, editing its values, changing its type and changing a field from its menu.
paths:
  - MarfaMac/Model/QuickAdd*.swift
  - MarfaMac/Views/QuickAdd*.swift
  - MarfaMac/Views/ValueEditing/*.swift
  - MarfaMac/Model/Items/TypeChange*.swift
  - MarfaMac/Model/Items/ItemWrite*.swift
---

# Making and editing

Every change a person makes to an item is an `ItemWrite` through `ItemLibrary`. `docs/commands.md` says how a command is added, and `MarfaMac/Model/AGENTS.md` how a write is kept.

## Making an item

- **Quick add is the one way to make an item** (`QuickAdd`): every plus, command and any-app shortcut opens the same panel, so a person learns one.
- **The type to start with:** a type's own place starts with that type. Anywhere else starts with the last one used, or a note (`QuickAdd.startingType`).
- **A type gives a new item only its first status that has not started** (`QuickAdd.prefill`), so no item arrives done. A change of kind takes back what the last kind gave and keeps what the person changed.
- **A required field the panel cannot set is named at once** (`QuickAdd.unsettableRequired`), not after the person has typed.
- **What the type gave is not content** (`holdsContent`). A panel that holds only that closes without asking.
- **What the chosen kind cannot keep stays in sight and holds the panel back**: text, more than one file, or a parent that is gone.
- **A refused item keeps the panel and its text.**

## Value panels

- **A value is edited in a panel under itself** (`ValueEditPresenter`, `ValueEditModel`), the same one from a row, a cell, the right sidebar and a chip.
- **A single choice closes the panel when picked; several choices keep it open.** Only a date's panel has a row for Not Set; picking a choice again clears it.
- **A status panel lists the type's words under their four groups.** Edit Statuses… opens the type in Settings.
- **Unsaved text is kept when a panel loses its place**, and the person is told where it is.
- **A panel writes the one property it shows**, on the version it read, so it never writes over another app's change to another property.
- **Change Type, Add Tag and Add to Collection are panels too** (`CommandValuePanels`), never sheets. They act on the whole selection as one undo.
- **What a command cannot change is left alone and counted** (`BatchSkips`), never silently skipped.

## Changing type

- **The title and text move to the new type's own keys in one edit** (`TypeChange`), because Marfa reads them from those keys. Marfa keeps every other value, as an unlisted property where the new type has no such field.
- **A required field the items lack is asked for first** (`TypeValuesSheet`), once for the selection.
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

## Location

- **The person places the pin.** Apple's license (Developer Program License Agreement, Attachment 6, section 2.5) forbids keeping what a map search returned. A search result only moves the map; what is written is the point the person chose (`LocationPanelModel`).
- **One edit and one undo write both numbers** and the name the person typed. Clear Location keeps the name.
- **A name that cannot be written goes to the clipboard**, and the person is told.
