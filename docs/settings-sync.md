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
| This app's settings | Settings that follow the person, such as New item opens as |
| This Mac only | Widths, last place, playback places, recent kinds, New Item's tags and parents, any-app shortcuts, error-report consent, export plans |

- **A setting has the narrowest home a person would expect**, and one home only. `PreferencesMap` names it, and a test fails for a key it does not place.
- **To add a setting:** add its key to `MacSettings.keys` and to `PreferencesMap` in the same change. Reset, export, restore points and the sample library then include it.
- **The defaults are the store the app reads**, so a launch needs no network. Synced, they are this Mac's copy.
- **Store only what a person chose.** A default value is left out, so a better default reaches them.
- **A new member of a stored value is optional**, so older values decode.
- **A library's own settings are named by its Marfa,** else its copy's folder. `LibrarySettings` moves earlier names' first; losers go to `Restore Points/Library Settings Set Aside/`, unreadable or undecided stay unsynced.

## In the Marfa

- **One hidden item a Marfa holds them** (`PreferencesType`): five object fields, one for each group of settings that come once, and five tables for settings that come once for a command, type, view, place or sidebar part.
- **The type can never change shape.** Only the client that registered it may replace it, and every Mac is another client (withmarfa/marfa#3462). A new setting is a new member of a field or a new `setting` word in a table.
- **Two Macs that change different settings both keep their change.** A field is written by member and a table by row, so split a value into rows where its parts change apart. A list whose order matters is one row, and the later arrangement wins whole.
- **A set is written sorted**, so saving it again is not a change.
- **A hidden view is its own row, kept when shown again:** a row this Mac lacks of a `PreferencesMap.keptWhereAbsent` setting is taken, not deleted.
- **What is kept for a place is keyed by its word** (`PlaceView.storageKey`), and for a saved view by its id, as its place can change; an earlier copy's keys are never removed (`EarlierPlace`).
- **An earlier copy drops unknown members** from a row it rewrites. For example, it may drop `digest` from `viewLayout` or `placeDefaults`. It reads an unknown layout as List.
- **A sign-in asks for `app.*:write`, never the app's own vendor scope**, because discovery lists no vendor scope before its first type exists (withmarfa/marfa#3522).

## The first launch against a Marfa

- **Settings sync checks the copy first.** Hydration must be complete, the sign-in must reach the type, and every active item must have all five tables held whole.
- **No item, and this Mac never adopted a Marfa:** the item is made from this Mac's settings.
- **No item, and this Mac adopted another Marfa:** the shared settings start from the app's defaults, so a new Marfa does not take another's arrangement.
- **An item exists:** it wins, and what it lacks is filled from this Mac once.
- **Two items,** made by two Macs at once: the older is used, filled from the other.
- **Switching Marfa** loads the other Marfa's settings whole.

## Changes between Macs

- **Each step compares this Mac, the item, and what both held after the last step** (`PreferencesMerge`). A drag is one write. What was just applied is not written back.
- **The record of what both hold is saved before the item is written**, so a refused write never sends another Mac's change back as this Mac's.
- **The later write wins**, row by row and member by member. A table's change log can undo a batch from the command line.
- **A conflicted copy of a field is answered by member:** what this Mac sent is written again, the rest is taken; the copy goes to the bin.
- **Stores reload incoming changes** so windows and shortcuts follow. Register stores that cache values with the `reload` callback in `Libraries`.
- **Search remembers display names in memory.** Adding an exclusion saves its name.
- **Sync preserves unrecognized rows.** A later version may own them.

## Unreadable values

- **Stores preserve unreadable values** under their `...SetAside` keys and use defaults.
- **Sync skips unreadable text and values the defaults cannot hold.**
- **Page placements are read by type.** An edit keeps every other entry byte for byte. The first edit with unreadable entries saves the original document under `pagePlacementsSetAside`.
- **Reset keeps every value that was set aside.**

## Removing and signing out

- **Remove… in General queues removal and stops sync**, even offline. If the copy still lists an item targeted for removal, Keep in Marfa Again waits for the removal to settle and the copy to catch up. Local settings stay.
- **Sign Out can remove them with Keep Copy.** Removal sends the whole queue, so it can’t accompany Discard.
- **The app signs out only after the server has taken the removal.** If that fails, it stays connected.

## Restore points

- **Before anything replaces many settings at once, a restore point is saved** (`RestorePoints`): the first sync, adoption, switching Marfa, Reset, Import and Restore. If the point cannot be saved, nothing changes and the person is told.
- **A point is the defaults themselves** (`SettingsSnapshot`): every key, every Marfa's entry, the settings that stay, and text its store cannot read. It reads only the app's own domain, so a restore never makes a system setting the app's.
- **An identical point is not saved again**, so a retry pushes none out.

## Import, restore and reset

- **They run between sync steps** (`PreferencesSync`): a step under way ends first and one runs after, so no step writes over them with what it read before.
- **What they wrote wins at the next step**, even over another Mac's change not yet taken here. The marks that say so survive a relaunch.
- **Import replaces each chosen section whole** (`SettingsFile`): a setting the file lacks goes to its default; other sections are untouched. A file not the app's, or from a later version, changes nothing. Every value is checked before any is written.
- **Restore puts back exactly what the point holds**, removes the keys it lacks and saves a point of its own, so it can be undone.
- **Reset clears `MacSettings.keys`.** It keeps the library's copy, the queue, the sign-in and the sync's record, and its alert says every connected Mac follows.
- **A system-wide shortcut that another app holds is kept as it was** and counted as skipped.
