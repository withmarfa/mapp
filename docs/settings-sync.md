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

Read this before you add, move, reset or restore a setting.

## Three homes

| Home | What it holds |
| --- | --- |
| The Marfa's own data | Items, types, views and the sign-in's grants. Never an app setting |
| This app's settings | Every setting that should follow the person to another Mac |
| This Mac only | What fits one screen or one Mac: widths, the last place open, any-app shortcuts, consent to error reports, export plans |

- **A setting has the narrowest home a person would expect**, and one home only. `PreferencesMap` names it, and a test fails for a key it does not place.
- **To add a setting:** add its key to `MacSettings.keys` and to `PreferencesMap` in the same change. Reset, export, restore points and the sample library then include it.
- **The defaults are the store that the app reads**, so a launch needs no network and `@AppStorage` works. Where settings sync, the defaults are this Mac's copy.
- **Store only what a person chose.** A value that equals the default is left out, so a better default reaches them.
- **A new member of a stored value is optional**, because values saved before it must still decode.

## In the Marfa

- **One hidden item a Marfa holds them** (`PreferencesType`): five object fields, one for each group of settings that come once, and five tables for settings that come once for a command, type, view, place or sidebar part.
- **The type can never change shape.** Only the client that registered it may replace it, and every Mac is another client (withmarfa/marfa#3462). A new setting is a new member of a field or a new `setting` word in a table.
- **Two Macs that change different settings both keep their change.** A field is written by member and a table by row, so split a value into rows where its parts change apart. A list whose order matters is one row, and the later arrangement wins whole.
- **A set is written sorted**, so saving it again is not a change.
- **What is kept for a place is keyed by its word** (`PlaceView.storageKey`), and for a saved view by its id, since its place can change. Each place's order of views is a `viewOrder` row (`ViewOrders`).
- **What an earlier copy kept under its own key for a place is never removed**, so that copy still reads it (`EarlierPlace`). An earlier copy that rewrites a `viewLayout` row drops the members it does not know, such as `quickActions`; that downgrade is accepted.
- **A sign-in asks for `app.*:write`, never the app's own vendor scope**, because discovery lists no vendor scope before its first type exists (withmarfa/marfa#3522).

## The first launch against a Marfa

- **Nothing is decided from a partial copy.** Until hydration is complete, the sign-in reaches the type and every table is held whole, the defaults stay as they are.
- **No item, and this Mac never adopted a Marfa:** the item is made from this Mac's settings.
- **No item, and this Mac adopted another Marfa:** the shared settings start from the app's defaults, so a new Marfa does not take another's arrangement.
- **An item exists:** it wins, and what it lacks is filled from this Mac once.
- **Two items,** made by two Macs at once: the older is used, and what it lacks is filled from the other.
- **Switching Marfa** loads the other Marfa's settings whole.

## Changes between Macs

- **Each step compares three things:** this Mac, the item, and what both held after the last step (`PreferencesMerge`). A change on this Mac waits a moment, so a drag is one write. What was just applied is not written back.
- **The record of what both hold is saved before the item is written**, so a refused write never sends another Mac's change back as this Mac's.
- **The later write wins**, row by row and member by member. A table's change log can undo a batch from the command line.
- **A conflicted copy of a field is answered by member:** what this Mac sent is written again, the rest is taken; the copy goes to the bin.
- **After another Mac's change reaches the defaults, the stores read them again**, so open windows and shortcuts follow. A store that reads its value once must join the `reload` that `Libraries` gives `PreferencesSync`.
- **A row that no setting here owns is the Marfa's.** A later version of the app may have written it, so it is never changed or deleted.

## Unreadable values

- **An unreadable value is never deleted or written over.** It is set aside under the store's `...SetAside` key, and the store starts from its defaults.
- **Stored text that this Mac cannot read is not sent**, and a value that the defaults cannot hold is skipped before anything is written.
- **Reset keeps every value that was set aside.**

## Removing and disconnecting

- **Remove… in Connection moves every settings item to the bin** and stops writing until Keep in Marfa Again. This Mac keeps its own settings.
- **Disconnect can remove them too, and only with Keep Copy.** A removal sends the whole queue, and a change that the person discarded must not reach the server.
- **The app signs out only after the server has taken the removal.** If that fails, it stays connected.

## Restore points

- **Before anything replaces many settings at once, a restore point is saved** (`RestorePoints`): the first sync, adoption, switching Marfa, Reset, Import and Restore. If the point cannot be saved, nothing changes and the person is told.
- **A point is the defaults themselves** (`SettingsSnapshot`): every key, every Marfa's entry, the settings that stay, and text its store cannot read. It reads only the app's own domain, so a restore never makes a system setting the app's.
- **An identical point is not saved again**, so a step that retries does not push a real one out.

## Import, restore and reset

- **They run between sync steps** (`PreferencesSync`): a step under way ends first and one runs after, so no step writes over them with what it read before.
- **What they wrote wins at the next step**, even over a change from another Mac that this Mac has not taken. The marks that say so survive a relaunch.
- **Import replaces each chosen section whole** (`SettingsFile`): a setting that the file lacks goes to its default, and other sections are untouched. A file that is not the app's, or is from a later version, changes nothing. Every value is checked before any is written.
- **Restore puts back exactly what the point holds**, removes the keys it lacks and saves a point of its own, so it can be undone.
- **Reset clears `MacSettings.keys` and `MacSettings.prefixes`.** It keeps the library's copy, the queue, the sign-in and the sync's record, and its alert says that every connected Mac follows.
- **A system-wide shortcut that another app holds is kept as it was** and counted as skipped.
