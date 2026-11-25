---
summary: How a value is edited in its panel: the rows, counts, conflicts, an event's time, lists with labels and the location map.
paths:
  - MarfaMac/Views/ValueEditing/*.swift
  - MarfaMac/Model/Items/EventTime.swift
  - MarfaMac/Model/Items/ValueEditing.swift
---

# Value panels

`docs/editing.md` says how an item is made and its type changed.

## Value panels

- **A value is edited in a panel under itself** (`ValueEditPresenter`, `ValueEditModel`), the same one from a row, a cell, the right sidebar and a chip. Rows are 28 points with 7 point corners, in a panel with 14 point corners.
- **A single choice closes the panel when picked; several choices keep it open.** Only a date's panel has a row for Not Set. A yes or no is two rows, Yes and No, and closes when one is picked.
- **A chosen or pointed-at row is gray, never the accent.** In a calendar the chosen day is a dark gray circle and today's number is red (`ValueCalendar`).
- **A value that holds several shows what is chosen as chips in the find field,** each with a remove mark, then the rows to choose from.
- **Tags, words and collections show a count beside each row,** how many items hold it. A tag's and a word's come from the copy; a collection's member count is asked of Marfa (`ItemCounts`) when the rows appear, never while they draw, and the row shows none until Marfa answers.
- **The last row makes what was typed:** Add “letterpress” for a word, Create Tag “pap” for a tag. Its Return key cap shows only while Return takes that row.
- **A status panel lists the type's words under their four groups.** Edit Statuses… opens the type in Settings.
- **An event's time is one panel** (`EventTime`, `EventTimePanelModel`): a calendar, the start and the end each with a day and a time, All Day, and the zone. A change is one write of only the properties that changed, so a time the person did not touch stays as the item holds it.
- **Moving the start keeps the length, and an end before the start is refused.** A whole-day event's end is shown as its last day and stored as the midnight that closes it.
- **A list of entries is edited in one panel** (`EntriesEditor`): a block for each entry with its members in rows, the name of each in a column. The first entry is the main one, which the page's row shows with how many more there are. A form that has no item yet holds the same editor inline.
- **A conflict is a question, not an error,** so it has no red: "This value changed while you were editing." and "Your edit hasn’t been saved.", with Keep My Edit, the main button, and Use Current Value. Any other refusal is one red line at the panel's foot, and what was typed stays.
- **A web address is a link, and a click opens it.** It is edited from its row's menu: Open, Copy, Edit, then Clear.
- **Unsaved text is kept when a panel loses its place**, and the person is told where it is.
- **A panel writes the one property it shows**, on the version it read, so it never writes over another app's change to another property.
- **Change Type, Add Tag and Add to Collection are panels too** (`CommandValuePanels`), never sheets. They act on the whole selection as one undo.
- **What a command cannot change is left alone and counted** (`BatchSkips`), never silently skipped.

## Location

- **The panel is 360 points wide and its map has a zoom stepper.**
- **The person places the pin.** Apple's license (Developer Program License Agreement, Attachment 6, section 2.5) forbids keeping what a map search returned. A search result only moves the map; what is written is the point the person chose (`LocationPanelModel`).
- **One edit and one undo write both numbers** and the name the person typed. Clear Location keeps the name.
- **A name that cannot be written goes to the clipboard**, and the person is told.
