# Glossary

Status: Built in v0.0.43. Entries marked "agreed, not built" describe a design that a later release builds.

Where it lives: `Catalogue`, `Item`, `SidebarItem`, `PropertyRow`, `PagePins` and `ItemViewMode`, under `MarfaMac/Model/`.

What is agreed and not built yet is in [Agreed designs](agreed-designs.md). This page defines the words the app uses. Each entry names who owns the thing, Marfa or the app, and links to the page that explains it. [Marfa and the app](marfa-and-the-mac-app.md) explains the split.

| Term | Owner | Meaning | Read more |
| --- | --- | --- | --- |
| Button | The app | A rounded rectangle at 22 or 28 points with a role: primary, secondary, plain or destructive (`AppButtonStyle`). The toolbar's glass buttons are the system's. | [Components](components.md) |
| Catalogue | Marfa | The server's list of types, fields and edge types. The app reads it as `Catalogue` and names no type of its own. | [Marfa and the app](marfa-and-the-mac-app.md) |
| Chip | The app | One value drawn as a small rounded label, 22 points tall (`PageChip`). | [Value components](value-components.md) |
| Collection | Marfa | An item of a type that plays the `container` role. Other items are filed under it with an `in-collection` edge. | [Marfa and the app](marfa-and-the-mac-app.md) |
| Composed property | The app | A value that the app presents from fields, links, or table rows. Location, Relation, and Count are composed properties. | [Composed properties](composed-properties.md) |
| Density | The app | How much room a row takes: Standard or Compact. Built in v0.0.44. | [Presets and densities](presets-and-densities.md) |
| Edge | Marfa | A typed link from one item to another. The app shows an edge's name as Marfa words it. | [Marfa and the app](marfa-and-the-mac-app.md) |
| Item | Marfa | A record in a library: a type, properties, a text body and edges. | [Marfa and the app](marfa-and-the-mac-app.md) |
| Item link | Marfa | An item's `marfa://<instance id>/<item id>` link. The app opens the item it names only in the connected Marfa, and a link never changes anything (`ItemAppLink`). Built, not yet released. | [Marfa and the app](marfa-and-the-mac-app.md#item-links) |
| Keycap | The app | A shortcut's glyph drawn as a small outlined cap, one glyph each, with no fill, wherever the app draws a shortcut itself (`KeyCap`). | [Components](components.md) |
| Layout | The app | How a list of items is drawn: list, gallery, table, board or timeline (`ItemViewMode`). | [Views and lists](views-and-lists.md) |
| Look | The app | How one type is drawn in every view: its date, the line under the title and its facts. The list row reads it in v0.0.44; the gallery, board and table read it in v0.0.45. | [Looks](looks.md) |
| Pin | The app | A property shown under an item page's title, at most four per type (`PagePins`). | [Item page](item-page.md) |
| Place | The app | Somewhere the sidebar can open: Inbox, a type, a source, a collection, a saved view (`SidebarItem`). | [Views and lists](views-and-lists.md) |
| Preset | The app | The starting look that a type takes from its fields (`LookPreset`). Built in v0.0.44. | [Presets and densities](presets-and-densities.md) |
| Properties list | The app | The fields a view shows after the title, one list for every layout, falling back to each type's look until changed. Built, not yet released. | [Views and lists](views-and-lists.md#properties) |
| Property | Marfa and the app | A value an item holds, shown as a row on the page. Fields and edges are Marfa's; the row, its icon and its place are the app's (`PropertyRow`). | [Item page](item-page.md) |
| Property block | The app | The rows under the pins on an item page. | [Item page](item-page.md) |
| Right sidebar | The app | The panel beside the page that lists every property, links and history sections (`ItemInspector`). | [Item page](item-page.md) |
| Saved view | Marfa and the app | A `system.view` item that holds a title, query, sort and group. The app adds the layout, Properties, cards and density on the Mac. | [Views and lists](views-and-lists.md) |
| Section | The app | A heading over rows in the sidebar: Library, Views, Types or one the person made. It sits in one tab and can hold views, collections and sources (`SidebarGroup`). | [Views and lists](views-and-lists.md) |
| Settings window | The app | The window of its own that holds this app's settings and the Marfa's, with a sidebar of pages, Back and Forward in the toolbar and one centered column (`SettingsWindowView`). | [Settings storage](settings-storage.md) |
| Shortcut | The app | A sidebar row that acts or goes somewhere, such as New or Search, and never takes the selection (`SidebarShortcut`). | [Views and lists](views-and-lists.md) |
| Slot | The app | One fixed place in a look, such as Title or Date. The look's own places (date, secondary, facts) and the row's are built. | [Looks](looks.md) |
| Source | Marfa | Where an item came from, such as a connector or an app. Marfa holds its name and mark. | [Marfa and the app](marfa-and-the-mac-app.md) |
| Status group | Marfa | One of four fixed groups (not started, in progress, completed, canceled) that every type's status words belong to (`StatusGroup`). | [Value components](value-components.md) |
| Tab | The app | A named set of the sidebar's sections. The sidebar shows a tab bar only with more than one (`SidebarTab`). | [Views and lists](views-and-lists.md) |
| Tone | The app | The color a type's mark and chip take, chosen by the type's icon (`TypeTone`). Marfa holds no color. | [Value components](value-components.md) |
| Type | Marfa | What an item is, with its fields, parent, status words and icon. | [Marfa and the app](marfa-and-the-mac-app.md) |
| Type mark | The app | A type's icon in its tone on a pale rounded square (`TypeMark`). | [Value components](value-components.md) |
| Value component | The app | One drawing for one kind of value, in a row, on the page and in an editor. Built in v0.0.44. | [Value components](value-components.md) |

Throwaway link to [a missing page](no-such-page.md).
