# Marfa and the Mac app

Status: Built in v0.0.43. The rule that the app owns how a type looks, one look per type, is agreed and not built; see [Looks](looks.md).

Where it lives: `Catalogue`, `ItemTypeInfo`, `PageHeaderKind`, `LookPreset` and `MarfaMapping`, under `MarfaMac/Model/`.

Marfa holds what a thing is. The app decides how it looks. This page explains where the line sits, so you know which side a change belongs on.

## What Marfa holds

Marfa is the server. The app reads and writes it through the `marfa-swift` package's working copy.

- **Items and types.** An item has a type, properties, a text body and edges. A type has a label, fields, a parent, status words and an icon. A field's name carries down the type chain, so a child type has its parent's fields.
- **Read-only.** `read_only` is per item, not per type or field.
- **Field kinds.** A field has a kind (string, number, date, enum, status, list of entries, and so on) and an optional `format`. There is no kind for a location, a color or a duration.
- **Status groups.** Every status word belongs to one of four fixed groups: not started, in progress, completed or canceled. A type can add words but not groups.
- **Edges.** A link between two items is an edge with a name and a reverse name. A field cannot point at an item.
- **Saved views.** A saved view holds a title, a query, a sort and a group. It holds no layout.
- **Display hints.** A type can name its `title_field`, its `body_field`, `name_from_body` and an icon. These are the only presentation a type carries.
- **Names.** Marfa's core works out an item's name and preview. The app shows them and parses nothing itself.
- **Source names and marks.** A source has a name and a mark, which a person can change.

Marfa stores no color per type, status or option, no per-field icon or order, and no layout.

## What the app owns

- **How each type looks.** One look per type, read by the list row, with the page's pins and property order and gallery cards still their own; see [Looks](looks.md).
- **Layouts.** List, gallery, table, board and timeline, with their columns, cards and rows.
- **Defaults.** Which properties to pin, which to hide, and which look a type starts from.
- **Everything drawn.** Chip colors, mark shapes, symbols and spacing. A tone comes from the type's icon id, and an option's dot color comes from its words, because Marfa holds neither.

The app keeps all of this as its own settings, in one hidden item in the Marfa so every Mac uses them, not in any item's data. [Settings storage](settings-storage.md) says where each setting lives.

## The app names no type

Code never tests for a type by its identifier. A type's label, fields, parent, status words and icon come from the catalogue, so a type that a person or an app creates works with no change to the app.

Three places read a type's ancestry because the page needs a starting point:

- `Catalogue.isTask` treats a child of `core.task` as a task, so a task row can read its due date and priority.
- `PageHeaderKind` walks up the parents to choose a header for the item page.
- `LookPreset.suggested` reads a type's fields, and walks up the parents for the highlight type, to choose a type's starting look.

A type that nobody at WithMarfa defined takes the nearest built-in type above it through the `parent` chain.

## What decides how an item shows

For a list's density, the first of these that has a choice wins:

1. The saved view's own density, or a place's own where it is not a saved view.
2. The Density in Settings.

What a row says comes from the type's look (`TypeLooks`), never from a choice of row. A person chooses a look for a type only by importing one; see [Looks](looks.md).

## Item links

Built, not yet released.

Marfa gives each item a link of the form `marfa://<instance-id>/<item-id>`. The instance ID is the lowercase UUID returned by `GET /`. The item ID is a lowercase UUIDv7. Marfa for Mac routes the link through the last active main window. Settings > General > Open Items controls how items open from the list. If the item is in Recently Deleted, the app tells you.

A link only opens. It never creates, changes, deletes or restores an item, never signs in or changes the connection or a setting, and never reaches the server. The app opens the item only when all of these are true:

- The URL macOS delivers has exactly that form. A query, fragment, port, percent-encoded digit, trailing slash, or uppercase ID makes it invalid.
- The instance id matches the one held by the copy of the connected Marfa. A link to another Marfa opens nothing and says only that it is to another Marfa.
- The copy holds the item. If it doesn't, the app says that the item can't be found in this Mac's copy.

If no Marfa is connected, or its library can't be opened, the app says so and offers Settings. While the library is still opening, as at launch, the link waits for it for a short time; a newer link replaces a waiting one.

Where it lives: `AppDelegate` receives the URL. In `MarfaMac/Model/`, `ItemAppLink` parses it, `ItemLinkRoute` checks it against the working copy, and `ItemLinkOpener` handles the result.

## Related pages

- [Looks](looks.md)
- [Settings storage](settings-storage.md)
- [Glossary](glossary.md)
