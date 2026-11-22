# Looks

Status: Relation shipped in v0.0.47. Count and the list row's picture are available in this branch. The model, the store, Export and Import and the list row are built in v0.0.44. The gallery card, the board card and the table are built in v0.0.45. Every view reads the look of the type of each item it draws. The gallery card's real previews (a PDF's page, a video's frame, a bookmark's attached picture) and its shape are built, not yet released, and so is the favorite's star on the card and in the table.

Where it lives: `TypeLook`, `LookPreset`, `TypeLookResolver`, `TypeLooks` and `LooksFile` under `MAPP/Model/Looks/`, `LooksCommands` under `MAPP/Views/`, the row's content (`RowContent`, `RowContents`) under `MAPP/Model/Items/`, `Density` under `MAPP/Model/`, `ItemRow` and `ItemList` under `MAPP/Views/`, the cards' content (`CardContents`) and the table's columns (`ItemTableLayout`) under `MAPP/Model/Items/`, `ViewCards` under `MAPP/Model/`, the card pictures' sources and face (`CardPicture`, `CardFace`) and the row's picture (`RowPicture`) under `MAPP/Model/Items/`, `RowPictureView` and `GalleryCard`, `ItemBoard`, `ItemTable`, `ItemTableCell` and `ChipLine` under `MAPP/Views/`.

A look says how one type is drawn. Every view of that type, whether a list, a gallery, a board, a table or the page, reads the same look, so one item never changes character between views.

## The model

- Marfa holds what a thing is. MAPP holds how each type looks. See [Marfa and MAPP](marfa-and-mapp.md).
- A type has one look. Every view uses it.
- A type starts from a preset chosen from its fields. See [Presets and densities](presets-and-densities.md).
- A child type takes its parent's look, place by place, along Marfa's `parent` chain, at most ten types up. It does so only through types whose fields suggest the same preset: a place under an entity gets Place, not the entity's Person, and a repository under an entity gets Note. A parent the server lacks ends the walk.
- A person edits a type's look in Settings > Layouts ([Settings pages](settings.md#layouts)) or imports a file of them; until then the presets are the looks.
- A view adds little: its layout, its density, a gallery's cards and its Properties list. The date and the Secondary line come from the type, and so do the facts until the view changes its Properties.
- Looks are kept for each server, in the defaults and synced through the Marfa, with an export (`TypeLooks`). The store holds only what was chosen, place by place; every other look is worked out each time, so a better preset improves every look nobody chose. A density is not part of a look: a saved view keeps its own and a place keeps its own. See [Settings storage](settings-storage.md).
- `TypeLooks.looks(in:library:)` is the one way to resolve looks: it works out every type's look once. A caller holds the result for a catalogue revision and a set of choices, and never resolves in a row's body. A type the catalogue lacks has no entry.
- A look syncs with MAPP's other settings, as a row of the `types` table, never as an item's own data.

## What a look holds

A `TypeLook` has three places. A view adds its layout, its density, a gallery's cards and its Properties list; the date and the Secondary line stay the type's.

- **Date.** A date field of the type, when the item was created, when it was last edited, when it happened, or none. An item with no value in the field shows when it was last edited. When it happened is Marfa's own `occurred_at`, which every item has and no type declares as a field; an item with none shows when it was created. MAPP's `Item` holds it as `occurred`.
- **Secondary.** Up to two parts joined with ", ": a field, a date field's time of day, the item's opening line, the website of its `url`, a file's kind and size, or the title of the item's parent (`parent`). A time of day is offered only for a date field that includes a time, and an all-day value shows nothing for that part, so an event's Date shows the day and its Secondary "7:30 pm, Brat, Shoreditch". The timeline gives the time a column of its own, so it leaves a time of day out of the Secondary line.
- **Facts.** A view shows fields, tags, relations, and counts in the look's order after the status. A relation is the parent, the children, or the collections (`parent`, `children`, or `collections` in a looks file). Each appears as a linked-item chip. See [Composed properties](composed-properties.md).

`count:children` counts active children. `count:members` counts active collection members. `count:progress` shows the proportion of active children with a status that are completed or canceled, such as "3 of 7 done". `count:rows:<table>` counts an item's rows in the named table, such as "214 messages". A count with nothing to display leaves the fact blank. A count column starts hidden until a row has a value to display.

A row or card requests its counts when it appears, even if another window already shows it. A wide board requests counts only for the lanes in view. When the working copy reports a new sync time, MAPP requests fresh table row counts for the items on display. Changes to items or edges also refresh counts. MAPP can display the previous answer while it waits.

Count columns do not support sorting in the table header or in Add Sort. MAPP drops a stored count sort because rows the table has yet to display may have no answer.

A type with a status field always shows its status first, so a status is never a fact. A place the type has no field for stays empty: a look never names a field its type lacks, and a chosen date field the type lacks is replaced by the preset's date, while a chosen part or fact it lacks is left out.

## Export and import

File > Export Layouts writes every look of the connected server's types as one JSON file, and File > Import Layouts reads one; both are also in the command palette and under the list in Settings > Layouts. People see Layouts; the code and the file keep Looks. The file names its format (`mapp-looks`) and version and no server, and holds a look for each type the server has, each place by its word, such as `field:due_at`, `time:starts_at`, `opening`, `site`, `file`, `tags`, `parent`, `children`, `collections`, `created`, `edited`, `occurred` or `none`.

- An export writes every look as this Mac resolves it. An import stores, for each type and place, only a value that differs from what this Mac would work out for the place without a choice (the preset, and what the types above it chose), and clears the place's choice where the file's value is the same. Importing your own export therefore changes nothing, a file with one changed place stores that place alone, and a later better preset still reaches every place nobody chose. A child is measured against its parent's choices as the import leaves them, so after an import every type shows the look the file holds. A child listed with its parent's old value keeps that value as its own choice.
- A type the server lacks has nothing to measure against: its whole look is kept and waits for the type. An export holds it too, so a round trip loses nothing.
- A file that cannot be read, is not a looks file, is another version or holds a word this version does not know is refused whole with a notice, and nothing is written.
- Looks chosen for other types are left as they were.

## The places of a row

A look fills a fixed set of places. A place with nothing to show is left out and leaves no gap.

- **Title.** The item's name, as Marfa has it. No gray key or number comes before it, because a number is a property.
- **Date.** Top right, on every row that has one. It is the date the list is sorted by, otherwise the type's own date: due, published, taken or updated. Inside a day's group it is the time.
- **Secondary.** One line under the title that the look chooses, such as a repository, a website, an address or a highlight's passage.
- **Bottom line.** The type's chip, only when the list mixes types and is not grouped by type, whose group headers already name it. Then the status, then up to two facts, then "+N" for the rest. These are the page's own chips at row size: 20 points high with 11.5-point text. A person is initials only, in the pale circle. Tags do not show in a row, except in a Note's: the Note preset names `tags` as its fact, shown at row size. A linked item (the parent, the children or the collections) shows as a linked-item chip when the look names it, up to two, then "+N". A row or card finds its two without sorting every link. The chip does not underline under the pointer there, since a click selects the row; the table's cell opens the item.

- **Picture.** A Standard row whose item has a picture shows it at the trailing edge, under the date and beside the Secondary and bottom lines: 44 points square, with a 6-point corner radius and a hairline edge, cut to fill. It is the picture a gallery card would show, from the same places: an image file's own, a PDF's first page, a video's frame or another file's Quick Look thumbnail, the item's first embedded image, or an image file attached to it. A picture at a web address (`image_url`) is never loaded for a row. A row has one only where the list is Standard and the item has one of those places; a Compact row never does. It is made off the main thread, a few at a time and only while the row is on screen, and cached with the cards' pictures, with a quiet frame until it is ready. Where an item turns out to have no picture (a file Quick Look cannot draw, a deleted embed, no connection) the frame stays and holds the file's kind icon or the type's mark, so a row never changes height once drawn. A row with a picture is as tall as the picture needs, 44 points plus the row's padding, so it is the only Standard row taller than its words.

Nothing indents a row. No status circle or highlight bar sits at the leading edge.

A row never shows the tier. Inbox is a view of the feed tier, not a fact about a row. A row's preview starts from the item's text, not from its first heading. Marfa's core works out the preview and MAPP shows it; the preview rule is agreed, not built.

## One look in every view

Each view resolves the looks once for a catalogue revision and the person's choices (`Browser.looks(in:)`, `CardContents`, `RowContents`), and never in a card's or a cell's body. A list of several types draws each item from its own type's look.

A view's or place's Properties list, one for every layout, falls back to each type's look until the person changes it (`ViewProperties.looks`, read through `Browser.propertyLooks`). The type's look stays the default, and the Secondary line and the date stay the type's. Built, not yet released. [Properties](views-and-lists.md#properties) says the rest.

- **List.** The row above.
- **Gallery card.** The picture, or the item's opening lines when it has none, so a title never shows twice. A picture is the one MAPP can make: an image file's own, a PDF's first page, a video's frame or another file's Quick Look thumbnail, an item's first embedded image, or an image file attached to the item, as a bookmark's saved cover is. A picture at a web address (`image_url`) is never loaded for a card. Pictures are made off the main thread, cached and never written to Marfa, with a quiet frame until ready. An item with neither a picture nor text shows its type's mark. Then the title on up to two lines, then the Secondary line. The Secondary line leaves out the opening line while the picture area shows it. A card says no date and no status. A favorite's star is the one mark on the picture, drawn in yellow on a pale material disc. Every picture area in a row is one height and cards align at the top, and every card reserves two title lines and one Secondary line, so every row is one height. Opening lines read as text: emphasis is styled, a list item has a bullet, a task shows its words, a table shows its cells as words, and rules and a table's separator row are left out (the item itself is never changed). The view chooses the preview, whether a picture is fitted, the shape (standard four to three, square or a book's two to three cover) and the card's size.
- **Board card.** The title, the Secondary line and the bottom line, without the field the board is grouped by. The bottom line is the row's: the type only where the board mixes types, the status, two facts and "+N". A board grouped by status leaves the status off every card, whichever field holds it. A compact board keeps a title-only card, with the type's mark where the board mixes types. A card says no date.
- **Table.** The title column, then the look's facts as columns, drawn with the same chips: a status or a priority as a chip, a choice as an option chip, people as initials and name, the type as a chip, a date or a number as plain text with no label. The look's date follows the facts. The columns of several types are the union of their looks, the status first and the rest in the order the looks give them. A look's column that no row fills starts hidden. The table always reads each row's parent, so its filter and grouping are always offered, and reads the children and collections only for a column the look or the person shows, or a group, filter or sort names. Every other property, the Parent, Children and In Collection columns, Created, Edited, Happened and Tags among them, waits behind View Options. A saved view's chosen columns win over the look. See [Value components](value-components.md).

## How a row is made

A list row is one view for every type (`ItemRow`), drawn in one of two densities (`Density`). It holds no logic of its own: it draws a `RowContent`, which is plain values worked out from an item, the look of its type and the list.

- **Looks.** `ItemList` reads the looks from `Browser.looks(in:)`, which resolves them once for a catalogue revision and the person's choices, and never resolves in a row's body (`RowContents`).
- **Content.** `RowContent.make` works out the title, the date, the Secondary line and the bottom line for one item, and whether it has a picture (`RowContent.picture`, a `RowPicture`: the item and its attached images, for a list that shows pictures, `RowList.showsPictures`, which a Standard list does). `RowContents` reads the files attached to each item once for a pass, as the gallery does, and only for a Standard list. `RowContents` holds the result for each item value, so a change of selection, or of one item, works out one row at most and a row's body looks nothing up. The content is dropped when the catalogue, the looks, the list or the day changes, and made again for a row whose linked items changed (a renamed parent, a child that comes or goes).
- **The list tells each row what it shares** (`RowList`): whether the list holds several types, which date it is sorted by, and the day. A list sorted by a date, whether by a column or by the global order, shows that date in every row; a list sorted by title, by relevance or by its own order shows each type's look date. An item with no value in the sorted date field shows no date.
- **Inside a day's group** (Today and Yesterday) the date is the time of day; elsewhere it is the list's label for the date, so a day to come reads as a day and not a time.
- **A look's date that names a date field** falls back to when the item was last edited where the item has no value. A list sorted by a date field does not fall back, since a row with no date there has nothing to say about the order.
- **Facts.** A fact that has no value for an item is skipped. A person shows as initials in the pale circle, the first of several with the rest counted in "+N"; a choice or a priority shows as an option chip; a text, number or date shows as plain secondary text led by its field's label ("Location 1712", "Due 14 Nov"); a yes-or-no shows its label alone when it is yes, and nothing when it is no; a Note's tags show as tag chips, up to three; a relation shows as linked-item chips, up to two; a count shows as one chip ("4 of 5 done", "12 items") when Marfa answers. The help tag for children and progress lists each nonempty status group and how many children have no status. Up to two facts show, and every value left out is counted in "+N", whether the fact that left it out shows or not.
- **The item's text.** A Secondary part or a fact that names the type's text field (a highlight's passage) reads the item's opening line, since the text is not one of its properties.
- **A search result** keeps its excerpt where the Secondary line would be, in a Standard row. A Compact list shows a search result in Standard, since a title and a date cannot show why an item matched.
- **The picture is made by its own view** (`RowPictureView`), only for a row that has one, and never in the row's body: the row says that a picture is there and draws its frame.
- **Selection.** A selected row is drawn on the soft grey of `SoftSelection`, so chips and text keep their colors.

The Density setting is in Settings > Lists, where each density is shown as a few sample rows drawn by the real row, the Standard one with a sample picture on its first row ([Settings pages](settings.md#lists)). Edit View's Density picker and a place's choice override it. See [Presets and densities](presets-and-densities.md).

## Related pages

- [Presets and densities](presets-and-densities.md)
- [Value components](value-components.md)
- [Views and lists](views-and-lists.md)
