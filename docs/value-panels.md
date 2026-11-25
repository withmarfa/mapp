---
summary: How a value is edited in its panel: the rows, counts, conflicts, an event's time, lists with labels and the location map.
paths:
  - MarfaMac/Views/ValueEditing/*.swift
  - MarfaMac/Model/Items/EventTime.swift
  - MarfaMac/Model/Items/ValueEditing.swift
---

# Value panels

`docs/editing.md` says how an item is made and its type changed.

## Panels

- **A value is edited in a panel under itself** (`ValueEditPresenter`, `ValueEditModel`), the same one from a row, a cell, the right sidebar and a chip. Rows are 28 points, 1 point apart, with 7 point corners, in a panel with 14 point corners.
- **A panel is as wide as its board** (`ValueEditMetrics`): status 250, date 212, choice 170, type 230 and event time 262, and a section header is 27 points.
- **A single choice closes the panel when picked; several keep it open.** Only a date's panel has a row for Not Set. A yes or no is two rows, Yes and No.
- **A chosen or pointed-at row is gray, never the accent.** In a calendar the chosen day is a dark gray circle and today's number is red (`ValueCalendar`).
- **A value that holds several shows what is chosen as chips in the find field,** each with a remove mark. The field is a bare caret, not a box; the keyboard ring stays on every other control.
- **A date panel starts with the day typed** ("25 Nov 2026", with " at 09:00" where the value holds a time). Return sets it; text that is no date stays in the field with the reason, and goes back to the person as the panel ends.
- **Tags, words and collections show a count beside each row,** how many items hold it. A collection's member count is asked of Marfa (`ItemCounts`) when the rows appear, never while they draw.
- **The last row makes what was typed:** Add “letterpress” for a word, Create Tag “pap” for a tag. Its Return key cap shows only while Return takes that row.
- **A status panel lists the type's words under their four groups.** Edit Statuses… opens the type in Settings.
- **A people panel offers the people the lists already name and the people the library holds as items,** each added with their first address.
- **An event's time is one panel** (`EventTime`, `EventTimePanelModel`): a calendar, the start and the end each with a day and a time, All Day, and the zone. A change writes only the fields the action changes, so a stored value the person did not touch stays byte for byte.
- **A day chosen or typed keeps the whole clock time,** seconds and fractions included. Moving the start keeps the length, and an end before the start is refused.
- **A time the zone does not have on that day is refused,** never moved to one it has. What was typed stays in the field with the reason, and is given back where the panel ends or the start or end changed meanwhile.
- **A list of entries is edited in one panel** (`EntriesEditor`): a block for each entry, its members in rows named by the core's labels. The first is the main one. Add, Return and leaving write the new entry whole, or hand back all of it; a refused Add keeps it to try again.
- **A conflict is a question, not an error,** so it has no red: "This value changed while you were editing." and "Your edit hasn’t been saved.", with Keep My Edit, the main button, and Use Current Value. Any other refusal is one red line at the foot, and what was typed stays.
- **A web address is a link, and a click opens it.** Its row's menu has Open, Copy, Edit, then Clear.
- **Unsaved text is kept when a panel loses its place**, and the person is told where it is.
- **A panel writes the one property it shows**, on the version it read, so it never writes over another app's change to another property.
- **Change Type, Add Tag and Add to Collection are panels too** (`CommandValuePanels`), never sheets. What a command cannot change is left alone and counted (`BatchSkips`).

## Location

- **The panel is 360 points wide and its map has a zoom stepper.**
- **The person places the pin.** Apple's license (Developer Program License Agreement, Attachment 6, section 2.5) forbids keeping what a map search returned. A search result only moves the map; what is written is the point the person chose (`LocationPanelModel`).
- **One edit and one undo write both numbers** and the name the person typed. Clear Location keeps the name.
- **A name that cannot be written goes to the clipboard**, and the person is told.
