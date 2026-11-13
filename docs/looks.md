# Looks

Status: The model, the store, Export and Import and the list row are built, not yet released. Cards and tables do not read a look yet: a gallery card, a board card and a table cell each draw status, priority, people and type in their own way.

Where it lives: `TypeLook`, `LookPreset`, `TypeLookResolver`, `TypeLooks` and `LooksFile` under `MAPP/Model/Looks/`, `LooksCommands` under `MAPP/Views/`, the row's content (`RowContent`, `RowContents`) under `MAPP/Model/Items/`, `Density` under `MAPP/Model/`, `ItemRow` and `NoteList` under `MAPP/Views/`, and, until cards read a look, `ViewCards` under `MAPP/Model/` with `GalleryCard` and `ItemBoard` under `MAPP/Views/`.

A look says how one type is drawn. Every view of that type, whether a list, a gallery, a board, a table or the page, reads the same look, so one item never changes character between views.

## The model

- Marfa holds what a thing is. MAPP holds how each type looks. See [Marfa and MAPP](marfa-and-mapp.md).
- A type has one look. Every view uses it.
- A type starts from a preset chosen from its fields. See [Presets and densities](presets-and-densities.md).
- A child type takes its parent's look, place by place, along Marfa's `parent` chain, at most ten types up. It does so only through types whose fields suggest the same preset: a place under an entity gets Place, not the entity's Person, and a repository under an entity gets Note. A parent the server lacks ends the walk.
- Until Settings lets a person edit a look, the presets are the looks, and Import Looks is the only way to choose one.
- A view adds little: its layout, its density, and which date, picture and facts it shows. Everything else comes from the type.
- Looks are kept on this Mac for each server, with an export (`TypeLooks`). The store holds only what was chosen, place by place; every other look is worked out each time, so a better preset improves every look nobody chose. A density is not part of a look: a saved view keeps its own and a place keeps its own on this Mac. See [Settings storage](settings-storage.md).
- `TypeLooks.looks(in:library:)` is the one way to resolve looks: it works out every type's look once. A caller holds the result for a catalogue revision and a set of choices, and never resolves in a row's body. A type the catalogue lacks has no entry.
- A look is never written to Marfa.

## What a look holds

A `TypeLook` has three places, and a view adds only its layout and density.

- **Date.** A date field of the type, when the item was created, when it was last edited, when it happened, or none. An item with no value in the field shows when it was last edited. When it happened is Marfa's own `occurred_at`, which every item has and no type declares as a field; an item with none shows when it was created. MAPP's `Item` holds it as `occurred`.
- **Secondary.** Up to two parts joined with ", ": a field, a date field's time of day, the item's opening line, the website of its `url`, or a file's kind and size. A time of day is offered only for a date field that includes a time, and an all-day value shows nothing for that part, so an event's Date shows the day and its Secondary "7:30 pm, Brat, Shoreditch".
- **Facts.** The fields and tags shown after the status, in order; a view shows as many as fit. Later kinds MAPP builds (a count, a reading time, a relation) are new cases.

A type with a status field always shows its status first, so a status is never a fact. A place the type has no field for stays empty: a look never names a field its type lacks, and a chosen date field the type lacks is replaced by the preset's date, while a chosen part or fact it lacks is left out.

## Export and import

File > Export Looks writes every look of the connected server's types as one JSON file, and File > Import Looks reads one; both are also in the command palette. The file names its format (`mapp-looks`) and version and no server, and holds a look for each type the server has, each place by its word: `field:due_at`, `time:starts_at`, `opening`, `site`, `file`, `tags`, `created`, `edited`, `occurred` or `none`.

- An export writes every look as this Mac resolves it. An import stores, for each type and place, only a value that differs from what this Mac would work out for the place without a choice (the preset, and what the types above it chose), and clears the place's choice where the file's value is the same. Importing your own export therefore changes nothing, a file with one changed place stores that place alone, and a later better preset still reaches every place nobody chose. A child is measured against its parent's choices as the import leaves them, so after an import every type shows the look the file holds. A child listed with its parent's old value keeps that value as its own choice.
- A type the server lacks has nothing to measure against: its whole look is kept and waits for the type. An export holds it too, so a round trip loses nothing.
- A file that cannot be read, is not a looks file, is another version or holds a word this version does not know is refused whole with a notice, and nothing is written.
- Looks chosen for other types are left as they were.

## The places of a row

A look fills a fixed set of places. A place with nothing to show is left out and leaves no gap.

- **Title.** The item's name, as Marfa has it. No gray key or number comes before it, because a number is a property.
- **Date.** Top right, on every row that has one. It is the date the list is sorted by, otherwise the type's own date: due, published, taken or updated. Inside a day's group it is the time.
- **Secondary.** One line under the title that the look chooses, such as a repository, a website, an address or a highlight's passage.
- **Bottom line.** The type's chip, only when the list mixes types. Then the status, then up to two facts, then "+N" for the rest. These are the page's own chips at row size: 20 points high with 11.5-point text. A person is initials only, in the pale circle. Tags do not show in a row, except in a Note's: the Note preset names `tags` as its fact, shown at row size.

Nothing indents a row. No status circle or highlight bar sits at the leading edge.

A row never shows the tier. Inbox is a view of the feed tier, not a fact about a row. A row's preview starts from the item's text, not from its first heading. Marfa's core works out the preview and MAPP shows it; the preview rule is agreed, not built.

## One look in every view

- **List.** The row above.
- **Gallery card.** The picture, or the item's opening lines when it has none, so a title never shows twice. Then the title on up to two lines, then the Secondary line.
- **Board card.** The title, the Secondary line and the bottom line, without the field the board is grouped by.
- **Table.** The title column, then the look's facts as columns, drawn with the same chips. See [Value components](value-components.md).

## How a row is made

A list row is one view for every type (`ItemRow`), drawn in one of two densities (`Density`). It holds no logic of its own: it draws a `RowContent`, which is plain values worked out from an item, the look of its type and the list.

- **Looks.** `NoteList` resolves the looks once for a catalogue revision and the person's choices, and never in a row's body (`RowContents`).
- **Content.** `RowContent.make` works out the title, the date, the Secondary line and the bottom line for one item. `RowContents` holds the result for each item value, so a change of selection, or of one item, works out one row at most and a row's body looks nothing up. The content is dropped when the catalogue, the choices, the list or the day changes.
- **The list tells each row what it shares** (`RowList`): whether the list holds several types, which date it is sorted by, and the day. A list sorted by a date, whether by a column or by the global order, shows that date in every row; a list sorted by title, by relevance or by its own order shows each type's look date. An item with no value in the sorted date field shows no date.
- **Inside a day's group** (Today and Yesterday) the date is the time of day; elsewhere it is the list's label for the date, so a day to come reads as a day and not a time.
- **A look's date that names a date field** falls back to when the item was last edited where the item has no value. A list sorted by a date field does not fall back, since a row with no date there has nothing to say about the order.
- **Facts.** A fact that has no value for an item is skipped. A person shows as initials in the pale circle, the first of several with the rest counted in "+N"; a choice or a priority shows as an option chip; a text, number or date shows as plain secondary text led by its field's label ("Location 1712", "Due 14 Nov"); a yes-or-no shows its label alone when it is yes, and nothing when it is no; a Note's tags show as tag chips, up to three. Up to two facts show, and every value left out is counted in "+N", whether the fact that left it out shows or not.
- **The item's text.** A Secondary part or a fact that names the type's text field (a highlight's passage) reads the item's opening line, since the text is not one of its properties.
- **A search result** keeps its excerpt where the Secondary line would be, in a Standard row. A Compact list shows a search result in Standard, since a title and a date cannot show why an item matched.
- **Selection.** A selected row is drawn on the soft grey of `SoftSelection`, so chips and text keep their colors.

The Density setting is in Settings > Lists, and Edit View's Density picker and a place's choice override it. See [Presets and densities](presets-and-densities.md).

## Related pages

- [Presets and densities](presets-and-densities.md)
- [Value components](value-components.md)
- [Views and lists](views-and-lists.md)
