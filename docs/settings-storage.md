# Settings storage

Status: Built in v0.0.43. The store of type looks and the list density are built in v0.0.44. See [Looks](looks.md).

Where it lives: `ListKey`, `PageKey`, `OrderKey`, `InterfaceKey` and `AppearanceKey` under `MAPP/Views/`, and `MacSettings`, `StartWith`, `ReopenWindows`, `NewItemType`, `WeekStart`, `CalendarHourHeight`, `PagePlacements`, `ViewLayouts`, `PlaceDefaults`, `Density`, `SidebarLayouts`, `TypeLooks`, `IncludedSubtypes`, `SearchLeaveOuts`, `SearchOptions`, `DateFormat` and `RemotePictureSetting` under `MAPP/Model/`, and `ShortcutBindings` and `AnyAppShortcuts` under `MAPP/Model/Shortcuts/`.

MAPP keeps its own settings in the app's defaults on this Mac today. It is agreed that they move into one hidden item in the Marfa, `app.mapp.preferences`, with window sizes, column widths and On This Mac staying on the Mac ([Agreed designs](agreed-designs.md#settings)). Until that is built, the scopes below stand. This page lists where each kind of setting lives, so you know which scope a new setting belongs to.

## Scopes

A setting has one scope. Pick the narrowest scope that matches what the person would expect.

| Scope | Where | Settings |
| --- | --- | --- |
| Every window | One key in the defaults. | `listDensity`, `openItemsIn` (where an item opens: `modal`, `fullPage` or `newWindow`), `dateFormat` (one JSON value: whether lists and tables say Today and Yesterday, the date style and the clock), `weekStart` (a weekday, or none for the system's), `calendarHourHeight` (how tall an hour is in the calendar's week, in points from 24 to 160, set by a pinch on the trackpad), `startWith` and `startLastPlace`, `NSQuitAlwaysKeepsWindows` (Reopen Windows: unset, the Mac's own answer stands), `newItemType`, `indexNewTypes` (the types on the Items page's New row, as type identifiers in order, absent until the row is edited), `theme`, `accentColor`, `highlightColor`, `textFont`, `codeFont`, `sidebarSubtypeIcons`, `noteSort`, `groupsByDate`, `searchIncludesArchived`, `searchIncludesInbox`, `searchOrder` and `searchShowsSnippets` (Settings > Search, in `SearchOptions`), the page options in `PageKey` (`titleLines`, `linkLook`, `fullWidthPages`, `showsCoordinates` and others), the Editor page's `lineSpacing`, `paragraphSpacing`, `editingMode`, `indentWith`, `pasteAs`, `smartPunctuation`, `pairsBrackets`, `continuesLists`, `foldsHeadings` and `showsCodeLineNumbers` (with `sourceViewMode`, which Articles Open In sets), `remotePictures`, the interface options in `InterfaceKey`. |
| A type | One value keyed by type identifier. | `pagePlacements` (pins, shown rows, property order, sidebar sections, where Linked From goes), `includedSubtypes`. |
| A saved view | One value keyed by the view's item identifier. | `viewLayouts`: a `ViewMacSettings` with the layout, columns, whether the board hides empty groups, the gallery's cards, the calendar's Week or Month choice, the list's density and the table's widths. A place's own calendar choice is kept in `placeDefaults`. |
| A place | A key built from the place. | `placeDefaults` (the default view of a place that is not a saved view: its filters, sort, grouping, layout, timeline date, compact board, gallery cards and calendar scale), `itemTableColumns` (the table's columns for each place), `placeDensities` (the density of a place that is not a saved view), `indexTab.<place>` and `indexSort.<place>` (an index page's tab and the order of its table). |
| Every window, on this Mac | One key in the defaults, shared by every server. | `keyboardShortcuts`: the shortcut chosen for each menu command, kept only where it differs from the command's default; `anyAppShortcuts`: the shortcuts that work in any app, off until set. See [Keyboard shortcuts](keyboard-shortcuts.md). |
| A server | One value keyed by server address. | `sidebarLayouts`: for each server, the hidden places, their order, the tabs, the sections of each tab with their shortcuts, where a place sits when it was moved to another section, and the color of each view's mark; `typeLooks`: the looks chosen for its types; and `searchLeaveOuts`: the types and sources left out of search (a type takes its subtypes with it). |
| A window | Scene storage, or memory only. | The layout in `SceneStorage("browser")`, `detailsPresented` and `sidebarHidden`. |

Column widths are `interfaceDefaultWidth.<column>`, and the right sidebar's width and open sections are `inspectorWidth` and the `inspector*Open` keys.

## Reset

Settings > General > Reset MAPP's Settings… clears every key in `MacSettings.keys`, and the keys that come one for each app's inspector, and so removes MAPP's own `NSQuitAlwaysKeepsWindows`, which puts Reopen Windows back to the Mac's answer. It leaves the copy of the library, its queue, the sign-in, the connection (the server's address and its names) and any value set aside under a `...SetAside` key. The shortcuts held in memory are put back with it (`Libraries.resetMacSettings`), so the menus and the hot keys follow at once. One list holds the keys, which the Reset and the sample library's clean start both read: a new setting stored on this Mac is added to `MacSettings.keys` in the same change, and a test checks that each group of keys is in it.

## Rules

The rules that apply to every setting are in the `AGENTS.md` files: [that today nothing goes to Marfa](../AGENTS.md), [how a saved view's Mac settings are kept and forgotten](../MAPP/Model/AGENTS.md), and [how a Debug build keeps its own values](../AGENTS.md). Three more belong to this page.

- **A type's setting has little inheritance.** `pagePlacements` for a child type does not read its parent's. A look does: it follows the `parent` chain, place by place; see [Looks](looks.md).
- **Unreadable stored text is set aside, not dropped.** When a stored value cannot be decoded, MAPP keeps the text under a `...SetAside` key (`pagePlacementsSetAside`, `viewLayoutsSetAside`, `sidebarLayoutsSetAside`, `typeLooksSetAside`, `placeDensitiesSetAside`, `placeDefaultsSetAside`, `itemTableColumnsSetAside`, `searchLeaveOutsSetAside`, `keyboardShortcutsSetAside`, `anyAppShortcutsSetAside`, `dateFormatSetAside`) and starts from the defaults, so a person's arrangement can be recovered. An older Date Format value that no longer reads (`automatic`, `relative`, a word this version lacks) is set aside the same way at launch and never translated.
- **A new field on a stored value is optional.** A value saved before the field existed must still decode.

## The Settings window

Where it lives: `SettingsWindowView`, `SettingsPage`, `SettingsNavigation`, `SettingsLauncher`, `SettingsSidebar`, `SettingsTokens` and `MarfaSettingsHost`, under `MAPP/Settings/`.

Settings is a window of its own, opened by MAPP > Settings… (⌘,), with one instance that comes forward if it is already open and keeps the size it was left at (1200 by 900 points at first). It is a `Window` scene, not the system's `Settings` scene, which is sized to its content for a few tabs and gives no toolbar of ours or remembered, resizable frame. Every route that opens Settings names a page in the same window: the command, the sidebar's Settings shortcut, the palette's Settings commands, the connect and sign-in buttons, and the notices that offer Settings (`SettingsLauncher`). The main window keeps no Settings place, and no Settings column or width.

The sidebar lists MAPP's pages, then the Marfa's: General, Appearance, Keyboard, Editor, Lists, Layouts, Search, On This Mac and Connection; then the Marfa's pages, which [The Marfa's half of Settings](marfa-settings.md) lists. A page is listed once it is built, so the pages in [Agreed designs](agreed-designs.md#settings) that are not here yet appear as they are. Settings > Sidebar and Settings > About are gone: the sidebar is customized in place, and About is the MAPP menu's About MAPP.

- **General, Appearance, Editor, Lists and Layouts** are in [Settings](settings.md). Appearance has no Settings column width.
- **Search, On This Mac and Connection** are in [Settings](settings.md). Connection holds the server and how it stands, the account, each change that needs the person, the other server and Disconnect; the downloaded files moved to On This Mac and the error reports switch to General.
- **Keyboard** holds the shortcut of every menu command and the few that work in any app ([Keyboard shortcuts](keyboard-shortcuts.md)).
- **Overview** holds This Marfa's fields until the page is built out, and **Recently Deleted** the bin. Both are the Marfa's: each needs an owner permission (`config.manage` and `items.purge`), which the sign-in holds only if the owner approved it. Allow More… signs in again through the package, asking for MAPP's scopes, the permissions already held and the page's own, and hands the new sign-in to the open copy as Sign In Again does. Every sign-in again, by the browser or with a code, asks for the permissions already held, or for every permission the pages use where the Keychain cannot say what is held. The owner may untick permissions on the approval page, and that stands, but never silently: when a permission held before is no longer held, MAPP says so in one notice that names what it is no longer allowed to do, and the page that asked shows Needs a Permission again.
- **The Marfa's half** (`Settings/Marfa/`) reaches MAPP only through `MarfaSettingsHost`, so another app could take its pages.

The measurements of a page's rows and boxes are in [Views and lists](views-and-lists.md#settings). The agreed pages not built yet are in [Agreed designs](agreed-designs.md#settings).

## Looks

`typeLooks` holds only what was chosen for a type, place by place, as sorted-key JSON; every other look is worked out from the type's fields. It replaces the type styles, which are gone with no migration. A density is not part of a look: it is kept in `viewLayouts` for a saved view and in `placeDensities` for a place, and an old row choice (`listRowStyle` and the other row keys) is not read. Settings > Layouts changes them type by type, and Export Layouts and Import Layouts move a server's looks as a file. It is agreed that looks move with the rest of MAPP's settings into the Marfa, as Layouts rows per type ([Agreed designs](agreed-designs.md#settings)); until that is built they stay on this Mac. See [Looks](looks.md).

## Related pages

- [Keyboard shortcuts](keyboard-shortcuts.md)
- [Looks](looks.md)
- [Marfa and MAPP](marfa-and-mapp.md)
- [Views and lists](views-and-lists.md)
