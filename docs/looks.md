# Looks

Status: Agreed, not built. Today MAPP draws a list row from one of six row styles; the section "Built today" says how.

Where it lives: `ListRowStyle`, `ViewRows` and `ViewCards` under `MAPP/Model/`, and `NoteList`, `GalleryCard` and `ItemBoard` under `MAPP/Views/`, with the row views in `ListRows.swift`.

A look says how one type is drawn. Every view of that type, whether a list, a gallery, a board, a table or the page, reads the same look, so one item never changes character between views.

## The model

- Marfa holds what a thing is. MAPP holds how each type looks. See [Marfa and MAPP](marfa-and-mapp.md).
- A type has one look. Every view uses it.
- A new type starts from a preset chosen from its fields. See [Presets and densities](presets-and-densities.md).
- A child type starts from its parent's look, place by place, along Marfa's `parent` chain.
- Until Settings lets a person edit a look, the presets are the looks.
- A view adds little: its layout, its density, and which date, picture and facts it shows. Everything else comes from the type.
- Looks are kept on this Mac for each server, with an export. One store replaces the type styles, the row parts of each saved view's settings, and the row state a window holds. See [Settings storage](settings-storage.md).

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

A list row takes one of six styles: Standard, Compact, With Pictures, Task, Highlight and Person (`ListRowStyle`). Settings > Lists offers the first three under In Every List. The others come from a type's fields, or from a choice for a type (For Particular Types) or for a view.

The style resolves as described in [Marfa and MAPP](marfa-and-mapp.md). In a list that mixes types, each row takes the style of its own type, so rows can differ within one list.

The six styles differ in ways a look removes. A Task row shows due, finish and repeat facts in place of the modified date. A Standard row shows the type's chip, at row size, under the preview, and a Compact row shows a type mark at the leading edge. A gallery card, a table cell and a board card each draw status, priority, people and type in their own way.

When the look is built, the six row styles go. The Row Style control in Edit View becomes a Density control, and the type styles in Settings become looks.

## Related pages

- [Presets and densities](presets-and-densities.md)
- [Value components](value-components.md)
- [Views and lists](views-and-lists.md)
