# Settings pages

Status: General and Appearance are built. The other pages are in [Agreed designs](agreed-designs.md#settings) until they are built.

Where it lives: `GeneralPage`, `AppearancePage`, `StartWith`, `ReopenWindows`, `NewItemType`, `WeekStart`, `DateFormat`, `DateDisplay`, `MissingChoice`, `MacSettings`, `AppTheme`, `AccentChoice`, `HighlightChoice` and `FontChoice`, under `MAPP/Settings/`, `MAPP/Model/` and `MAPP/Views/`.

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

## Related pages

- [Agreed designs](agreed-designs.md#settings)
- [Settings storage](settings-storage.md)
- [Views and lists](views-and-lists.md)
- [Item page](item-page.md)
