# Settings storage

Each Mac keeps its own window sizes and positions, column widths, global shortcuts, and On This Mac settings. The connected Marfa holds the app settings shared by its Macs. See [Looks](looks.md).

Where it lives: `ListKey`, `PageKey`, `OrderKey`, `InterfaceKey` and `AppearanceKey` under `MarfaMac/Views/`, and `MacSettings`, `StartWith`, `ReopenWindows`, `NewItemType`, `NewRowTypes`, `WeekStart`, `CalendarHourHeight`, `PagePlacements`, `ViewLayouts`, `PlaceDefaults`, `Density`, `SidebarLayouts`, `TypeLooks`, `IncludedSubtypes`, `SearchLeaveOuts`, `SearchOptions`, `DateFormat` and `RemotePictureSetting` under `MarfaMac/Model/`, `ShortcutBindings` and `AnyAppShortcuts` under `MarfaMac/Model/Shortcuts/`, and `PreferencesType`, `PreferencesMap`, `PreferencesMerge`, `PreferencesSync`, `PreferencesCopy`, `SettingsFile`, `RestorePoints` and `ConnectionSettings` under `MarfaMac/Model/Marfa/`.

This app's settings have three homes. A setting belongs in the narrowest one that matches what the person would expect.

## The three homes

| Home | What it holds | Where |
| --- | --- | --- |
| The Marfa's own data | Items, types, views, the sign-in's grants. Never an app setting. | The Marfa. |
| This app's settings | Every setting that should follow the person to another Mac. | One hidden item per Marfa, of type `app.marfa-mac.preferences`. |
| This Mac only | Window sizes and positions, column widths, the shortcuts that work in any app, On This Mac, the connection and the sync's own bookkeeping. | The defaults on this Mac. |

The defaults on this Mac stay the store the app's code reads, so a launch reads nothing from the network and `@AppStorage` keeps working. Where the settings sync, the defaults are this Mac's copy of the Marfa's settings, and `PreferencesSync` keeps the two together.

## This app's settings in the Marfa

`app.marfa-mac.preferences` is hidden: the library never lists it as an item, and Marfa stores and syncs it without reading it. It has five fields, each an `object` keyed by the app's defaults key, and five tables, each with the columns `key`, `setting` and `value` (the value is the JSON text the app stores).

| Place | Keys |
| --- | --- |
| `appearance` field | `theme`, `accentColor`, `highlightColor`, `textFont`, `codeFont`, `interfaceTextSize`, `valuePanelStyle`, `paletteMaterial`, `showsScrolledTitle`, `showsPageToolbarBackground`, `showsSidebarHistory`, `toolbarLabelStyle`, `sidebarSubtypeIcons` |
| `general` field | `dateFormat`, `weekStart`, `startWith`, `newItemType`, `openItemsIn`, `remotePictures` |
| `editor` field | every `PageKey`, and `sourceViewMode` |
| `lists` field | `listDensity`, `showsQuickAddOptions`, `calendarHourHeight`, `indexNewTypes`, `noteSort`, `groupsByDate` |
| `search` field | `searchIncludesArchived`, `searchIncludesInbox`, `searchOrder`, `searchShowsSnippets`, and this server's entry of `searchLeaveOuts` |
| `commands` table | `keyboardShortcuts` (one row per command) |
| `types` table | `pagePlacements`, this server's `typeLooks`, `includedSubtypes` |
| `views` table | `viewLayouts`, without the table's widths |
| `places` table | `placeDefaults`, `placeDensities`, `indexTab.<place>`, `indexSort.<place>` |
| `sidebar` table | this server's `sidebarLayouts`: the `hidden`, `order`, `collapsed`, `tabs` and `groups` lists, a `home` row for each placed place and a `color` row for each mark |

A mark's color and a place's section change one at a time, so each is its own row that two Macs can change apart. The sidebar's lists say where many things sit relative to each other, so each list is one row and the later arrangement wins whole. `hidden` and `collapsed` are sets, written sorted, so saving again never looks like a change.

`PreferencesMap` is the one table of where each key goes and which keys stay on this Mac, and a test checks that every key in `MacSettings.keys` is in exactly one of the two. A new setting is added to `PreferencesMap` in the change that adds it.

### The type's shape never changes

Every Mac is another OAuth client to the server, and only the client that registered the first type under `app.marfa-mac` may replace it (withmarfa/marfa#3462). A later copy of the app could not change the type, so a new setting is a new member inside a field or a new `setting` word in a table, never a new field, table or column. `PreferencesTypeTests` fails on any change to the definition.

### The scope the app asks for

Every sign-in asks for `app.*:write`, never `app.marfa-mac.*:write`, and never both. This grants read and write access to every app's types. The vendor scope is unavailable before its first type exists, and discovery never lists it afterward. Together with `metadata.types:write`, the app root lets the first Mac register its settings type and later Macs reach its items. withmarfa/marfa#3522 would let the app ask for its vendor alone.

## What stays on this Mac

Window sizes and positions (`interfaceDefaultWidth.*`, `inspectorWidth`, the `inspector*Open` keys, `inspectorAppOpen.*`, window scene storage), a table's column widths (`itemTableColumns`), the shortcuts that work in any app (`anyAppShortcuts`), `startLastPlace`, `quickAddLastType`, `sendErrorReports`, `betaVersions`, `NSQuitAlwaysKeepsWindows`, everything on On This Mac, the `Marfa*` connection keys, the sync's own key `preferencesSync` and the restore points.

The shortcuts that work in any app are not synced, but a settings file and a restore point carry them. A Marfa that holds them from an earlier version keeps those rows, and the sync neither reads nor deletes them.

## The first launch

Nothing is decided until the hydration is complete, the sign-in reaches the type and every table is held whole; until then the defaults stay as they are and Connection says the settings are not ready.

- **The sign-in lacks the permission** (a sign-in made before the settings synced holds neither `app.*:write` nor `metadata.types:write`): nothing syncs, the defaults are untouched and Connection offers Allow More….
- **Before the first write or adoption**, and before switching Marfa, this Mac's settings are saved as a restore point ([Restore points, export and import](#restore-points-export-and-import)). If the point can't be saved, the step changes nothing, the failure is logged, and the next step tries again.
- **The Marfa holds no item, and this Mac never adopted a Marfa:** the item is made from this Mac's settings.
- **The Marfa holds no item, and this Mac adopted another Marfa before:** the synced settings go back to the app's defaults and an empty item is made, so a new Marfa does not take another's arrangement.
- **The item exists:** what it holds wins, and what it lacks is filled from this Mac, once. The adoption is recorded for the Marfa's instance.
- **Two items** (two Macs made one at once): the one created first is used and what it lacks is filled from the other. The other stays hidden until Remove… bins every settings item.
- **Switching Marfa** loads the other Marfa's settings into the defaults whole, and switching back loads the first Marfa's again.

## A change on one Mac reaching another

One step compares this Mac's settings and the item's with what both held after the last step. A change on this Mac is written to the item, and a change from another Mac is written into the defaults, after which the observable stores read them again and open windows follow. A change on this Mac waits one second, so a slider's drag is one write, and the sync asks the library to send it at once, so another Mac sees it without waiting for the next connection. Nothing is written for what was just applied, so there is no echo.

Fields are written by member. Where two Macs change different members, both changes stand; where the server keeps another Mac's member and writes this Mac's to a conflicted copy, the app writes the members it sent again, takes the members the other Mac changed, and bins the copy.

## Two Macs changing one setting

The later write wins, row by row and member by member, and nothing is lost: each table keeps a change log. To put a batch back, undo it from the command line with `marfa rows undo <item> <table> <batch>`; undoing the undo redoes it. Row ids are a hash of the table, the setting and the key, so two Macs writing one setting write one row.

## Unreadable settings

- **A Marfa row whose value is not JSON** is set aside once under its store's `...SetAside` key and is never deleted from the Marfa by this Mac. A value the defaults can't keep, such as one with `null` inside it, is skipped the same way: every value is checked before it is written (`SyncedSetting.write`), and this Mac keeps what it held there.
- **Stored text this Mac cannot read** is neither sent nor written over. A stored value of another kind than its store keeps, such as text where the store keeps data, counts as unreadable.
- **A store's older value** that no longer decodes (`pagePlacementsSetAside`, `viewLayoutsSetAside`, `sidebarLayoutsSetAside`, `typeLooksSetAside`, `placeDensitiesSetAside`, `placeDefaultsSetAside`, `itemTableColumnsSetAside`, `searchLeaveOutsSetAside`, `keyboardShortcutsSetAside`, `anyAppShortcutsSetAside`, `dateFormatSetAside`) is kept under that key and the store starts from its defaults, so a person's arrangement can be recovered. An older Date Format value that no longer reads is set aside the same way at launch and never translated.
- **A new field on a stored value is optional.** A value saved before the field existed must still decode.

## Connection's This App's Settings section

Settings > Connection shows where the settings are kept, in the state the sync is in (`ConnectionSettings`):

- **Syncing:** "Kept in <name>. Every Mac that connects to it uses them." with Remove….
- **Needs a permission:** "Kept on This Mac Only", saying the app isn't allowed to keep them in the Marfa yet, with Allow More…. After the sign-in is approved the section moves to Syncing without a relaunch.
- **Not filled yet:** a quiet line while the copy downloads, with no button.
- **Removed** (here or on another Mac): "Kept on This Mac Only", saying they were removed and this Mac keeps its own, with Keep in Marfa Again.
- **No Marfa** (the sample library): the section is not shown.

A footer names what stays on each Mac. Remove… asks first, saying every Mac that connects loses the settings and this Mac keeps its own. It moves the item to the bin and nothing is written again until Keep in Marfa Again. The bin keeps hidden items out of Recently Deleted, so the owner restores one from the command line.

### Disconnect

Disconnect's alert has a checkbox, "Also remove this app's settings from <name>", off by default and offered only while the settings are kept in the Marfa. Checked, the app removes the item and waits until the server has taken that removal, judged by its own write and no other, before it signs out, since afterwards nothing can be removed. If the removal fails, the app says so, stays connected, and disconnects only if the person chooses Disconnect Anyway; the checkbox is then offered only if the settings are still kept. The question about changes that wait (the Departure sheet) has the same checkbox, and nothing is removed until the person has chosen how to leave the copy. Sending the removal sends the whole queue, so the checkbox goes with Keep Copy only: Discard Changes is off while it is checked, and a removal asked for with a discard is refused, never sent, so a change the person chose to discard never reaches the server. A removal that was queued and not taken counts among the changes that wait; the sheet says one of them removes this app's settings from the Marfa, and that discarding the copy leaves the settings there.

## Reset

Settings > General > Reset This App's Settings… saves a restore point first. If the save fails, the app tells the person and stops. Otherwise, Reset clears the keys in `MacSettings.keys` and `MacSettings.prefixes`, including each app's inspector state. Clearing the app's `NSQuitAlwaysKeepsWindows` override makes Reopen Windows follow the system setting again. The sample library uses the same key lists for a clean start.

`Libraries.resetMacSettings` reloads the settings stores, so menus, global shortcuts, and open windows reflect the reset immediately; if a sync step is under way, Reset waits for it to end first. When settings sync, the confirmation alert explains that Reset affects every Mac connected to this Marfa. The sync groups changed fields in one item update and changed rows in one batch per table. Reset preserves the library copy, its queue, the sign-in, the connection, the sync record, and values in `...SetAside` keys.

## Restore points, export and import

A restore point is this app's settings as they were before something replaced many of them. The app saves one before the first sync, before taking another Mac's settings, before Reset, before Import, before switching Marfa and before restoring, each titled for its reason, such as "Before Reset". Nothing is replaced until its point is saved. Points are files in `Restore Points` in the app's Application Support folder, so they stay on this Mac; the newest ten are kept. A point with the same reason and settings as the newest one is not saved again, so a step that tries again leaves one point. A point that can't be read is left out of the list. The unit tests and previews keep points of their own, each in a temporary folder removed with it, and the sample library keeps its points beside its copy and clears them at launch with it.

A point is the app's own defaults themselves (`SettingsSnapshot`): every key in `MacSettings.keys` and the keys that come one for each app's inspector, each value as a binary property list (base64 in the file), with the reason and the date, so a date, data or a number JSON can't hold comes back as it was. If a value can't be kept, the point isn't saved and nothing is replaced. A point reads only the app's own domain, never a value the defaults inherit, such as the system's `NSQuitAlwaysKeepsWindows`, so a restore never makes a system setting the app's own. It holds every Marfa's entry of a setting kept for each server, the settings that stay on this Mac, and a stored value its store can't read, so it puts back exactly what was replaced.

A settings file (`SettingsFile`) groups settings into General, Appearance, Keyboard, Editor, Lists, Layouts, Search, and Sidebar. The JSON file identifies its format as `marfa-mac-settings`, version 1. Each value uses the same JSON text as the sync. For settings kept by server, the file carries the connected Marfa's entry, or this Mac's entry when disconnected. Export omits unreadable settings. Keyboard includes global shortcuts.

- **Export** includes each section that has stored values.
- **Import** reads a file and replaces each chosen section whole: a setting of the section that the file lacks goes back to its default, and the other sections are untouched. A file that is not the app's, or comes from a later version, is refused and changes nothing. Every value is checked before any is written; one the setting can't store is skipped and counted. A stored value in a chosen section that this Mac can't read is set aside under its `...SetAside` key before it is written over. A shortcut that works in any app that the system won't register, because another app holds the keys, is kept and counted as skipped, judged by what the system holds after the stores read the defaults again.
- **Restore** puts back exactly the keys a point holds and removes the ones it lacks, after checking every value and saving a point of its own, so the restore can be undone.

Import, Restore and Reset run between sync steps: steps stop, a step under way ends first, and a step runs after, so no step writes what it read before over them. After each, the stores read the defaults again, so the open windows and the shortcuts follow at once. Where the settings sync, each setting they wrote is marked in the sync's bookkeeping (`preferencesSync`) and wins at the next step for every Mac, even over another Mac's change this Mac has not taken; a value Import skipped is left out of its setting's mark, since it is what this Mac held. The marks survive a relaunch. A setting's mark clears once the write that carries it is queued, with the record of what it carried, so if a later write of the step is refused, only what that write carried is sent again; a switch of Marfa clears them too. With no Marfa connected, they change this Mac only. If the point before them can't be saved, they change nothing and say so.

## Rules

The rules that apply to every setting are in the `AGENTS.md` files: [what syncs and what stays](../AGENTS.md), [how a saved view's Mac settings are kept and forgotten](../MarfaMac/Model/AGENTS.md), and [how a Debug build keeps its own values](../AGENTS.md).

- **A type's setting has little inheritance.** `pagePlacements` for a child type does not read its parent's. A look does: it follows the `parent` chain, place by place; see [Looks](looks.md).
- **A setting has one place.** A key is in `PreferencesMap` as synced or as staying on this Mac, never both.

## The Settings window

Where it lives: `SettingsWindowView`, `SettingsPage`, `SettingsNavigation`, `SettingsLauncher`, `SettingsSidebar`, `SettingsTokens` and `MarfaSettingsHost`, under `MarfaMac/Settings/`.

Settings is a window of its own, opened by Marfa > Settings… (⌘,), with one instance that comes forward if it is already open and keeps the size it was left at (1200 by 900 points at first). It is a `Window` scene, not the system's `Settings` scene, which is sized to its content for a few tabs and gives no toolbar of ours or remembered, resizable frame. Every route that opens Settings names a page in the same window: the command, the sidebar's Settings shortcut, the palette's Settings commands, the connect and sign-in buttons, and the notices that offer Settings (`SettingsLauncher`). The main window keeps no Settings place, and no Settings column or width.

The sidebar names its two halves App and Marfa. App lists General, Appearance, Keyboard, Editor, Lists, Layouts, Search, On This Mac and Connection; Marfa lists the pages that [The Marfa's half of Settings](marfa-settings.md) lists. A page is listed once it is built, so the pages in [Agreed designs](agreed-designs.md#settings) that are not here yet appear as they are. Settings > Sidebar and Settings > About are gone: the sidebar is customized in place, and About is Marfa > About Marfa.

- **General, Appearance, Editor, Lists and Layouts** are in [Settings](settings.md). Appearance has no Settings column width.
- **Search, On This Mac and Connection** are in [Settings](settings.md). Connection holds the server and how it stands, the account, each change that needs the person, this app's Settings, the other server and Disconnect; the downloaded files moved to On This Mac and the error reports switch to General.
- **Keyboard** holds the shortcut of every menu command and the few that work in any app ([Keyboard shortcuts](keyboard-shortcuts.md)).
- **Overview** requires `instance.read`. Changing the name in This Marfa requires `config.manage`. **Recently Deleted** requires `items.purge`. Allow More… signs in again through the package and gives the new sign-in to the open copy. Browser and code sign-in both request all app-grantable owner permissions. See [Permissions in Settings](marfa-settings.md#rules).
- **The Marfa's half** (`Settings/Marfa/`) reaches the app only through `MarfaSettingsHost`, so another app could take its pages.

The measurements of a page's rows and boxes are in [Views and lists](views-and-lists.md#settings). The agreed pages not built yet are in [Agreed designs](agreed-designs.md#settings).

## Looks

`typeLooks` holds only what was chosen for a type, place by place, as sorted-key JSON; every other look is worked out from the type's fields. It replaces the type styles, which are gone with no migration. A density is not part of a look: it is kept in `viewLayouts` for a saved view and in `placeDensities` for a place, and an old row choice (`listRowStyle` and the other row keys) is not read. Settings > Layouts changes them type by type, and Export Layouts and Import Layouts move a server's looks as a file. Looks sync with the rest, as rows of the `types` table. See [Looks](looks.md).

## Related pages

- [Keyboard shortcuts](keyboard-shortcuts.md)
- [Looks](looks.md)
- [Marfa and the app](marfa-and-the-mac-app.md)
- [Views and lists](views-and-lists.md)
