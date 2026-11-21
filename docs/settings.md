# Settings pages

Status: General, Appearance, Search, On This Mac and Connection are built. The other pages are in [Agreed designs](agreed-designs.md#settings) until they are built.

Where it lives: `GeneralPage`, `AppearancePage`, `StartWith`, `ReopenWindows`, `NewItemType`, `WeekStart`, `DateFormat`, `DateDisplay`, `MissingChoice`, `MacSettings`, `SearchPage`, `SearchOptions`, `SearchLeaveOutList`, `OnThisMacPage`, `LibraryExport`, `StoreSize`, `ConnectionPage`, `ConnectionStanding`, `ConnectionAccount`, `AppTheme`, `AccentChoice`, `HighlightChoice` and `FontChoice`, under `MAPP/Settings/`, `MAPP/Model/` and `MAPP/Views/`.

Every setting here is a Mac setting, kept in the defaults and never written to Marfa ([Settings storage](settings-storage.md)).

## General

- **Opening.**
  - Start With is what a window with nothing to restore shows: Where I Left Off (the place a window was last in), Inbox, Recents, All Items, Favorites or one of the library's types. A window that comes back with the app keeps what it showed.
  - Reopen Windows says whether the windows that were open come back after MAPP quits. It follows the Mac until the person changes it: unset, the row shows the system's own answer (`NSQuitAlwaysKeepsWindows`, the inverse of "Close windows when quitting an application") and MAPP writes nothing. Only a change of the row writes MAPP's own `NSQuitAlwaysKeepsWindows`, and Reset removes it, so the Mac's answer stands again.
  - Open Items is where an item opens from a list or a search: Over the List, Full Page or New Window ([Opening an item](views-and-lists.md#opening-an-item)).
- **New Items.** New Items Are is the kind a new item takes outside a type's own list and the Collections and Files places: Last Used, or a kind from the catalogue that can be made. A kind the server no longer offers gives way to the last used one.
- **Dates and Times.**
  - Today and Yesterday makes lists and tables say Today, Yesterday, Tomorrow and the weekday for a recent day, instead of its date. A value read by itself (a property, the inspector, a version) is always a date.
  - Week Starts On is System Setting or a day. Every calendar and date panel MAPP draws starts its week there (`Calendar.mapp`).
  - Date Format is System Setting, Numeric (27/10/2026), Abbreviated (27 Oct 2026) or Long (27 October 2026), and Time Format is System Setting, 12-Hour or 24-Hour. They apply wherever MAPP writes a date or a time, as a person reads it: lists, tables, the inspector, the calendar's hour gutter and its blocks, the timeline's Now marker and day heading, the date panel's time field and quick dates, a collection's Created and Updated, and the dates the Settings pages show. A time typed in the date panel reads back in either clock. A calendar's month and day names are not dates in this sense and follow the language only. System Setting keeps each place's own way, in the Mac's formats. An event's header is laid out in the event's own zone and ignores them.
- **Privacy.** Pictures from Websites (Ask, Always or Never) and Send Error Reports. The second shows only in a build that carries a place to send reports to.
- **Reset.** Reset MAPP's Settings… asks first with an alert; Cancel changes nothing. It resets every setting MAPP keeps on this Mac and leaves the copy, the queue, the sign-in and the connection alone ([Reset](settings-storage.md#reset)).

## Appearance

- **Theme** is System, Light or Dark, chosen from three small pictures. It sets the whole app's appearance.
- **Color.**
  - Accent is the system's accent, one of the eight colors System Settings offers (Blue, Purple, Pink, Red, Orange, Yellow, Green and Graphite, as the Mac itself resolves each in the light and the dark appearance), or a color of the person's own made with the system's color panel. It tints MAPP's controls and the item page's accent. It is stored as a name, or as `#RRGGBB`.
  - Highlights is the color behind highlighted text on an item's page: Yellow (the page's own), Orange, Green, Blue, Pink, Purple or the accent.
- **Text.** Text Size is the size of the sidebar, lists and controls. The item page's own text size is in Editor.
- **Fonts.** Text Font is any installed font for an item's text, and Code Font any installed monospaced font for code. The interface stays the system font. The installed fonts are listed when the page appears, never before. A font chosen and later uninstalled is shown as "<name> (Missing)" in its pop-up, and the page and the editor use the default meanwhile. A place or a type chosen in Start With or New Items Are that the library no longer has reads the same way, and the app falls back as it did. They reach the page as `--inkkit-font-family` and `--inkkit-monospace-font`.
- **Materials.** Value Panels and Palettes: Glass, Solid, and Translucent for palettes.
- **Window.** Title When Scrolling and Toolbar Background When Scrolling (both for an item's page), and Symbols on Subtypes in the sidebar.
- **Window Layout.** Where the sidebar and the list start in a new window, with From This Window: Reset puts the built-in widths back, and Use Current Widths keeps the widths of the front window.

## Search

- **Left Out of Search** lists the types and sources this server leaves out. They still show in their own place, in views and in Favorites. It is MAPP's own setting for this server (`SearchLeaveOuts`), applied inside the search call. A type left out takes its subtypes with it, and they are listed under it as left out too. "Leave Out a Type or Source…" is a menu of the types and sources not yet left out. A search holds at most ten conditions, and each type left out counts once for itself and once for each subtype below it, each source once, so the menu turns off what would cross ten and says so in one line. A source the server no longer lists is kept, shown as unknown, and can be removed.
- **It applies to every search across the whole library**: Search Items, and the items ⌘K matches by title. Both end with "N more in what is left out" and Show, which searches once with nothing left out. A search inside one place or list leaves nothing out, since the person chose that place. Collection and Updated in Search Items still narrow after the 500 results, since the filter grammar has no parentheses.
- **Include.** Archived Items and Inbox Items are on by default. Off, they are asked of the copy in the search call itself (`ItemQuery.states` is active only, `ItemQuery.tier` is the library tier), so the most a search lists is counted after them. The Inbox is the feed tier.
- **Results.** Order is Best Match, as the copy ranked them, or Most Recent, by when each was last edited; the sort runs on the up to 500 the copy answered, then the first 50 are listed. Show Snippets off gives Search Items one line to a row, with no words around the match.

## On This Mac

- **The head** says how much room the copy of this library takes: every file in its store folder, which MAPP sums itself, since the package reports downloaded files only. It sums when the page opens, after a step on the page, when a download ends and then about every 30 seconds while the page stays open.
- **Files.** Keep Opened Files is the size the downloaded files may reach (Automatic, a size, or Keep All Downloads). Attachments are always kept so they open offline, and are counted, with the ones not yet offline and why. Opened Files shows their size, and Clear fetches again only what is needed: it keeps attachments and files waiting to upload. There is no "recent files only".
- **Export Everything** asks for a folder and writes the server's whole archive there (`GET /export`, as an archive with files), named after the server and the day. It needs the server; it is written beside its name and moved into place only once whole, and a failure says so in one line and leaves no file.
- **Download Everything Again** asks first, then hydrates the copy again from the server. Changes not yet sent stay in the queue and are sent afterwards; the queue is never cleared. While it downloads, the row shows the progress in place of its usual line and the button is off.

## Connection

- **The head** names the server and how it stands: Connected with how long ago it was up to date, Not Answering with Try Again, or Sign In… and Use a Code Instead… once the server has ended the sign-in. A copy that stopped shows no download progress.
- **Account.** Signed In As (the owner's name, which the server tells only to a sign-in that holds the profile name read scope: MAPP asks for it at sign-in, and a Mac signed in before that shows it after Allow More… or Sign In Again, where the row offers Allow More… until then), Look After This Marfa ("MAPP holds N of the owner's 14 permissions" with Allow More…, or All 14, counted as a key's and an app's pages count them) and Unsent Changes. Allow More… asks for every permission not held, `sign_ins.manage` included, which is never asked at sign-in. Problems, the changes that need the person, follow Account.
- **Other Marfas** and **Disconnect** follow every rule of [Marfa library](../MAPP/Model/Marfa/AGENTS.md): the queue is read in the same step, and the Departure sheet asks about changes that wait. Disconnect asks first with an alert.
- **Not built.** The section "MAPP's Settings" and the alert's "Also remove MAPP's settings" wait for settings to sync through Marfa ([Agreed designs](agreed-designs.md#settings-sync-through-marfa)). The state after the sign-in address changed (a head that says where the server moved to) is not built: MAPP cannot learn the new address.

## Related pages

- [Agreed designs](agreed-designs.md#settings)
- [Settings storage](settings-storage.md)
- [Views and lists](views-and-lists.md)
- [Item page](item-page.md)
