# Looks

Status: The model, the store and Export and Import are built, not yet released. Rows, cards and tables do not read a look yet: today a list row is drawn from one of six row styles, and the section "Built today" says how.

Where it lives: `TypeLook`, `LookPreset`, `TypeLookResolver`, `TypeLooks` and `LooksFile` under `MAPP/Model/Looks/`, `LooksCommands` under `MAPP/Views/`, and, until rows read a look, `ListRowStyle`, `ViewRows` and `ViewCards` under `MAPP/Model/`, with `NoteList`, `GalleryCard` and `ItemBoard` under `MAPP/Views/` and the row views in `ListRows.swift`.

A look says how one type is drawn. Every view of that type, whether a list, a gallery, a board, a table or the page, reads the same look, so one item never changes character between views.

## The model

- Marfa holds what a thing is. MAPP holds how each type looks. See [Marfa and MAPP](marfa-and-mapp.md).
- A type has one look. Every view uses it.
- A type starts from a preset chosen from its fields. See [Presets and densities](presets-and-densities.md).
- A child type takes its parent's look, place by place, along Marfa's `parent` chain, at most ten types up. It does so only through types whose fields suggest the same preset: a place under an entity gets Place, not the entity's Person. A parent the server lacks ends the walk.
- Until Settings lets a person edit a look, the presets are the looks, and Import Looks is the only way to choose one.
- A view adds little: its layout, its density, and which date, picture and facts it shows. Everything else comes from the type.
- Looks are kept on this Mac for each server, with an export (`TypeLooks`). The store holds only what was chosen, place by place; every other look is worked out each time, so a better preset improves every look nobody chose. The row parts of each saved view's settings and the row state a window holds join the store when rows read it. See [Settings storage](settings-storage.md).
- A look is never written to Marfa.

## What a look holds

A `TypeLook` has three places, and a view adds only its layout and density.

- **Date.** A date field of the type, when the item was created, when it was last edited, or none. An item with no value in the field shows when it was last edited.
- **Secondary.** Up to two parts joined with ", ": a field, the item's opening line, the website of its `url`, or a file's kind and size.
- **Facts.** The fields and tags shown after the status, in order; a view shows as many as fit. Later kinds MAPP builds (a count, a reading time, a relation) are new cases.

A type with a status field always shows its status first, so a status is never a fact. A place the type has no field for stays empty: a look never names a field its type lacks, and a chosen field the type lacks is passed over for the preset's.

## Export and import

File > Export Looks writes every look of the connected server's types as one JSON file, and File > Import Looks reads one; both are also in the command palette. The file names its format (`mapp-looks`) and version and no server, and holds a look for each type the server has, each place by its word: `field:due_at`, `opening`, `site`, `file`, `tags`, `created`, `edited` or `none`.

- An import keeps every look in the file as chosen, including those for types the server lacks, which wait for the type. An export holds them too, so a round trip loses nothing.
- A file that cannot be read, is not a looks file, is another version or holds a word this version does not know is refused whole with a notice, and nothing is written.
- Looks chosen for other types are left as they were.

## The places of a row

A look fills a fixed set of places. A place with nothing to show is left out and leaves no gap.

- **Title.** The item's name, as Marfa has it. No gray key or number comes before it, because a number is a property.
- **Date.** Top right, on every row that has one. It is the date the list is sorted by, otherwise the type's own date: due, published, taken or updated. Inside a day's group it is the time.
- **Secondary.** One line under the title that the look chooses, such as a repository, a website, an address or a highlight's passage.
- **Bottom line.** The type's chip, only when the list mixes types. Then the status, then up to two facts, then "+N" for the rest. These are the page's own chips at row size: 20 points high with 11.5-point text. A person is initials only, in the pale circle.

Nothing indents a row. No status circle or highlight bar sits at the leading edge.

A row never shows the tier. Inbox is a view of the feed tier, not a fact about a row. A row's preview starts from the item's text, not from its first heading. Marfa's core works out the preview and MAPP shows it; the preview rule is agreed, not built.

## One look in every view

- **List.** The row above.
- **Gallery card.** The picture, or the item's opening lines when it has none, so a title never shows twice. Then the title on up to two lines, then the Secondary line.
- **Board card.** The title, the Secondary line and the bottom line, without the field the board is grouped by.
- **Table.** The title column, then the look's facts as columns, drawn with the same chips. See [Value components](value-components.md).

## Built today

A list row takes one of six styles: Standard, Compact, With Pictures, Task, Highlight and Person (`ListRowStyle`). Settings > Lists offers the first three under In Every List. The others come from a type's fields (the preset suggestion above maps to them) or from a choice for a view. A person can no longer choose a style for a type.

The style resolves as described in [Marfa and MAPP](marfa-and-mapp.md). In a list that mixes types, each row takes the style of its own type, so rows can differ within one list.

The six styles differ in ways a look removes. A Task row shows due, finish and repeat facts in place of the modified date. A Standard row shows the type's chip, at row size, under the preview, and a Compact row shows a type mark at the leading edge. A gallery card, a table cell and a board card each draw status, priority, people and type in their own way.

When rows read the look, the six row styles go, and the Row Style control in Edit View becomes a Density control.

## Related pages

- [Presets and densities](presets-and-densities.md)
- [Value components](value-components.md)
- [Views and lists](views-and-lists.md)
