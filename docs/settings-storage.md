# Settings storage

Status: Built in v0.0.43. The store of type looks and the list density are built in v0.0.44. See [Looks](looks.md).

Where it lives: `ListKey`, `PageKey`, `OrderKey` and `InterfaceKey` under `MAPP/Views/`, and `PagePlacements`, `ViewLayouts`, `PlaceDefaults`, `Density`, `SidebarLayouts`, `TypeLooks`, `IncludedSubtypes`, `DateFormat` and `RemotePictureSetting` under `MAPP/Model/`.

MAPP keeps its own settings in the app's defaults on this Mac today. It is agreed that they move into one hidden item in the Marfa, `app.mapp.preferences`, with window sizes, column widths and On This Mac staying on the Mac ([Agreed designs](agreed-designs.md#settings)). Until that is built, the scopes below stand. This page lists where each kind of setting lives, so you know which scope a new setting belongs to.

## Scopes

A setting has one scope. Pick the narrowest scope that matches what the person would expect.

| Scope | Where | Settings |
| --- | --- | --- |
| Every window | One key in the defaults. | `listDensity`, `openItemsIn` (where an item opens: `modal`, `fullPage` or `newWindow`), `dateFormat`, `noteSort`, `groupsByDate`, the page options in `PageKey` (`titleLines`, `linkLook`, `fullWidthPages`, `showsCoordinates` and others), `remotePictures`, the interface options in `InterfaceKey`. |
| A type | One value keyed by type identifier. | `pagePlacements` (pins, shown rows, property order, sidebar sections, where Linked From goes), `includedSubtypes`. |
| A saved view | One value keyed by the view's item identifier. | `viewLayouts`: a `ViewMacSettings` with the layout, columns, whether the board hides empty groups, the gallery's cards, the calendar's Week or Month choice, the list's density and the table's widths. A place's own calendar choice is kept in `placeDefaults`. |
| A place | A key built from the place. | `placeDefaults` (the default view of a place that is not a saved view: its filters, sort, grouping, layout, timeline date, compact board, gallery cards and calendar scale), `itemTableColumns` (the table's columns for each place), `placeDensities` (the density of a place that is not a saved view), `indexTab.<place>` and `indexSort.<place>` (an index page's tab and the order of its table). |
| A server | One value keyed by server address. | `sidebarLayouts`: for each server, the hidden places, their order, the tabs, the sections of each tab with their shortcuts, where a place sits when it was moved to another section, and the color of each view's mark; and `typeLooks`: the looks chosen for its types. |
| A window | Scene storage, or memory only. | The layout in `SceneStorage("browser")`, `detailsPresented` and `sidebarHidden`. |

Column widths are `interfaceDefaultWidth.<column>`, and the right sidebar's width and open sections are `inspectorWidth` and the `inspector*Open` keys.

## Rules

The rules that apply to every setting are in the `AGENTS.md` files: [that today nothing goes to Marfa](../AGENTS.md), [how a saved view's Mac settings are kept and forgotten](../MAPP/Model/AGENTS.md), and [how a Debug build keeps its own values](../AGENTS.md). Three more belong to this page.

- **A type's setting has little inheritance.** `pagePlacements` for a child type does not read its parent's. A look does: it follows the `parent` chain, place by place; see [Looks](looks.md).
- **Unreadable stored text is set aside, not dropped.** When a stored value cannot be decoded, MAPP keeps the text under a `...SetAside` key (`pagePlacementsSetAside`, `viewLayoutsSetAside`, `sidebarLayoutsSetAside`, `typeLooksSetAside`, `placeDensitiesSetAside`, `placeDefaultsSetAside`, `itemTableColumnsSetAside`) and starts from the defaults, so a person's arrangement can be recovered.
- **A new field on a stored value is optional.** A value saved before the field existed must still decode.

## The Settings window

Where it lives: `SettingsWindowView`, `SettingsPage`, `SettingsNavigation`, `SettingsLauncher`, `SettingsSidebar`, `SettingsTokens` and `MarfaSettingsHost`, under `MAPP/Settings/`.

Settings is a window of its own, opened by MAPP > Settings… (⌘,), with one instance that comes forward if it is already open and keeps the size it was left at (1200 by 900 points at first). It is a `Window` scene, not the system's `Settings` scene, which is sized to its content for a few tabs and gives no toolbar of ours or remembered, resizable frame. Every route that opens Settings names a page in the same window: the command, the sidebar's Settings shortcut, the palette's Settings commands, the connect and sign-in buttons, and the notices that offer Settings (`SettingsLauncher`). The main window keeps no Settings place, and no Settings column or width.

The sidebar lists MAPP's pages, then the Marfa's: Appearance, Editor, Lists and Connection; then Overview and Recently Deleted. A page is listed once it is built, so the pages in [Agreed designs](agreed-designs.md#settings) that are not here yet (General, Keyboard, Layouts, Search, On This Mac, and the Marfa's other pages) appear as they are. Settings > Sidebar and Settings > About are gone: the sidebar is customized in place, and About is the MAPP menu's About MAPP.

- **Appearance, Editor and Lists** hold what the old pages held, with the same keys in the defaults. Appearance has no Settings column width.
- **Connection** is the old Library page: the server and how it stands, each change that needs the person, the sign-in, the other server, the downloaded files, the error reports switch and Disconnect.
- **Overview** holds This Marfa's fields until the page is built out, and **Recently Deleted** the bin. Both are the Marfa's: each needs an owner permission (`config.manage` and `items.purge`), which the sign-in holds only if the owner approved it. Allow More… signs in again through the package, asking for MAPP's scopes, the permissions already held and the page's own, and hands the new sign-in to the open copy as Sign In Again does. Signing in again keeps the permissions already held.
- **The Marfa's half** (`Settings/Marfa/`) reaches MAPP only through `MarfaSettingsHost`, so another app could take its pages.

The measurements of a page's rows and boxes are in [Views and lists](views-and-lists.md#settings). The agreed pages not built yet are in [Agreed designs](agreed-designs.md#settings).

## Looks

`typeLooks` holds only what was chosen for a type, place by place, as sorted-key JSON; every other look is worked out from the type's fields. It replaces the type styles, which are gone with no migration. A density is not part of a look: it is kept in `viewLayouts` for a saved view and in `placeDensities` for a place, and an old row choice (`listRowStyle` and the other row keys) is not read. Export Looks and Import Looks move a server's looks as a file. It is agreed that looks move with the rest of MAPP's settings into the Marfa, as Layouts rows per type ([Agreed designs](agreed-designs.md#settings)); until that is built they stay on this Mac. See [Looks](looks.md).

## Related pages

- [Looks](looks.md)
- [Marfa and MAPP](marfa-and-mapp.md)
- [Views and lists](views-and-lists.md)
