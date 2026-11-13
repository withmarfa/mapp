# Value components

Status: Built, not yet released. Each kind of value below is drawn by one component wherever the app shows it, except where "Not yet built" says otherwise.

Where it lives: `PageChip`, `PagePerson`, `PersonCircle`, `StatusMark`, `ChipLooks`, `TypeMark`, `TypeTone` and `OptionTone` under `MAPP/Views/Looks/`, `StatusSymbol` under `MAPP/Model/Items/`, and `editor/src/header.ts` for the page's web header.

A value component is one drawing for one kind of value. The same component appears on the page, in the right sidebar, in a row, a card and a table cell, and in the panel that edits the value, so a status looks like a status everywhere.

## One chip for each kind of value

| Kind | Drawing |
| --- | --- |
| Status | A symbol for its group, in a chip with a fine gray edge, and a faint fill in dark. |
| Priority and other options | A dot in the option's color, then the word. A list of options, such as a repository's labels, takes the dot too. |
| Type | The type's name tinted in its color, with its icon in color. |
| Linked item | The linked item's type mark and title on the gray of an option chip. The title is underlined under the pointer. |
| Tag | Gray, after a number sign. |
| Person | Initials in a pale circle with a fine edge. The page and the right sidebar add the name; a row shows initials only. |
| Filter | Its field in gray, then is or is not, the values and an x. |

Dates, numbers, web addresses and sources are plain text, not chips.

In a row, linked items do not show, and tags show only in a Note's (a Note look's `tags` fact; see [Looks](looks.md)). A chip is a little smaller in a row (20 points high with 11.5-point text) than on the page (22 points high with 13-point text).

A tint means a type, so no other chip uses a colored fill. A person has no chip round the name and is never colored. Bare chips are not used.

Agreed, not built: solid options and tags are a setting, off by default.

## Type marks

A type's mark is its icon on a pale rounded square of the same color (`TypeMark`), the same everywhere, with no shadow. Built in v0.0.43. In light the icon sits 22 percent toward black from the tint's color. In dark it sits 8 percent toward white and stays under a brightness ceiling, so the bright tones sit level with the others (`ChipLooks.inkDepth`, `inkDepthDark`, `inkCeilingDark`).

Every component works in light and in dark.

## Status

A status takes the group's symbol, and the status words stay the type's own, so a GitHub issue still says Closed. A status no group claims draws as not started. A word too long for its chip is cut with an ellipsis and its whole word is in the help.

| Group | SF Symbol | Color |
| --- | --- | --- |
| Not started | `circle` | Secondary gray |
| In progress | `circle.lefthalf.filled` | Blue |
| Completed | `largecircle.fill.circle` | Secondary gray |
| Canceled | `xmark.circle` | Tertiary gray |

`StatusSymbol` is the one place that maps a group to a symbol and a tint. `StatusMark` draws it in SwiftUI wherever the app shows a status: the page's chip, the right sidebar, a table, a gallery card, a value panel and a list row. The page's web header draws the same four symbols, which the app sends as it sends every other symbol (`PageHeaderIcons`), and colors them from its own system colors.

## Priority

A task's priority takes its color from its rank, never from its word: Low purple, Medium yellow, High red, Urgent blue (`OptionTone.prioritySteps`). Any other option takes a color from a fixed palette chosen by its words, so the same word has the same color on every launch.

## Empty values

An empty value is the gray word Empty, in rows and pins. It is never a bordered plus button.

## Editing

A value is edited in a panel that opens under it, its leading edge on the value's (`ValueEditPresenter`). The chosen values sit as chips in the field at the top, each with an x.

- A status is edited by its groups, with each of the type's words under its group, as Marfa defines status.
- Lists are flush left, with no column for a tick, and show ten rows at most.
- A value that takes one choice (status, priority, parent, type) closes on a pick and has no Not Set row. A value that takes several (tags, people) stays open.
- A date has its shortcuts, a calendar that MAPP draws with the day as a circle, a Time row that stays empty until set, and Not Set.
- The panel is glass by default. A Solid choice in Appearance makes it the window's own color.
- Change Type is a panel like status. See [Item page](item-page.md).

## Built, not yet released

One family draws every kind of value: `PageChip` for a type, a linked item, a status, an option, a tag and a plain word, and `PagePerson` and `PersonCircle` for a person. Each takes a size, `.page` or `.row` (`ChipSize`), and its measures come from `ChipLooks`, scaled with the interface's text size. A chip is as tall as its size says, so chips side by side line up.

- The item page's pins and property rows, the right sidebar's status, choice and tag values, and a gallery card's chips draw through the family at page size. The value panel's chips and a table's cells draw only their marks (status symbol, person circle) through it. The page's web header draws the same measures in HTML.
- A list row draws its type, status, options, people and tags through the family at row size (`ItemRow`, `RowContent`), whatever the type; a person is initials only. See [Looks](looks.md).
- A person is one look everywhere: initials in a pale circle, then the name on the page and in the right sidebar, and the circle alone in a row, with the name for VoiceOver. A name with one word, or an email address, gives one initial.
- A choice the field's list does not hold draws as its word, with the color its word gives it. Several values show as the first two, then a count.
- The right sidebar's tag chip carries a number sign and keeps its remove control.

Not yet built:

- A table's priority is still bars, the value panel's chips keep their own shape, and a gallery card keeps its own chip layout.
- The right sidebar's relationship rows, its people text fields and the Details cells keep their own drawings.

## Related pages

- [Looks](looks.md)
- [Item page](item-page.md)
- [Rejected designs](rejected-designs.md)
