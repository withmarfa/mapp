# Value components

Status: Agreed, not built. The page and its pins already draw chips this way (built in v0.0.43); the other places do not yet. See "Built today".

Where it lives: `PageChip`, `PagePerson`, `ChipLooks`, `TypeMark`, `TypeTone` and `OptionTone` under `MAPP/Views/Looks/`, `StatusMark` in `MAPP/Views/GalleryCards.swift`, and `editor/src/header.ts` for the page's web header.

A value component is one drawing for one kind of value. The same component appears on the page, in the right sidebar, in a row, a card and a table cell, and in the panel that edits the value, so a status looks like a status everywhere.

## One chip for each kind of value

| Kind | Drawing |
| --- | --- |
| Status | A symbol for its group, in a chip with a fine grey edge. |
| Priority and other options | A dot in the option's color, then the word. |
| Type | The type's name tinted in its color, with its icon in color. |
| Linked item | The linked item's type mark and title on the grey of an option chip. The title is underlined under the pointer. |
| Tag | Grey, after a number sign. |
| Person | Initials in a pale circle. The page and the right sidebar add the name; a row shows initials only. |

Dates, numbers, web addresses and sources are plain text, not chips.

In a row, linked items and tags do not show. A chip is a little smaller in a row (20 points high with 11.5-point text) than on the page (22 points high with 13-point text).

A tint means a type, so no other chip uses a colored fill. A person has no chip and no edge round the initials.

## Status

A status takes the group's symbol, and the status words stay the type's own, so a GitHub issue still says Closed.

| Group | SF Symbol | Color |
| --- | --- | --- |
| Not started | `circle` | Default |
| In progress | `circle.lefthalf.filled` | Blue |
| Completed | `largecircle.fill.circle` | Secondary grey |
| Canceled | `xmark.circle` | Tertiary grey |

## Priority

A task's priority takes its color from its rank, never from its word: Low purple, Medium yellow, High red, Urgent blue (`OptionTone.prioritySteps`). Any other option takes a color from a fixed palette chosen by its words, so the same word has the same color on every launch.

## Empty values

An empty value is the grey word Empty, in rows and pins. It is never a bordered plus button.

## Editing

A value is edited in a panel that opens under it, its leading edge on the value's (`ValueEditPresenter`). The chosen values sit as chips in the field at the top, each with an x.

- Lists are flush left, with no column for a tick, and show ten rows at most.
- A value that takes one choice (status, priority, parent, type) closes on a pick and has no Not Set row. A value that takes several (tags, people) stays open.
- A date has its shortcuts, a calendar that MAPP draws with the day as a circle, a Time row that stays empty until set, and Not Set.
- The panel is glass by default. A Solid choice in Appearance makes it the window's own color.

## Built today

The page's pins and property rows draw these chips in SwiftUI (`PageChip`, `PagePerson`, `PagePinsView`) and in the web header (`editor/src/header.ts`), from the sizes and fills of `ChipLooks`. Every chip is 22 points tall so chips side by side line up.

The other places draw a value in their own way. Status is a ring with a fill in `StatusMark` and in the page's chip, not a symbol. A Standard list row shows no status, priority or person. A gallery card and a table cell draw people and types differently from the page. The right sidebar shows a priority as plain text. These places adopt the components when the look is built.

## Related pages

- [Looks](looks.md)
- [Item page](item-page.md)
- [Rejected designs](rejected-designs.md)
