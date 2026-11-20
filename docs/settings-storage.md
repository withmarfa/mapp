# Settings storage

Status: Built in v0.0.43. The store of type looks and the list density are built in v0.0.44. See [Looks](looks.md).

Where it lives: `ListKey`, `PageKey`, `OrderKey` and `InterfaceKey` under `MAPP/Views/`, and `PagePlacements`, `ViewLayouts`, `PlaceDefaults`, `Density`, `SidebarLayouts`, `TypeLooks`, `IncludedSubtypes`, `SearchLeaveOuts`, `DateFormat` and `RemotePictureSetting` under `MAPP/Model/`.

MAPP keeps its own settings in the app's defaults on this Mac today. It is agreed that they move into one hidden item in the Marfa, `app.mapp.preferences`, with window sizes, column widths and On This Mac staying on the Mac ([Agreed designs](agreed-designs.md#settings)). Until that is built, the scopes below stand. This page lists where each kind of setting lives, so you know which scope a new setting belongs to.

## Scopes

A setting has one scope. Pick the narrowest scope that matches what the person would expect.

| Scope | Where | Settings |
| --- | --- | --- |
| Every window | One key in the defaults. | `listDensity`, `openItemsIn` (where an item opens: `modal`, `fullPage` or `newWindow`), `dateFormat`, `noteSort`, `groupsByDate`, the page options in `PageKey` (`titleLines`, `linkLook`, `fullWidthPages`, `showsCoordinates` and others), `remotePictures`, the interface options in `InterfaceKey`. |
| A type | One value keyed by type identifier. | `pagePlacements` (pins, shown rows, property order, sidebar sections, where Linked From goes), `includedSubtypes`. |
| A saved view | One value keyed by the view's item identifier. | `viewLayouts`: a `ViewMacSettings` with the layout, columns, whether the board hides empty groups, the gallery's cards, the calendar's Week or Month choice, the list's density and the table's widths. A place's own calendar choice is kept in `placeDefaults`. |
| A place | A key built from the place. | `placeDefaults` (the default view of a place that is not a saved view: its filters, sort, grouping, layout, timeline date, compact board, gallery cards and calendar scale), `itemTableColumns` (the table's columns for each place), `placeDensities` (the density of a place that is not a saved view), `indexTab.<place>` and `indexSort.<place>` (an index page's tab and the order of its table). |
| A server | One value keyed by server address. | `sidebarLayouts`: for each server, the hidden places, their order, the tabs, the sections of each tab with their shortcuts, where a place sits when it was moved to another section, and the color of each view's mark; `typeLooks`: the looks chosen for its types; and `searchLeaveOuts`: the types and sources left out of search (a type takes its subtypes with it). |
| A window | Scene storage, or memory only. | The layout in `SceneStorage("browser")`, `detailsPresented` and `sidebarHidden`. |

Column widths are `interfaceDefaultWidth.<column>`, and the right sidebar's width and open sections are `inspectorWidth` and the `inspector*Open` keys.

## Rules

The rules that apply to every setting are in the `AGENTS.md` files: [that today nothing goes to Marfa](../AGENTS.md), [how a saved view's Mac settings are kept and forgotten](../MAPP/Model/AGENTS.md), and [how a Debug build keeps its own values](../AGENTS.md). Three more belong to this page.

- **A type's setting has little inheritance.** `pagePlacements` for a child type does not read its parent's. A look does: it follows the `parent` chain, place by place; see [Looks](looks.md).
- **Unreadable stored text is set aside, not dropped.** When a stored value cannot be decoded, MAPP keeps the text under a `...SetAside` key (`pagePlacementsSetAside`, `viewLayoutsSetAside`, `sidebarLayoutsSetAside`, `typeLooksSetAside`, `placeDensitiesSetAside`, `placeDefaultsSetAside`, `itemTableColumnsSetAside`, `searchLeaveOutsSetAside`) and starts from the defaults, so a person's arrangement can be recovered.
- **A new field on a stored value is optional.** A value saved before the field existed must still decode.

## The Settings window

As built, Settings is a place in the sidebar, not a separate window; it is agreed to become a window of its own ([Agreed designs](agreed-designs.md#settings)), which leaves out the Settings column's width. It shows its pages in the list column (`SettingsPage`) and the chosen page in the detail column. The pages are Appearance, Lists, Editor and Sidebar ([Settings > Sidebar](views-and-lists.md#settings--sidebar)); then Library, This Marfa and Recently Deleted; then About.

The sidebar, list and Settings columns each have a default width a person can change in Settings (`ColumnWidth`): 230, 330 and 280 points, each within a range the column allows. The measurements of a page's rows and boxes are in [Views and lists](views-and-lists.md). The agreed pages and rules for the new Settings window are in [Agreed designs](agreed-designs.md#settings).

## Looks

`typeLooks` holds only what was chosen for a type, place by place, as sorted-key JSON; every other look is worked out from the type's fields. It replaces the type styles, which are gone with no migration. A density is not part of a look: it is kept in `viewLayouts` for a saved view and in `placeDensities` for a place, and an old row choice (`listRowStyle` and the other row keys) is not read. Export Looks and Import Looks move a server's looks as a file. It is agreed that looks move with the rest of MAPP's settings into the Marfa, as Layouts rows per type ([Agreed designs](agreed-designs.md#settings)); until that is built they stay on this Mac. See [Looks](looks.md).

## Related pages

- [Looks](looks.md)
- [Marfa and MAPP](marfa-and-mapp.md)
- [Views and lists](views-and-lists.md)
