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

- **Webhooks.** Every app's, grouped by the app that made them. The owner can end any of them (needs a server change). The page that lists MAPP's own webhooks is built.
- **A key.** Extend… beside the expiry date, for the owner. The secret keeps working (needs a server change).
- **Built:** Overview, Account, Apps, Keys, Addresses, Sources, Recently Deleted, History, File Storage, Webhooks, a read-only Folders, Backups, Updates, Housekeeping, Activity, Monitoring (was Reporting), Limits (new) and Start-Up (read-only) are in [The Marfa's half of Settings](marfa-settings.md).
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
