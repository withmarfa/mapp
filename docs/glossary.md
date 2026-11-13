# Glossary

Status: Built in v0.0.43. Entries marked "agreed, not built" describe a design that a later release builds.

Where it lives: `Catalogue`, `Item`, `SidebarItem`, `PropertyRow`, `PagePins` and `ItemViewMode`, under `MAPP/Model/`.

This page defines the words MAPP uses. Each entry names who owns the thing, Marfa or MAPP, and links to the page that explains it. [Marfa and MAPP](marfa-and-mapp.md) explains the split.

| Term | Owner | Meaning | Read more |
| --- | --- | --- | --- |
| Catalogue | Marfa | The server's list of types, fields and edge types. MAPP reads it as `Catalogue` and names no type of its own. | [Marfa and MAPP](marfa-and-mapp.md) |
| Chip | MAPP | One value drawn as a small rounded label, 22 points tall (`PageChip`). | [Value components](value-components.md) |
| Collection | Marfa | An item of a type that plays the `container` role. Other items are filed under it with an `in-collection` edge. | [Marfa and MAPP](marfa-and-mapp.md) |
| Composed property | MAPP | A property that MAPP builds from fields or edges, such as Location or Count. Agreed, not built. | [Composed properties](composed-properties.md) |
| Density | MAPP | How much room a row takes: Standard or Compact. Built in v0.0.44. | [Presets and densities](presets-and-densities.md) |
| Edge | Marfa | A typed link from one item to another. MAPP shows an edge's name as Marfa words it. | [Marfa and MAPP](marfa-and-mapp.md) |
| Item | Marfa | A record in a library: a type, properties, a text body and edges. | [Marfa and MAPP](marfa-and-mapp.md) |
| Layout | MAPP | How a list of items is drawn: list, gallery, table, board or timeline (`ItemViewMode`). | [Views and lists](views-and-lists.md) |
| Look | MAPP | How one type is drawn in every view: its date, the line under the title and its facts. The list row reads it in v0.0.44; the gallery, board and table read it too, built, not yet released. | [Looks](looks.md) |
| Pin | MAPP | A property shown under an item page's title, at most four per type (`PagePins`). | [Item page](item-page.md) |
| Place | MAPP | Somewhere the sidebar can open: Inbox, a type, a source, a collection, a saved view (`SidebarItem`). | [Views and lists](views-and-lists.md) |
| Preset | MAPP | The starting look that a type takes from its fields (`LookPreset`). Built in v0.0.44. | [Presets and densities](presets-and-densities.md) |
| Property | Marfa and MAPP | A value an item holds, shown as a row on the page. Fields and edges are Marfa's; the row, its icon and its place are MAPP's (`PropertyRow`). | [Item page](item-page.md) |
| Property block | MAPP | The rows under the pins on an item page. | [Item page](item-page.md) |
| Right sidebar | MAPP | The panel beside the page that lists every property, links and history sections (`ItemInspector`). | [Item page](item-page.md) |
| Saved view | Marfa and MAPP | A `system.view` item that holds a title, query, sort and group. MAPP adds the layout, columns, cards and density on the Mac. | [Views and lists](views-and-lists.md) |
| Slot | MAPP | One fixed place in a look, such as Title or Date. The look's own places (date, secondary, facts) and the row's are built. | [Looks](looks.md) |
| Source | Marfa | Where an item came from, such as a connector or an app. Marfa holds its name and mark. | [Marfa and MAPP](marfa-and-mapp.md) |
| Status group | Marfa | One of four fixed groups (not started, in progress, completed, canceled) that every type's status words belong to (`StatusGroup`). | [Value components](value-components.md) |
| Tone | MAPP | The color a type's mark and chip take, chosen by the type's icon (`TypeTone`). Marfa holds no color. | [Value components](value-components.md) |
| Type | Marfa | What an item is, with its fields, parent, status words and icon. | [Marfa and MAPP](marfa-and-mapp.md) |
| Type mark | MAPP | A type's icon in its tone on a pale rounded square (`TypeMark`). | [Value components](value-components.md) |
| Value component | MAPP | One drawing for one kind of value, in a row, on the page and in an editor. Agreed, not built. | [Value components](value-components.md) |
