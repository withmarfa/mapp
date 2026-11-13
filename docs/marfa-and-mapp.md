# Marfa and MAPP

Status: Built in v0.0.43. The rule that MAPP owns how a type looks, one look per type, is agreed and not built; see [Looks](looks.md).

Where it lives: `Catalogue`, `ItemTypeInfo`, `PageHeaderKind`, `LookPreset` and `MarfaMapping`, under `MAPP/Model/`.

Marfa holds what a thing is. MAPP decides how it looks. This page explains where the line sits, so you know which side a change belongs on.

## What Marfa holds

Marfa is the server. MAPP reads and writes it through the `marfa-swift` package's working copy.

- **Items and types.** An item has a type, properties, a text body and edges. A type has a label, fields, a parent, status words and an icon. A field's name carries down the type chain, so a child type has its parent's fields.
- **Read-only.** `read_only` is per item, not per type or field.
- **Field kinds.** A field has a kind (string, number, date, enum, status, list of entries, and so on) and an optional `format`. There is no kind for a location, a color or a duration.
- **Status groups.** Every status word belongs to one of four fixed groups: not started, in progress, completed or canceled. A type can add words but not groups.
- **Edges.** A link between two items is an edge with a name and a reverse name. A field cannot point at an item.
- **Saved views.** A saved view holds a title, a query, a sort and a group. It holds no layout.
- **Display hints.** A type can name its `title_field`, its `body_field`, `name_from_body` and an icon. These are the only presentation a type carries.
- **Names.** Marfa's core works out an item's name and preview. MAPP shows them and parses nothing itself.
- **Source names and marks.** A source has a name and a mark, which a person can change.

Marfa stores no color per type, status or option, no per-field icon or order, and no layout.

## What MAPP owns

- **How each type looks.** Today that is a list row style, the page's pins and property order, and gallery cards. The agreed design replaces these with one look per type; see [Looks](looks.md).
- **Layouts.** List, gallery, table, board and timeline, with their columns, cards and rows.
- **Defaults.** Which properties to pin, which to hide, and which row style a type starts from.
- **Everything drawn.** Chip colors, mark shapes, symbols and spacing. A tone comes from the type's icon id, and an option's dot color comes from its words, because Marfa holds neither.

MAPP keeps all of this on the Mac and never writes it to Marfa. [Settings storage](settings-storage.md) says where each setting lives.

## MAPP names no type

Code never tests for a type by its identifier. A type's label, fields, parent, status words and icon come from the catalogue, so a type that a person or an app creates works with no change to MAPP.

Three places read a type's ancestry because the page needs a starting point:

- `Catalogue.isTask` treats a child of `core.task` as a task, so a task row can read its due date and priority.
- `PageHeaderKind` walks up the parents to choose a header for the item page.
- `LookPreset.suggested` reads a type's fields, and walks up the parents for the highlight type, to choose a type's starting look.

A type that nobody at WithMarfa defined takes the nearest built-in type above it through the `parent` chain.

## What decides how an item shows

For a list's row style, the first of these that has a choice wins:

1. The saved view's own row style, or a window's choice in a place that is not a saved view.
2. The style the type's fields suggest (`LookPreset.suggested`, mapped to a row style).
3. The Row Style in Settings.

A person no longer chooses a row style for a type. The agreed design moves the choice from a row style to a type's look, kept per type. See [Looks](looks.md).

## Related pages

- [Looks](looks.md)
- [Settings storage](settings-storage.md)
- [Glossary](glossary.md)
