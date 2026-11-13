# Settings storage

Status: Built in v0.0.43. The store of type looks and the list density are built, not yet released. See [Looks](looks.md).

Where it lives: `ListKey`, `PageKey`, `OrderKey` and `InterfaceKey` under `MAPP/Views/`, and `PagePlacements`, `ViewLayouts`, `Density`, `SidebarLayouts`, `TypeLooks`, `IncludedSubtypes`, `DateFormat` and `RemotePictureSetting` under `MAPP/Model/`.

MAPP keeps its own settings in the app's defaults on this Mac and never writes them to Marfa. This page lists where each kind of setting lives, so you know which scope a new setting belongs to.

## Scopes

A setting has one scope. Pick the narrowest scope that matches what the person would expect.

| Scope | Where | Settings |
| --- | --- | --- |
| Every window | One key in the defaults. | `listDensity`, `dateFormat`, `noteSort`, `groupsByDate`, the page options in `PageKey` (`titleLines`, `linkLook`, `fullWidthPages` and others), `remotePictures`, the interface options in `InterfaceKey`. |
| A type | One value keyed by type identifier. | `pagePlacements` (pins, shown rows, property order, sidebar sections, where Linked From goes), `includedSubtypes`. |
| A saved view | One value keyed by the view's item identifier. | `viewLayouts`: a `ViewMacSettings` with the layout, columns, whether the board hides empty groups, the gallery's cards, the list's density and the table's widths. |
| A place | A key built from the place. | `itemTableColumns` (the table's columns for each place), `placeDensities` (the density of a place that is not a saved view), `indexLayout.<place>` and `indexWidth.<place>`. |
| A server | One value keyed by server address. | `sidebarLayouts`, and `typeLooks`: for each server, the looks chosen for its types. |
| A window | Scene storage, or memory only. | The layout in `SceneStorage("browser")`, `detailsPresented` and `sidebarHidden`. |

Column widths are `interfaceDefaultWidth.<column>`, and the right sidebar's width and open sections are `inspectorWidth` and the `inspector*Open` keys.

## Rules

The rules that apply to every setting are in the `AGENTS.md` files: [that nothing goes to Marfa](../AGENTS.md), [how a saved view's Mac settings are kept and forgotten](../MAPP/Model/AGENTS.md), and [how a Debug build keeps its own values](../AGENTS.md). Three more belong to this page.

- **A type's setting has little inheritance.** `pagePlacements` for a child type does not read its parent's. A look does: it follows the `parent` chain, place by place; see [Looks](looks.md).
- **Unreadable stored text is set aside, not dropped.** When a stored value cannot be decoded, MAPP keeps the text under a `...SetAside` key (`pagePlacementsSetAside`, `viewLayoutsSetAside`, `sidebarLayoutsSetAside`, `typeLooksSetAside`, `placeDensitiesSetAside`) and starts from the defaults, so a person's arrangement can be recovered.
- **A new field on a stored value is optional.** A value saved before the field existed must still decode.

## The Settings window

Settings is a place in the sidebar, not a separate window. It shows its pages in the list column (`SettingsPage`) and the chosen page in the detail column. The pages are Appearance, Lists, Editor and Sidebar; then Library, This Marfa and Recently Deleted; then About.

The sidebar, list and Settings columns each have a default width a person can change in Settings (`ColumnWidth`): 230, 330 and 280 points, each within a range the column allows. The measurements of a page's rows and boxes are in [Views and lists](views-and-lists.md).

## Looks

`typeLooks` holds only what was chosen for a type, place by place, as sorted-key JSON; every other look is worked out from the type's fields. It replaces the type styles, which are gone with no migration. A density is not part of a look: it is kept in `viewLayouts` for a saved view and in `placeDensities` for a place, and an old row choice (`listRowStyle` and the other row keys) is not read. Export Looks and Import Looks move a server's looks as a file. Whether looks sync between Macs through Marfa is not decided. See [Looks](looks.md).

## Related pages

- [Looks](looks.md)
- [Marfa and MAPP](marfa-and-mapp.md)
- [Views and lists](views-and-lists.md)
