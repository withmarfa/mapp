---
summary: How a type gets its look, and what that look puts in a row, a card and a table column.
paths:
  - MarfaMac/Model/Looks/*.swift
  - MarfaMac/Model/Density.swift
  - MarfaMac/Model/Items/Row*.swift
  - MarfaMac/Model/Items/Card*.swift
  - MarfaMac/Model/Items/ItemRelations.swift
  - MarfaMac/Views/ItemRow.swift
  - MarfaMac/Settings/App/Layout*.swift
---

# How a type looks

A look says how one type is drawn in lists, tables, and gallery cards. In Settings, looks are called Layouts. Digest uses the item's type, source, title, preview, and available picture directly.

## The model

- **A type has one look, and one resolver works it out** (`TypeLooks.looks(in:library:)`). A caller holds the result for a catalogue revision and a set of choices. Never resolve in a row's, a card's or a cell's body, because it runs for each row.
- **A look starts from a preset, chosen from the type's fields** (`LookPreset`). A preset names no type but Marfa's highlight.
- **A child type takes its parent's look**, place by place, only through types whose fields suggest the same preset. A repository under an entity is therefore not drawn as a person.
- **Only what a person chose is stored, place by place**, so a better preset reaches every place nobody chose.
- **A look never names a field that its type lacks** (`LookSurface`). The place stays empty and leaves no gap.
- **A view adds its layout, density and properties list.** The date and the Secondary line stay the type's.

## The three places

- **Date:** a date field, created, edited, happened or none. An item with no value in the field shows when it was edited, or when it was made for happened.
- **Secondary:** up to two parts in one line, such as a field, a time of day, the opening line, the website, a file's kind and size, or the parent's title.
- **Facts:** fields, tags, relations and counts, in the look's order. A type with a status always leads with it, so a status is never a fact.

## Presets

The first that fits wins, so the order is the rule: Quote, Place, Person, Media, Record, Task, Event, Message, Clip, Note. The test of each is in `LookPreset.suggested`. Place comes before Person because a place has an entity's phones; Media comes before Task because media has a progress status.

| Preset | Secondary | Bottom line | Date |
| --- | --- | --- | --- |
| Note | Opening line | Tags | Edited |
| Message | Sender | None | Sent |
| Task | Project or repository, else the parent | Status, progress, priority, people | Due, else edited |
| Event | Time and place | People | Starts |
| Person | Role and organization | One way to reach them | None |
| Place | Address | Category | None |
| Media | Site, author or size | Duration or progress | Published |
| Quote | The passage | Location | Captured |
| Clip | What was copied | The app | Copied |
| Record | Category | The amount | Happened |

- **Captured, copied, happened and sent are Marfa's own `occurred_at`**, which every item has and no type declares.
- **The title is the item's name**, with no key or number before it. A clipboard item is never titled with its content.

## Rows

- **A row draws plain values** (`RowContent`), worked out once for each item value (`RowContents`), and looks nothing up. What every row of a list shares is in `RowList`.
- **The date is the one the list is sorted by**, else the look's. A list sorted by a field shows no date where the item has none, because another date would say nothing about the order.
- **In All Items, a Feed item's name ends with the Feed mark** in each layout that shows it (`FeedMark`). Single-line titles reserve space for the mark. Card titles draw it inline.
- **The type shows only where the list mixes types** and is not grouped by type.
- **A row shows two facts, and a count of the rest.** A fact with no value is skipped.
- **A row's picture comes from the item's own file, its first embed or an attached image**, never from a web address, because drawing a list must load nothing from a website. Its frame stays when no picture can be made, so a row never changes height.
- **A row's picture stays inside its row,** beside the text, in lists and in Settings' density preview.
- **A card without a picture shows its opening lines**, and its Secondary line then leaves them out.
- **A board's card leaves out the field its lanes are grouped by.**
- **Two densities:** Standard, and Compact, which is one line. The view's or place's own choice wins, then the setting. A search result is always Standard, because its excerpt says why it matched.

## Composed properties

The app builds these from fields and edges and stores nothing new in Marfa.

- **Location** is one property for `latitude` and `longitude` (`ItemLocation`). The numbers are properties only while Show Coordinates is on. One number alone, or a pair out of range, shows as stored and is not drawn.
- **Relation** is Parent, Children or In Collection, named as Marfa names the edge (`Relation`). `ItemLibrary.relations(of:wanting:)` reads only those a look asks for.
- **Count** is children, progress, members or a table's rows (`CountFact`). It is blank until Marfa answers, and it cannot be sorted by, because rows that were never shown have no answer.

## Export and import

- **Importing your own export changes nothing.** An import stores only what differs from what would be worked out without a choice (`LooksFile`).
- **A file that is not fully understood is refused whole**, so half a set never applies.
