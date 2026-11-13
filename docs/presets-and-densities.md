# Presets and densities

Status: Agreed, not built. Today a list row takes one of six row styles; see [Looks](looks.md).

Where it lives: `ListRowStyle`, `ListRowType` and the row facts in `ListRowFacts.swift` under `MAPP/Model/Items/`, and `ListsSettings` and `ViewPanelRows` under `MAPP/Views/`. The presets and densities below replace them.

A preset is the starting look for a type. A density is how much room a row takes. Both are suggestions that a look builds on, not layouts a person has to choose between.

## Presets

A new type gets a preset from its fields. A child type starts from its parent's look instead, place by place. How a preset is chosen from a type's fields is decided when the feature is built.

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

The title is always the item's name. A clipboard item is titled "Clipboard Item", or a name its person gave it, and never its content.

## Densities

There are two: Standard and Compact. A view chooses one.

- **Standard.** The row has a Title, a Date, a Secondary line and a bottom line. See [Looks](looks.md).
- **Compact.** One line: the type's mark, only in a list that mixes types, then the title, then the date.

The Row Style control in Edit View becomes a Density control, and the six row styles go.

## Built today

Settings and Edit View offer Standard, Compact and With Pictures for every list. Task, Highlight and Person rows are chosen for a type or a view, or come from the type's fields. A person's choice for each type is stored as `listTypeStyles`, and a saved view's row choices are stored with the view's other settings on the Mac.

## Related pages

- [Looks](looks.md)
- [Views and lists](views-and-lists.md)
- [Settings storage](settings-storage.md)
