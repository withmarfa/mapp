---
summary: Where each of this app's settings is kept, how they reach another Mac, and how they are put back.
paths:
  - MarfaMac/Model/Marfa/Preferences/*.swift
  - MarfaMac/Model/Marfa/ConnectionSettings.swift
  - MarfaMac/Model/MacSettings.swift
  - MarfaMac/Settings/App/SettingsFiles.swift
  - MarfaMac/Settings/App/RestoreSheet.swift
---

# Where settings are kept

## Three homes

| Home | What it holds |
| --- | --- |
| The Marfa's own data | Items, types, views and the sign-in's grants. Never an app setting |
| This app's settings | Settings that follow the person to another Mac, such as New Opens |
| This Mac only | Widths, last place, playback places, recent kinds, New Item's tags and parents, any-app shortcuts, error-report consent, export plans |

- **Give each setting one home**, the narrowest a person would expect. Add its key to `MacSettings.keys` and `PreferencesMap` together. Tests check coverage.
- **The app reads the defaults**, so launch needs no network.
- **Store only what a person chose.** A default value is left out, so a better default reaches them.
- **A new member of a stored value is optional**, so older values decode.
- **A library's own settings are named by its Marfa,** else its copy's folder. `LibrarySettings` moves earlier names' first; losers go to `Restore Points/Library Settings Set Aside/`, unreadable or undecided stay unsynced.

## In the Marfa

- **One hidden item per Marfa holds the settings** (`PreferencesType`) in five object fields and five tables.
- **The type can never change shape.** Only the client that registered it may replace it, and every Mac is another client (withmarfa/marfa#3462). A new setting is a new member of a field or a new `setting` word in a table.
- **Different settings change independently**, by field member or table row. An ordered list occupies one row, so the later arrangement wins whole.
- **A set is written sorted**, so saving it again is not a change.
- **A hidden view is its own row, kept when shown again:** a row this Mac lacks of a `PreferencesMap.keptWhereAbsent` setting is taken, not deleted.
- **What is kept for a place is keyed by its word** (`PlaceView.storageKey`), and for a saved view by its id, as its place can change; an earlier copy's keys are never removed (`EarlierPlace`).
- **An earlier copy drops unknown members** from a row it rewrites. For example, it may drop `digest` from `viewLayout` or `placeDefaults`. It reads an unknown layout as List.
- **A sign-in asks for `app.*:write`, never the app's own vendor scope**, because discovery lists no vendor scope before its first type exists (withmarfa/marfa#3522).

## Groups you can keep on this Mac

Settings > General > Sync with This Marfa has nine switches, all on by default. Each choice belongs to one Mac and one Marfa instance.

With a group off, edits, removals, imports and restores stay local. Other Macs can still change the shared values.

Turning a group on requires a restore point. If saving fails, it stays off. Once the copy is whole, the Marfa's values win and local values fill gaps once. Settings files and restore points exclude the switches. Reset clears them and preserves remote values for groups previously off.

## The first launch against a Marfa

- **Settings sync checks the copy first.** Hydration must be complete, the sign-in must reach the type, and every active item must have all five tables held whole.
- **No item, and this Mac never adopted a Marfa:** the item is made from this Mac's settings.
- **No item, and this Mac adopted another Marfa:** the shared settings start from the app's defaults, so a new Marfa does not take another's arrangement.
- **An item exists:** it wins, and what it lacks is filled from this Mac once.
- **Two items,** made by two Macs at once: the older is used, filled from the other.
- **Switching Marfa** loads the groups that sync with that Marfa.

## Changes between Macs

- **Each step compares local, remote and last shared values** (`PreferencesMerge`). A drag makes one write.
- **The record of what both hold is saved before the item is written**, so a refused write never sends another Mac's change back as this Mac's.
- **The later write wins**, row by row and member by member. A table's change log can undo a batch from the command line.
- **Conflicts resolve by member.** This Mac reclaims members it sent and takes the rest. It leaves copies containing off groups for other Macs.
- **After another Mac's change reaches the defaults, the stores read them again**, so open windows and shortcuts follow. A store that reads its value once joins the `reload` `Libraries` gives `PreferencesSync`.
- **A row that no setting here owns is the Marfa's.** A later version may have written it, so it is never changed or deleted.

## Unreadable values

- **An unreadable value is never deleted or written over.** It is set aside under the store's `...SetAside` key, and the store starts from its defaults.
- **Stored text that this Mac cannot read is not sent**, and a value that the defaults cannot hold is skipped before anything is written.
- **Reset keeps every value that was set aside.**

## Removing and disconnecting

- **Remove… in Connection moves every settings item to the bin** and stops writing until Keep in Marfa Again. This Mac keeps its own settings.
- **Disconnect can remove them too, and only with Keep Copy.** A removal sends the whole queue, which must not carry a discarded change.
- **The app signs out only after the server has taken the removal.** If that fails, it stays connected.

## Restore points

- **Save a restore point** (`RestorePoints`) before first sync, adoption, switching Marfa, resuming a group, Reset, Import and Restore. A failed save stops the change.
- **A point holds the app's settings** (`SettingsSnapshot`), including every Marfa's entry, local settings and text a store cannot read. The sync switches are excluded. It reads only the app's own domain, so a restore never makes a system setting the app's.
- **An identical point is not saved again**, so a retry pushes none out.

## Import, restore and reset

- **They run between sync steps** (`PreferencesSync`). For enabled groups, their writes win over remote changes still to arrive. These marks survive relaunch.
- **Import replaces each chosen section whole** (`SettingsFile`): a setting the file lacks goes to its default; other sections are untouched. A file not the app's, or from a later version, changes nothing. Every value is checked before any is written.
- **Restore puts back exactly what the point holds**, removes the keys it lacks and saves a point of its own, so it can be undone.
- **Reset clears `MacSettings.keys`.** Other Macs follow the reset for groups both Macs sync. Groups previously off on this Mac take the Marfa's values when they resume. Reset keeps the library's copy, queue, sign-in and sync record.
- **A system-wide shortcut that another app holds is kept as it was** and counted as skipped.
