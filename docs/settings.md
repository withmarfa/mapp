# Settings pages

Status: General, Appearance, Editor, Lists, Layouts, Search, On This Mac and Connection are built. The other pages are in [Agreed designs](agreed-designs.md#settings) until they are built.

Where it lives: `GeneralPage`, `SettingsFilesModel`, `ImportSettingsSheet`, `RestoreSettingsSheet`, `AppearancePage`, `EditorPage`, `ListsPage`, `LayoutsPage`, `LayoutTypePage`, `LayoutChoices`, `EditorOptions`, `LineSpacing`, `ParagraphSpacing`, `IndentWith`, `PasteAs`, `EditingMode`, `StartWith`, `ReopenWindows`, `NewItemType`, `WeekStart`, `DateFormat`, `DateDisplay`, `MissingChoice`, `MacSettings`, `AppUpdater`, `UpdateSettings`, `AppTheme`, `AccentChoice`, `HighlightChoice`, `FontChoice`, `MarfaMac/Settings/`, `MarfaMac/Model/`, `MarfaMac/Views/`, `SearchPage`, `SearchOptions`, `SearchLeaveOutList`, `OnThisMacPage`, `LibraryExport`, `StoreSize`, `ConnectionPage`, `ConnectionStanding` and `ConnectionAccount`.

Every setting here is kept in the defaults on this Mac, and synced through the connected Marfa except what stays on each Mac ([Settings storage](settings-storage.md)).

## General

- **Opening.**
  - Start With is what a window with nothing to restore shows: Where I Left Off (the place a window was last in), Inbox, Recents, All Items, Favorites or one of the library's types. A window that comes back with the app keeps what it showed.
  - Reopen Windows says whether the windows that were open come back after the app quits. It follows the Mac until the person changes it: unset, the row shows the system's own answer (`NSQuitAlwaysKeepsWindows`, the inverse of "Close windows when quitting an application") and the app writes nothing. Only a change of the row writes the app's own `NSQuitAlwaysKeepsWindows`, and Reset removes it, so the Mac's answer stands again.
  - Open Items is where an item opens from a list or a search: Over the List, Full Page or New Window ([Opening an item](views-and-lists.md#opening-an-item)).
- **New Items.** New Items Are is the kind a new item takes outside a type's own list and the Collections and Files places: Last Used, or a kind from the catalogue that can be made. A kind the server no longer offers gives way to the last used one.
- **Dates and Times.**
  - Today and Yesterday makes lists and tables say Today, Yesterday, Tomorrow and the weekday for a recent day, instead of its date. A value read by itself (a property, the inspector, a version) is always a date.
  - Week Starts On is System Setting or a day. Every calendar and date panel the app draws starts its week there (`Calendar.chosenWeekStart`).
  - Date Format is System Setting, Numeric (27/10/2026), Abbreviated (27 Oct 2026) or Long (27 October 2026), and Time Format is System Setting, 12-Hour or 24-Hour. They apply wherever the app writes a date or a time, as a person reads it: lists, tables, the inspector, the calendar's hour gutter and its blocks, the timeline's Now marker and day heading, the date panel's time field and quick dates, a collection's Created and Updated, and the dates the Settings pages show. A time typed in the date panel reads back in either clock. A calendar's month and day names are not dates in this sense and follow the language only. System Setting keeps each place's own way, in the Mac's formats. An event's header is laid out in the event's own zone and ignores them.
- **Privacy.** Pictures from Websites (Ask, Always or Never) and Send Error Reports. The second shows only in a build that carries a place to send reports to.
- **Updates.** Check Automatically (once a day) and Beta Versions, which also offers release candidates. The section shows only in a build that carries an update feed and key, which is a release build; it has the app menu's Check for Updates… beside it.
- **This App's Settings.** One section with four rows, in this order. Each button ends in an ellipsis, since each opens a panel, a sheet or a question.
  - Export Settings… opens a save panel (`Marfa Settings.json`) and writes every setting as a settings file ([Restore points, export and import](settings-storage.md#restore-points-export-and-import)). A file that can't be written is told in a notice.
  - Import Settings… opens a panel for a JSON file. A file that is not a settings file, one from a newer version of the app, one with no settings in it and one that can't be read are each told in a notice, and nothing changes. A good file opens a sheet with a box for each section the file holds, all ticked: a section the file lacks is not offered, since importing it would put it back to its defaults. Under the boxes it says that the import changes these settings on every Mac connected to the Marfa (by its name), or on this Mac only where they don't sync, and that a restore point is saved first. Cancel and Import, which takes Return and is off while no box is ticked. A notice then says how many settings were applied and how many were skipped. If the restore point can't be saved, nothing changes and the notice says so.
  - Restore Earlier Settings… opens a sheet of the restore points, newest first, each with what it was saved before and its date, such as "Before Reset" and "23 Nov 14:02" (day, abbreviated month and time, in the Mac's language and clock). The points are a single-selection list, since one is chosen: none is selected at first, and Restore (Return) is off until one is. The sheet says the same as Import about who it reaches and the restore point. The row is dimmed, with "None saved yet." as its line, while there are no points. A notice says what was applied, as Import does.
  - Reset This App's Settings… asks first with an alert; Cancel changes nothing. The alert says a restore point is saved first and Restore Earlier Settings brings it back. Reset saves the point, then resets every setting the app keeps, in the Marfa too where they sync, and leaves the copy, the queue, the sign-in and the connection alone ([Reset](settings-storage.md#reset)).

## Appearance

- **Theme** is System, Light or Dark, chosen from three small pictures. It sets the whole app's appearance.
- **Color.**
  - Accent is the system's accent, one of the eight colors System Settings offers (Blue, Purple, Pink, Red, Orange, Yellow, Green and Graphite, as the Mac itself resolves each in the light and the dark appearance), or a color of the person's own made with the system's color panel. It tints the app's controls and the item page's accent. It is stored as a name, or as `#RRGGBB`.
  - Highlights is the color behind highlighted text on an item's page: Yellow (the page's own), Orange, Green, Blue, Pink, Purple or the accent.
- **Text.** Text Size is the size of the sidebar, lists and controls. The item page's own text size is in Editor.
- **Fonts.** Text Font is any installed font for an item's text, and Code Font any installed monospaced font for code. The interface stays the system font. The installed fonts are listed when the page appears, never before. A font chosen and later uninstalled is shown as "<name> (Missing)" in its pop-up, and the page and the editor use the default meanwhile. A place or a type chosen in Start With or New Items Are that the library no longer has reads the same way, and the app falls back as it did. They reach the page as `--inkkit-font-family` and `--inkkit-monospace-font`.
- **Materials.** Value Panels and Palettes: Glass, Solid, and Translucent for palettes.
- **Window.** Back and Forward over the sidebar, Title When Scrolling and Toolbar Background When Scrolling (both for an item's page), and Symbols on Subtypes in the sidebar.
- **Window Layout.** Where the sidebar and the list start in a new window, with From This Window: Reset puts the built-in widths back, and Use Current Widths keeps the widths of the front window.

## Editor

Every Editor setting reaches a page that is already open. The ones that are Inkkit's go to the page as one set (`EditorOptions`, sent with `window.editor.setOptions`), since each of Inkkit's two calls replaces its whole set; see [Editor page](../editor/AGENTS.md).

- **Text.** Text Size (the item's own text; the interface's is in Appearance), Line Spacing and Paragraph Spacing (Tight, Standard or Relaxed, as multiples of the text size: 1.4, 1.55 and 1.8 for lines, one third, two thirds and one for paragraphs), and Links to Items (how a link to another item looks: Mark, Underline, Tinted Pill, Pill, Quiet or Text; a link to an item that doesn't exist keeps its dashed line in every look).
- **Page.** Page Width (Standard or Full Width), Standard Width (dimmed under Full Width) and Title Length (up to 2 to 5 lines before an ellipsis).
- **Page Corner.** Formats (Aa), Text Size and Focus, each on by default, choose which of these controls show at the bottom right of an item's page (`PageCornerChoice`). A control turned off is in the page's More menu instead (Show Formats, a Text Size submenu holding the sizes and widths, Focus), and the View menu keeps every command either way. The corner's other controls (Reader or Original, a PDF's page, an image's or PDF's size) belong to the page they are for and are not a choice.
- **Editing.** Edit Pages As is the mode a page opens in, Formatted or Markdown Source. It applies to an item opened, never to the page already shown, which keeps the mode its Format menu switched it to. Articles Open In is Reader or Original, and a web page opens in Original until the person chooses otherwise; the last choice, from this setting or from View > Show Reader or Original, is kept for every article.
- **Typing.** Check Spelling While Typing, Smart Quotes and Dashes (formatted text; off until turned on), Pair Brackets and Quotes (off), Continue Lists on Return (on, in formatted text and Markdown source) and Indent With (a tab, or 2, 4 or 8 spaces, in Markdown source). Indent With always sends both a kind and a width, since Tab indents in the source only once the kind is set.
- **Pasting.** Paste Formatted Text As is Markdown (formatted, the default) or Plain Text, which inserts what is pasted exactly as typed in every mode.
- **Display.** Fold Headings (a triangle beside each heading hides what follows) and Line Numbers in Code.

## Lists

Density (Standard or Compact, chosen from two previews side by side, each half the card wide and made of sample rows of several types drawn by the real list row: the type's mark in its color, a title, the line under it and the date, with a sample picture on the first Standard row; the chosen one has a ring) is what every list takes until a saved view or a place chooses its own. Sort By and Group By are the starting order of a place's list, until its own Sort by or Group by is chosen in View Options, which the place then keeps in its default view ([One Sort by and Group by for a place](views-and-lists.md#one-sort-by-and-group-by-for-a-place)); the section's line says so. Group By is dimmed while the sort is by title. **Items Page** holds Show Quick Add Options, off until turned on: it shows the Items page's New tiles ([Views and lists](views-and-lists.md)), and with it off the toolbar's Edit and the View menu's Edit New Row… are absent too. It syncs with the rest (`showsQuickAddOptions`). Lists has no setting to leave types or sources out: that belongs to Search. Open Items and Today and Yesterday are in General.

## Layouts

One page for how each type looks: a list of every type of the connected server (the ones its owner made first, then the built-in ones), each opening that type's page, with Import… and Export… under it. A page that is not connected shows no types. Layouts is the name people see; the code keeps its names ([Looks](looks.md), `TypeLooks`).

A type's page is pushed on the list and Back returns to it. It has:

- **Preview.** Up to two real items of the type, drawn as a list draws them, which follow every change below. A type with no items has none.
- **Row.** Date (a date field of the type, Created, Edited, Happened or None) and Secondary Line (up to two of: the opening line, a field, a date field's time of day, a website, a file's kind and size, or the parent). A place offers only what the type can fill.
- **Facts.** The values after the status, in the order a row shows them (a row shows the first two). Each has a menu to move it up or down or remove it, a handle to drag it by, and the last row adds one from what the type offers.
- **Page.** What the item's page pins under its title (at most four), in order, the same choice as Customize Layout on an item of the type (`PagePlacements`). The last row pins another property.
- **Restore Defaults** takes back that type's choices, for its look and for its page, and no other type's.

Edit Layouts… in the window (View Options > Properties, Edit View's Properties section and the row menu) opens this page at a type. Built, not yet released.

Every change is written to the store that already holds it (`TypeLooks` for the row, `PagePlacements` for the page), so a list, a card, a table and an item's page see it at once. Only what differs from what the type's preset gives is kept, as an import keeps it, so a better preset still reaches every place nobody chose. Nothing is written to Marfa.

Not built: the board's Color row (a type's color comes from its icon, which the server holds), its Card section (a card's facts come from the view's Properties list, which falls back to this page's Facts; see [Properties](views-and-lists.md#properties)) and Show in Types (waits for the Types page).

## Search

- **Left Out of Search** lists the types and sources this server leaves out. They still show in their own place, in views and in Favorites. It is the app's own setting for this server (`SearchLeaveOuts`), applied inside the search call. A type left out takes its subtypes with it, and they are listed under it as left out too. "Leave Out a Type or Source…" is a menu of the types and sources not yet left out, A to Z as the list is; a type with subtypes says so ("Notes, with 2 subtypes"), and two types with one name are told apart in the menu and in the list ("Tasks (Tickets)"). A search holds at most ten conditions, and each type left out counts once for itself and once for each subtype below it, each source once, so the menu dims every type and source that would cross ten, and a footer under the card says why while any is dimmed. A source the server no longer lists is kept, shown as unknown, and can be removed.
- **It applies to every search across the whole library**: Search Items, and the items ⌘K matches by title. Both end with "N more in what is left out" and Show, which searches once with nothing left out. A search inside one place or list leaves nothing out, since the person chose that place. Collection and Updated in Search Items still narrow after the 500 results, since the filter grammar has no parentheses.
- **Include.** Archived Items and Inbox Items are on by default. Off, they are asked of the copy in the search call itself (`ItemQuery.states` is active only, `ItemQuery.tier` is the library tier), so the most a search lists is counted after them. The Inbox is the feed tier.
- **Results.** Order is Best Match, as the copy ranked them, or Most Recent, by when each was last edited; the sort runs on the up to 500 the copy answered, then the first 50 are listed. Show Snippets off gives Search Items one line to a row, with no words around the match.

## On This Mac

- **The head** says how much room the copy of this library takes: every file in its store folder, which the app sums itself, since the package reports downloaded files only. It sums when the page opens, after a step on the page, when a download ends and then about every 30 seconds while the page stays open.
- **Files.** Keep Opened Files is the size the downloaded files may reach (Automatic, a size, or Keep All Downloads). Attachments are always kept so they open offline, and are counted; "Attachments Not Yet Offline" counts the rest and gives the reason as its line ("Waiting to download.", or each reason with its count where there are several). Opened Files shows their size, and Clear fetches again only what is needed: it keeps attachments and files waiting to upload. There is no "recent files only".
- **Export Everything** asks for a folder and writes the server's whole archive there (`GET /export`, as an archive with files), named after the server and the day. It needs the server; it is written beside its name and moved into place only once whole, and a failure says so in one line and leaves no file.
- **Not built.** Export Automatically, a schedule that exports to a folder the person chose, is in [Agreed designs](agreed-designs.md#settings): the app has no scheduler, and keeping a chosen folder across launches needs a saved folder permission that the app does not keep yet.
- **Download Everything Again** asks first, then hydrates the copy again from the server. Changes not yet sent stay in the queue and are sent afterwards; the queue is never cleared. While it downloads, the row shows the progress in place of its usual line and the button is off.

## Connection

- **The head** names the server and how it stands: Connected with how long ago it was up to date, Not Answering with Try Again, or Sign In… and Use a Code Instead… once the server has ended the sign-in. A copy that stopped shows no download progress.
- **Account.** Signed In As shows the owner's name when the sign-in has the profile name read scope. Look After This Marfa shows how many of the 14 owner permissions the sign-in holds. Its Allow More… button is offered while the sign-in lacks anything a sign-in asks for (an owner permission, the profile name read scope or a scope added since) and requests it all again. Unsent Changes shows what waits to be sent. Problems that need your attention follow Account.
- **Other Marfas** and **Disconnect** follow every rule of [Marfa library](../MarfaMac/Model/Marfa/AGENTS.md): the queue is read in the same step, and the Departure sheet asks about changes that wait. Disconnect asks first with an alert: "The app removes its copy from this Mac and signs out. Webhooks it made are deleted. Your items stay." The server deletes the webhooks an app made when its sign-in ends (`events/webhook-grant-revoked`).
- **This App's Settings** follows Account, and Disconnect's alert has the checkbox "Also remove this app's settings from <Marfa>", off by default ([Settings storage](settings-storage.md#connections-this-apps-settings-section)).
- **Not built.** The state after the sign-in address changed (a head that says where the server moved to) is not built: the app cannot learn the new address.

## Related pages

- [Agreed designs](agreed-designs.md#settings)
- [Settings storage](settings-storage.md)
- [Views and lists](views-and-lists.md)
- [Item page](item-page.md)
