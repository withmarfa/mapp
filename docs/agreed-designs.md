# Agreed designs, not built yet

Status: Agreed, not built. Each design is drawn on MAPP Pages, and the MAPP design system holds its components. When a design is built, move its section to the page for its area and delete it here.

Where it lives: not built yet.

This page lists what has been agreed for MAPP and is not in the app yet, so the next build starts from one list. What was turned down is in [Rejected designs](rejected-designs.md).

## Editing in place

What is not built yet. The built part is in [Value components](value-components.md) and [Item page](item-page.md).

- A field's menu has Edit the type in Settings, which opens a type's page in Settings > Types. The page is built (see [The Marfa's half of Settings](marfa-settings.md)); the menu row is not.
- Renaming a choice word is left out. A rename that carried the values to the new word is not in Marfa's contract, so the items that hold the old word would keep a word the type no longer lists. Choices can be added, reordered and taken out; a taken-out choice stays on the items that hold it.
- An empty In Collection row for an item in no collection. Add to Collection from the menu, the toolbar and the palette reaches it, and the page's own row appears once the item is in one.

## Grouping, Properties and filters

Agreed with August on 21 November 2026, drawn as the Next boards of MAPP Pages. The rules are in [Views and lists](views-and-lists.md#grouping-properties-and-filters); this is the list of what is not built. Filters for every field kind, relative dates, All or Any and the "is not" rewrite are built, not yet released.

- **Grouping by Collection and Tags** in a list and a table, an item in each of its groups.
- **A bucket's groups following the sort** where the view sorts by that date.
- **A saved view keeps Set or Not Set and the status groups** once Marfa can hold them. Until then Save as View names them under Not Saved in the View.
- **Dragging a board's lanes** to reorder them, which would write the group order Edit View writes.
- **Built, not yet released:** one Properties list for a view or place, shared by every layout, replacing the table's Columns and falling back to each type's look; Edit Layouts… in the window, opening Settings > Layouts at the type; the timeline's row as agreed; filters for every field kind; All or Any in the filter row; and relative dates in filters, kept only on this Mac.
- **Fixes:** MAPP keeping another app's group order and hidden groups, a board's cards following the sort, and no Sort on the timeline or the calendar are built, not yet released.

## Buttons

Agreed with August on 22 November 2026 (MAPP Pages, Foundations F7 to F10; the design system's Button, PopUp and Settings components). The rule is in [Components](components.md#buttons); this is what the build changes.

- **`MappButtonStyle`:** the corner radius follows the size, a capsule at 28 points and 7-point corners at the small size, which grows from 22 to 24 points. Keyboard focus follows the shape.
- **Pop-up and menu buttons** are gray with no outline: two arrows for a value, one for a menu of commands.
- **Symbols:** a gray circle on its own, such as More (…) and Add (+) at a row's end; plain on a header row and inside a banner, the toast or a chip. A symbol scales with its button's size and is never semibold, the menu chevron included.
- **Search fields** are the system's: white, with a hairline edge, a capsule.
- **Tabs** on an index page are a choice of one: the chosen tab is a capsule.
- **Settings:** a section's filter pop-up and search are 28 points, the filter plain. Inputs at a row's end are 160 points wide. A row's trailing edge holds one control, except a problem row's two buttons; a value it acts on goes in the row's line. A number's unit sits after its field. Rows with a mark get their own section. Show All in a table's footer has no fill. A sheet's confirm button is blue.
- **First run:** each step's one action is 36 points, a capsule.

## Pages

- Where a code block's language goes, and how it changes, is open. It stays as it is.


## Settings

Agreed with August on 19 and 20 November 2026. The pages are drawn on the Settings tab of MAPP Pages, and the design system holds every part (`SettingsWindow` and the components it uses). This section lists the rules and what each page holds. In the copy below, `<Marfa>` stands for the Marfa's own name.

### General rules

The rules that are built (the window, the toolbar, rows, sections, changing things, numbers, problems and errors, buttons, tables, words and named values) are in [Views and lists](views-and-lists.md#settings). One is not built yet:

- **A synced folder's page** shows what it holds as a tree of its folders, counted in files, which MAPP builds from the server's paths. Not built: the package's client offers no call for a folder's settings or paths (see [The Marfa's half of Settings](marfa-settings.md#left-out)).
- **Not now:** custom CSS, plugins for MAPP itself, AI providers and Vim keys. Themes come later; every color and font is already a named value.

### MAPP's pages

Nine pages in three groups: General, Appearance and Keyboard; Editor, Lists, Layouts and Search; On This Mac and Connection. There is no Advanced page, and Settings > Sidebar stays gone.

- **General and Appearance** are built: see [Settings pages](settings.md).
- **Keyboard** is built: see [Keyboard shortcuts](keyboard-shortcuts.md).
- **Editor, Lists and Layouts** are built: see [Settings pages](settings.md).
- **Search, On This Mac and Connection** are built: see [Settings pages](settings.md). Agreed but not built: On This Mac's **Export Automatically** ("To a folder you choose", with Never as the default), a row in the Export section under Export Everything. MAPP has no scheduler, and keeping a chosen folder across launches needs a saved folder permission that MAPP does not keep yet. Connection gets the "MAPP's Settings" section described under sync below once that is built.

### The Marfa's pages

Only the agreed changes are listed. A change marked "needs a server change" waits on Marfa first.

- **Built:** Overview, Account, Apps, Keys (with Extend… beside the expiry date, which keeps the secret), Addresses, Plugins (installed, updates, available and removal; a plugin that carries guidance installs from the command line), Sources, Recently Deleted, History, File Storage, Connectors (each connector's health, Pause, Run Now, settings, vendor sign-in and each kind's mapping with a live preview; adding one waits), Webhooks (every app's, grouped by who made them, any of which the owner can end), a read-only Folders, Backups, Updates, Housekeeping, Activity, Monitoring (was Reporting), Limits (new) and Start-Up (read-only) are in [The Marfa's half of Settings](marfa-settings.md).
- **Types** is built: see [The Marfa's half of Settings](marfa-settings.md). An owner's type's Fields, Feed, History and Delete Type, and a field's own page, are built too. Still agreed and not built on it: Strict and Keep Versions among a type's rules (Strict is an instance setting that needs `config.manage`, and Keep Versions has four numbers with no agreed control), and writing Guidance (waits for August's decision on whether an app may write it).
- **Connectors** are built except adding a connector and the Files row of its mapping.

### Settings sync through Marfa

Built: MAPP's settings are kept in one hidden item per Marfa, shown and removed in Connection's MAPP's Settings section, and removed with the Disconnect alert's checkbox. [Settings storage](settings-storage.md) says what is true. Export and Import of settings between two Marfas are not built.

## Still open

- A cover picture on an item's page, and how Marfa would hold the choice of cover. It is parked.
- How the corner's controls are drawn on pages for each kind of item beyond those above, such as a newsletter at its own width.
- A switch that turns pinned properties off everywhere. August has not decided.
- A full-screen view beside Focus. Not now.

## Related pages

- [Rejected designs](rejected-designs.md)
- [Views and lists](views-and-lists.md)
- [Item page](item-page.md)
- [Components](components.md)
- [Settings storage](settings-storage.md)
- [Value components](value-components.md)
