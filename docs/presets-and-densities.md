# Presets and densities

Status: The presets and the two densities are built in v0.0.44. See [Looks](looks.md).

Where it lives: `LookPreset` under `MAPP/Model/Looks/`, `Density` and `PlaceDensities` under `MAPP/Model/`, `ItemRow` under `MAPP/Views/`, and the two places that choose a density, `ListsSettings` and `ViewPanelDensity` under `MAPP/Views/`.

A preset is the starting look for a type. A density is how much room a row takes. Both are suggestions that a look builds on, not layouts a person has to choose between.

## Presets

A type gets a preset from its fields (`LookPreset.suggested`), and the preset fills each place of the look from the fields the type has; a place the type has no field for stays empty. A child type takes its parent's look instead, place by place, unless its own fields suggest another preset. See [Looks](looks.md).

| Preset | For | Secondary | Bottom line | Date |
| --- | --- | --- | --- | --- |
| Note | Notes, documents, meeting notes, transcripts | The opening line | Tags | Updated |
| Message | Email, chat, comments | The sender | None | Sent |
| Task | Tasks, issues, pull requests, sessions, checklists | Project or repository | Status, priority, people, and "3 of 7 done" | Due, else updated |
| Event | Events, meetings, bookings | Time and place | People | Starts |
| Person | People, organizations | Role and organization | One way to reach them | None |
| Place | Places, venues | The address | Category | None |
| Media | Bookmarks, articles, photos, video, audio, books, files | Site, author or size | Duration or progress | Published |
| Quote | Highlights, clippings | The passage | Location | Captured |
| Clip | Clipboard items | What was copied | The app it came from | Copied |
| Record | Transactions, workouts, measurements | Category | The amount or the numbers | Happened |

### How a preset is chosen

The first of these that fits wins, so the order is the rule. A preset names no type: it reads fields and their kinds. The exceptions are the highlight type, a file type (`Catalogue.isFileType`) and a person (`PageHeaderKind`), which no field tells.

1. **Quote.** The type is, or is below, `core.highlight`.
2. **Place.** `latitude` and `longitude` with a street, locality or postal code. An event or an image has coordinates and no address. Place comes before Person, since a place builds on an entity and carries its emails and phones.
3. **Person.** A person by header, or a type that itself declares `emails` or `phones` (`Field.declaredBy` is the type). A bare `core.entity` declares them, so it is a Person, since it stands for people and organizations. A child that only inherits them, such as a repository under an entity, is not: its own fields suggest its preset, which here is Note.
4. **Media.** A file type, or a type whose page is for reading (a bookmark, media). It comes before Task, since media has a progress status.
5. **Record.** A number with a currency code (a string field of the `currency` format). A record's date is Marfa's own `occurred_at`, which every item has and no type declares, so it cannot tell a record.
6. **Task.** A status field, whatever it is called.
7. **Event.** A `starts_at` field on an event.
8. **Message.** A `from` field.
9. **Clip.** A `source_app` field.
10. **Note.** Anything else, a type with no fields, and a type the server lacks.

No type Marfa ships gets Record or Clip today; a type with a number and a currency code, or a `source_app`, does.

The dates of a Quote ("captured"), a Clip ("copied"), a Record ("happened") and a Message ("sent") are all Marfa's own `occurred_at` (`LookDate.occurred`), or the created date for an item with none. MAPP's `Item` holds it as `occurred`. An Event's Secondary is its time of day (`LookPart.time`) and its place, since the Date top right already shows the day.

The title is always the item's name. A clipboard item is titled "Clipboard Item", or a name its person gave it, and never its content.

## Densities

There are two: Standard and Compact.

- **Standard.** The row has a Title, a Date, a Secondary line and a bottom line. See [Looks](looks.md).
- **Compact.** One line: the type's mark, only in a list that mixes types, then the title, then the date.

The density a list uses is the first of these that has a choice:

1. A saved view's own, set in Edit View (stored in the view's Mac settings).
2. For a place that is not a saved view, the place's own, set in Edit View's Density and kept on this Mac for that place.
3. The Density in Settings > Lists.

Edit View offers "As in Settings", Standard and Compact; "As in Settings" clears the choice. A search result is always a Standard row, since its excerpt needs the room.

## Related pages

- [Looks](looks.md)
- [Views and lists](views-and-lists.md)
- [Settings storage](settings-storage.md)
