# Agreed designs, not built yet

Status: Agreed, not built. Each design is drawn on MAPP Pages, and the MAPP design system holds its components. When a design is built, move its section to the page for its area and delete it here.

Where it lives: not built yet.

This page lists what has been agreed for MAPP and is not in the app yet, so the next build starts from one list. What was turned down is in [Rejected designs](rejected-designs.md).

## Editing in place

What is not built yet. The built part is in [Value components](value-components.md) and [Item page](item-page.md).

- A status's value panel ends with Edit Statuses, which opens the type in Settings > Types. Settings > Types does not exist yet.
- A field's menu has Edit the type in Settings, which opens the same page, and waits for it too.
- Renaming a choice word is left out. A rename that carried the values to the new word is not in Marfa's contract, so the items that hold the old word would keep a word the type no longer lists. Choices can be added, reordered and taken out; a taken-out choice stays on the items that hold it.
- An empty In Collection row for an item in no collection. Add to Collection from the menu, the toolbar and the palette reaches it, and the page's own row appears once the item is in one.

## Pages

- Where a code block's language goes, and how it changes, is open. It stays as it is.

## Settings

Agreed with August on 19 and 20 November 2026. The pages are drawn on the Settings tab of MAPP Pages, and the design system holds every part (`SettingsWindow` and the components it uses). This section lists the rules and what each page holds. In the copy below, `<Marfa>` stands for the Marfa's own name.

### General rules

- **A window of its own.** Settings opens in its own window, not as a place in the main window's sidebar, so the Marfa's pages can one day stand alone as their own app. One sidebar lists MAPP's pages, then the Marfa's, in groups split by space, each page with a color tile, and a search field at the top. The content is a column at most 620 points wide, with more room either side as the window widens.
- **The toolbar carries the page's name** beside Back and Forward. There is no back button beside a title.
- **Rows.** A row is a lead, a title with one line under it (two at most), and one trailing edge. Rows are 44 points, 56 with a line, 36 for a list of words. Every input is 200 by 28 and ends on the same line. Leads sit in one 24-point column, so text starts at 52 and the divider at the text.
- **Sections.** Every section is named; a thing's head card is the one exception. Cards are white with a hairline, never gray.
- **Changing things.** A list of words or patterns is changed in place (double-click or Return edits a line; Add a Name or Pattern adds one; order is shown where it matters). Something new with several fields is a sheet. Sheets and alerts sit in the middle of the window, not under the toolbar. Apple's alert asks before what can't be undone. A thing with settings of its own is a page.
- **Numbers.** A field with its unit inside, or a pop-up of sensible steps, then Custom, where steps guide the person.
- **Problems and errors.** A problem row offers only actions that exist: Ignore and Edit… where both do, one button and a menu where there are more. An error uses the design system's red: a ring and one line under the title, never more.
- **Buttons are gray**, the confirm button too. Blue is only for Update and for an alert's default button, unless that button is destructive, which macOS draws as it does today. Focus is a gray ring.
- **One button size.** Every button in Settings is 28 points, except inside a table, where row buttons stay small. No button sits in a section's header.
  - Adding something is the card's last row: + New Key…, + Add a Passkey…, + New Webhook…, + New Type…, + Add a Field….
  - Other actions are regular buttons in a row: Last Backup with Back Up Now, and Check for Updates beside Update.
  - The button rows under a card (Restore Defaults…, Export Shortcuts…, Import…) are regular size.
  - Select All is an "All Events" checkbox row.
- **Shortcuts.** Keyboard lists every command in a white shortcut field with a clear button, with a small search at the top right of the list and Restore Defaults… at the end. A keyboard button beside the search field searches by pressing: while it is on, pressing keys finds that shortcut (⌘K finds Command Palette), and typing searches by name.
- **Tables.** In a section, the filter pop-up and the search sit together at the trailing edge of the section's name, and Show All is in the table's foot beside the count ("8 of 1,204"). A table that is a page of its own has its count on the left and the filter and search together on the right, in one row under the toolbar, and fills the pane with columns, selection and actions at the foot. A section's table is light, with no rules between rows, a page at a time. A table's row action (Restore…, Restore) shows on every row, never only on the row under the pointer.
- **Words.** "Permanently Delete", never "for good".
- **A synced folder's page** shows what it holds as a tree of its folders, counted in files, which MAPP builds from the server's paths.
- **Themes later.** Every color and font is a named value, never hard-coded, so custom themes can come later without rework. Custom CSS, plugins, AI providers and Vim keys are not planned.

### MAPP's pages

Nine pages in three groups: General, Appearance and Keyboard; Editor, Lists, Layouts and Search; On This Mac and Connection. There is no Advanced page, and Settings > Sidebar stays gone.

- **General.**
  - Start With, and Reopen Windows after quitting.
  - Open Items In (moved from Lists), and New Items Are.
  - Today and Yesterday (moved from Lists), Week Starts On, Date Format and Time Format.
  - Pictures from Websites and Send Error Reports.
  - Reset MAPP's Settings… at the foot, with an alert.
- **Appearance.**
  - Theme, Accent with a custom color, and the Highlights color.
  - Text Font (any installed font) and Code Font (any monospaced font). The interface stays the system font.
  - Text Size, the materials and scrolling switches, and Symbols on Subtypes.
  - Window Layout: the column widths, with Use Current Widths and Reset.
- **Keyboard.**
  - Every menu command can be changed.
  - A section of shortcuts that work in any app while MAPP is running, all off by default: Show Command Palette, Search and New Item. Each must include ⌘ or ⌃.
  - Export Shortcuts… and Import Shortcuts….
- **Editor.**
  - Page Width, Standard Width, Line Spacing, Paragraph Spacing, Title Length, Links to Items and Articles Open In.
  - Editing Mode: Formatted or Markdown Source.
  - Typing: Pair Brackets and Quotes, Continue Lists, Smart Quotes and Dashes, Check Spelling, and Indent With tabs or spaces.
  - Pasting: Markdown or plain text.
  - Display: Fold Headings, and Line Numbers in code blocks.
  - Some of these need Inkkit to add them first: Pair Brackets, Fold Headings, Line Numbers in code blocks, Indent With, Continue Lists in source mode, and a paste default.
- **Lists.** Density, Dates, Sort and Group. Nothing about types or sources is left out here: Items, Inbox and Recents are only the views a library starts with, and leaving things out belongs to Search.
- **Layouts** (the name people see; it replaces "Rows and Cards" and "Looks"). One place for how each type looks. A type's page has Preview, Row (date, secondary line, color), Facts, Card (picture, facts on cards) and Page (pinned properties, the same as Customize Layout on an item), with Restore Defaults. Export and Import are on the list. The code keeps its names (`TypeLooks`, [Looks](looks.md)); only what people see is renamed.
- **Search.**
  - Leave Out of Search, by type and by source. It is MAPP's own setting, applied inside the search.
  - Include Archived Items and Include Inbox Items.
  - Results in Best Match or Most Recent order, and Show Snippets.
  - Search Items itself stays as it is, and passes its Type and Source filters into the search, so nothing is lost to the 500-hit cut.
- **On This Mac.** The copy of the library MAPP keeps on this Mac: the space it uses, opened files (a size budget and Remove Downloaded Files), export to a folder, and download everything again. "Recent files only" is not offered.
- **Connection.** As drawn, plus the "MAPP's Settings" section described under sync below.

### The Marfa's pages

Only the agreed changes are listed. A change marked "needs a server change" waits on Marfa first.

- **Webhooks.** Every app's, grouped by the app that made them. The owner can end any of them (needs a server change).
- **A key.** Extend… beside the expiry date, for the owner. The secret keeps working (needs a server change).
- **Account.**
  - Change Password…, Add Passkey… (opens the server's own page) and the passkey list. Sign-Ins is folded in as Browsers.
  - MAPP asks for the `sign_ins.manage` permission the first time the owner chooses Change Password (Allow More…), not at every sign-in.
  - Passkeys stay in the system's sign-in sheet.
- **Start-Up.** Stays, read-only.
- **Names.** Monitoring (was Reporting) and Limits (new).
- **Updates.**
  - Check for Updates sits beside Update on every Updates page.
  - A failed update that was put back reads "The update to 0.0.85 didn't work. <Marfa> is back on 0.0.84, as before. Nothing was lost." with Try Again and no second Update button.
  - Last Update rows read "Updated to 0.0.84", or "Tried 0.0.85" with why it was undone (Undone).
  - A backup folder row has a folder symbol.
- **Housekeeping.**
  - The problem row says "Clean-up is paused" and "<Marfa>'s clock jumped to 3 March 2027.", with Confirm Date….
  - The jobs table has Job, Every, Last Run and Result (Done, Paused), with the contract's intervals (version thinning hourly, file copying every minute, reading new files every 30 seconds), and no Run Now.
  - The alert asks "Is it 3 March 2027?" and says "<Marfa>'s clock says so. If it's right, clean-up starts again." Its buttons are Cancel and Confirm Date (blue).
  - Only jobs that delete pause, once the clock runs more than 7 days past the last trusted time.
- **Plugins, Connectors and Types** are drawn and agreed separately, and wait on server work.

### Settings sync through Marfa

Agreed, not built. It needs Marfa to keep `app.*` items hidden and to that app first.

- **One hidden item per Marfa.** MAPP's own settings move into `app.mapp.preferences`, which only MAPP and the owner read. Marfa stores and syncs it and never interprets it.
- **Its shape.** Fields hold settings that come once (Appearance, General, Editor, Lists, Search). Table rows hold those per command (shortcuts), per type (Layouts), per saved view, per place and per sidebar entry.
- **What stays on each Mac.** Window sizes and positions, column widths and On This Mac.
- **A second Mac** that connects to the same Marfa picks the settings up.
- **Two Macs changing one setting.** The later write wins, row by row, and can be undone from the table's log.
- **Connection** gets a section "MAPP's Settings" ("Kept in <Marfa>. Every Mac that connects to it uses them.") with Remove…, and a footer naming what stays on each Mac. The Disconnect alert has a checkbox, "Also remove MAPP's settings from <Marfa>", off by default.
- **Export and Import** may stay, to copy settings between two Marfas.
- **The owner** can see and remove the settings in Settings and from the command line, and backups include them.
- Until this is built, the scopes in [Settings storage](settings-storage.md) stand.

## Still open

- A cover picture on an item's page, and how Marfa would hold the choice of cover. It is parked.
- How the corner's controls are drawn on pages for each kind of item, such as a newsletter at its own width.
- A full-screen view beside Focus. Not now.

## Related pages

- [Rejected designs](rejected-designs.md)
- [Views and lists](views-and-lists.md)
- [Item page](item-page.md)
- [Components](components.md)
- [Settings storage](settings-storage.md)
- [Value components](value-components.md)
