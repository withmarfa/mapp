# Keyboard shortcuts

Status: Built, not yet released. The shortcuts that work in any app must be tried in a sandboxed TestFlight build before a release.

Where it lives: `Shortcut`, `ShortcutCommand`, `ShortcutBindings`, `ShortcutsFile`, `AnyAppShortcuts` and `SystemHotKeys` under `MAPP/Model/Shortcuts/`, `FrontBrowser` and the catalogue of commands (an extension of `ShortcutCommand`) under `MAPP/Views/`, and `KeyboardPage`, `KeyboardPageModel` and `KeyboardFiles` under `MAPP/Settings/MAPP/`.

Settings > Keyboard gives every menu command MAPP adds a shortcut that its person can change. It replaces the old Keyboard Shortcuts window, and Help > Keyboard Shortcuts opens the page. The shortcuts stay on this Mac and are never written to Marfa ([Settings storage](settings-storage.md)).

## Menu commands

- Every command is listed under the name of its menu, in the order of the menus, in a white shortcut field with a clear button. The system's own commands (Copy, Quit, Hide, Enter Full Screen, Close All, Emoji & Symbols, Help) are not MAPP's to change and are left out; a shortcut one of them holds can't be taken, by a menu command or by one that works in any app.
- A click on a field records the next keys pressed, taken before the menus can answer them. Escape stops, and Delete clears. Recording also stops when MAPP or the window stops being in front, or the page goes, and while a field records or the search waits for keys, the shortcuts that work in any app do not answer. A menu shortcut needs ⌘, ⌃ or ⌥ (or is a function key), since a bare key is typing.
- A shortcut another command holds is shown as taken: the red ring, and under the row's title "⌘K is Command Palette's." An alert offers Replace, which leaves the other command with none, or Cancel.
- The menus bind the chosen shortcut at once (`ShortcutBindings`), and so does the palette, which prints it beside the command. The Format commands also tell the item page, which answers the same keys.
- The default of a command is in `ShortcutCommand`'s catalogue and is the shortcut it had before the page. Only a choice is stored, so a better default reaches every command nobody changed. No default is a key the system holds (`SystemShortcuts`, which includes the View menu's Show Toolbar, ⌥⌘T) or another command's: Insert Table is ⌃⌘T for that reason, and a test fails on any clash.
- The toolbar's copy of a command and a row's menu bind no key, so a key is never registered twice.
- A command whose title or action changes with the state of the window (Show Reader or Original, Add to Favorites or Remove from Favorites) is one command with one shortcut.

## Shortcuts that work in any app

- Show Command Palette, Search Items and Quick Add (named apart from File's New Item), off until set, while MAPP is running. Each must include ⌘ or ⌃ (an Option-only shortcut fails on recent macOS), and two of them never share keys. One the system uses, or that another app already holds (the system refuses to register it), is shown as taken, with one line under the row, and nothing new is kept.
- A shortcut is registered with the system only while it is set: setting it registers it, clearing it unregisters it, and nothing is registered before launch finishes. It uses Carbon's `RegisterEventHotKey` through the KeyboardShortcuts package, which needs no Accessibility permission and works in the sandbox.
- Until the palette can be shown over another app (not designed yet), each brings MAPP forward and does its action in the window that was in front. With no such window it only brings MAPP forward.

## Search

A small search at the top right filters by command name. The keyboard button beside it searches by pressing keys instead (⌘K finds Command Palette), and typing searches by name again when it is off. While it searches by keys, each section says how many of its commands use the keys.

## Files

Export Shortcuts… writes a small versioned JSON file (`mapp-shortcuts`, version 1) with every command's shortcut and the shortcuts that work in any app. Import Shortcuts… reads it. A file that is not MAPP's, or comes from a newer MAPP, is refused and says so, and changes nothing. A shortcut naming a command MAPP no longer has is skipped and counted, and so is one whose keys another command or the system holds. Import adds and changes only what the file names, for menu commands and for the shortcuts that work in any app alike: a command the file does not name keeps its shortcut, and a shortcut left out keeps what its command had. The notice says how many were imported and how many were skipped.

Restore Defaults… puts every command back to its default and turns the shortcuts that work in any app off. Reset MAPP's Settings… in General does the same, at once: the menus and the registered hot keys change without a relaunch.

## Stored shortcuts

A stored shortcut for a command that no longer exists is ignored and kept, in case the command comes back. Stored text that can't be read is set aside under `keyboardShortcutsSetAside` or `anyAppShortcutsSetAside` and the defaults stand.

## Related pages

- [Settings storage](settings-storage.md)
- [Agreed designs](agreed-designs.md#settings)
- [Views and lists](views-and-lists.md)
