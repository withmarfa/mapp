---
summary: The rules of looks that hold on every screen, from chips and selection to buttons, messages and words.
paths:
  - MarfaMac/Views/Looks/*.swift
  - MarfaMac/Views/App*.swift
  - MarfaMac/Views/ToastView.swift
  - MarfaMac/Views/KeyCap.swift
  - MarfaMac/Model/Items/StatusSymbol.swift
---

# How things look

Each kind of thing has one drawing, used on the page and in a panel, row, card or table cell. Measures, colors and fills are tokens in the code; this page has the rules they serve. Search `docs/rejected.md` before proposing a look.

## Where things go

- **The window has three areas:** the sidebar, the list pane and the page. A screen adds no new kind of column or toolbar without changing this rule first.
- **What a person moves between goes in the list pane.** The page holds at most one main action.
- **The system's control comes first.** Segmented controls, search fields, switches, alerts, menus and the toolbar's glass are the system's, because a hand-drawn copy misses what the system changes.
- **Nothing shows until there is something to show.** An option that does not apply is absent from a menu, not dimmed, unless the person would look for it there.
- **Every component works in light and dark,** and scales with the interface's text size (`InterfaceStyle`).

## Chips and marks

| Kind of value | Drawing |
| --- | --- |
| Status, option | A chip: the status's symbol or the option's dot, then the word |
| Tag | The `number` symbol and the word, on the same chip |
| Type, linked item | Its mark in its tone and its name, never a chip |
| Person | Initials in a pale purple circle, with the name beside it where there is room |
| Date, number, address, source | Plain text |

- **A value from a set is a chip, and anything else is text or a fact**.
- **A chip has one gray wash and no edge.** Only the type being given to an item is tinted (`TintedChip`); Appearance chooses Tinted (default) or Gray.
- **A person's circle is 18 points: purple letters on pale purple, no edge** (`PersonCircle`). The name beside it is a fact: 13 points, regular.
- **Chips come from one family** (`PageChip`, `PersonCircle`, `ChipLine`) in two sizes. `ChipLooks` owns the measures, the web header reads them as `--chip-*` variables, and `ChipLooksTests` checks they agree.
- **Several values show as two, then a count.**
- **A type's mark in a row and on the page is its glyph in the plain tone** (`TonedGlyph`); the palette draws marks in one gray. A tile (`TypeTile`) is only for the Settings type page.
- **A filter chip reads in order:** field, operator, values, then its close button.

### Dark values

Neutral washes are white at the same strength, hairlines white at 12%, and a tone keeps its hue (`TypeTone`). `ChipLooksTests` holds each text to 4.5 to 1 on its fill.

| Color | Light | Dark | Where used |
| --- | --- | --- | --- |
| Chip wash | Ink 3.5% | White 3.5% | Every chip |
| Tinted type chip | Tone 14% | Tone 20% | `TintedChip` |
| Person fill | Purple 15% | Purple 26% | `PersonCircle` |
| Added words | Green 15% | Green 26% | `VersionLooks` |
| Faint text | Ink 36% | White 36% | `VersionLooks` |
| Current wash | Ink 6% | White 6% | `VersionLooks` |
| Chip text | Ink 72% | White 72% | Chips, a fact in a row |
| Name on a tint | Tone toward black: 28% person, 46% type | Tone 50% toward white | `PersonCircle`, `TintedChip` |
| Chosen, hover row | Ink 8%, 4.7% | White 8%, 4.7% | Lists, panels, calendars (`SelectionLooks`) |
| Keycap edge | Ink 20% | White 20% | `KeyCap` |
| Focus ring | Ink 26% | White 26% | Every keyboard control (`appFocusRing`) |
| PDF ground | Gray 94.5% | Gray 17% | Behind a PDF's white pages (`PDFBackground`) |

## Status, priority and empty values

- **`StatusSymbol` is the one map from a status's group to a symbol and a tint.** The words stay the type's own, so an app's "Closed" still reads Closed. A word that no group claims draws as not started.
- **A task's priority takes its color from its rank**, never from its word (`OptionTone.prioritySteps`). Any other option takes one from its word.
- **Clicking an editable status chip opens its panel** (`StatusPanel`).
- **An empty value is the gray word Empty**, never a plus button.
- **A favorite is a yellow star.** The tag behind it is never shown as a tag.

## Selection

- **A chosen row is soft gray and a row under the pointer is lighter**, in every list (`SoftSelection`). Neither is blue.
- **A chosen card has a 13% ring (26% in dark)**, never a fill over the picture.
- **A heading, a date line and a group's header get no hover mark**, because they cannot be clicked. Only a group's chevron reacts.
- **A cell that can be edited keeps its own tint** over the row's.
- **A chosen row in a value panel, filter panel or calendar is the same gray** (`SelectionLooks`), never the accent.

## Buttons

- **A button's shape follows its size** (`AppButtonSize`): regular and large are capsules, small has soft corners. Regular stands on its own, small goes in tables and panels, and large is the first-run action.
- **A text action has a fill:** pale gray, or the accent for the main action, but a page notice's has none. Destructive is pale red with red text, never the default.
- **A symbol on its own is a gray circle.** On a header row, and for a close button inside a notice or chip, it is plain until the pointer is over it.
- **Two arrows choose a value and one arrow opens a menu of commands** (`appMenu`, with `.value` or `.commands`).
- **A label ends in an ellipsis when the button opens** a sheet, dialog, chooser, confirmation or browser page. A button that acts at once, or is a menu, has none.
- **Keyboard focus is the app's own 3 point gray ring** in the control's shape, on every control that takes the keyboard: `appFocusRing` on a field, `AppButtonStyle` on a button.
- **In a sheet, a destructive action stands alone at the leading edge**, and Cancel and the main action are at the trailing edge. The button says Delete, not Delete Collection.
- **A field, a chip and a token keep soft corners**, so a value never reads as a button.

## Keycaps

- **Where the app draws a shortcut, it is outlined keycaps**, one glyph each (`KeyCap`). A menu keeps the system's glyphs.

## Messages

- **A toast says what happened, and offers Undo** (`ToastView`): a symbol, the words and Undo, 40 points high, no close button. A window shows one for five seconds and it waits while the pointer is over it. It reports moves to Recently Deleted, the Feed, the Library and the archive.
- **Undo in a toast takes back that step alone** (`StepUndo`). Any later step, undo or redo removes the toast, so it never takes back something else.
- **What cannot be undone asks first**, in the system's alert.
- **A window's toast belongs to that window** (`ToastPresenter`), and another workspace in it does not drop the toast.

## Empty states

- **One rule draws every empty place** (`PlaceEmpty`, `PlaceEmptyState`): a title, one short line, and a button only where there is something to do.
- **It stands in the middle of the content**, not of the list column.
- **A list emptied by filters offers Clear Filters.** A search with no match has no button.

## Words

- **Buttons and menu items are in title case**, sentences in sentence case. The words follow the Writing section of Apple's Human Interface Guidelines.
- **A label says what happens to the person's things**, with the names in `docs/model.md`, never a server's term.
- **A symbol before a label has its size and weight.** Symbols are SF Symbols.
- **Every string a person reads is in the String Catalog.**
