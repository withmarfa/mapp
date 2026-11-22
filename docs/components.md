# Components

Status: Built, not yet released, apart from the button shapes agreed on 22 November 2026. The one button style and the keycaps below are drawn by one type each in the sheets, quick add, the value panels, the banners and the palettes. The last Buttons line says what is built and what is not on the style yet. The toast is built for items moved to Recently Deleted; the Messages lines say what is left.

Where it lives: `MappButtonStyle`, `MappButtonRole`, `MappButtonSize`, `FieldLabel`, `KeyCap` and `ShortcutKeys`, under `MAPP/Views/`; `ToastView` there and `ToastPresenter` and `StepUndo` under `MAPP/Model/`.

The design system's Button and Toast components hold the exact fills and measures; `MappButtonStyle` and `ToastView` read them from there. What was turned down is in [Rejected designs](rejected-designs.md).

## Buttons

Agreed on 22 November 2026 and not built yet: the shape rule below replaces the rounded rectangles of 17 November. [Agreed designs](agreed-designs.md#buttons) lists what the build changes. MAPP Pages draws it on Foundations, F7 to F10.

- **The shape follows the size, as macOS draws its own controls.** A 28-point button is a capsule: anything that stands on its own, such as a row's button or pop-up, a sheet's actions, an empty state, tabs, and a header row's filter and search. A 24-point button is a rounded rectangle with 7-point corners: where controls repeat or sit inside something, such as a table's rows, a banner, the toast and a value panel. The first-run window's one action is 36 points, a capsule.
- **A text button always has a fill.** **Secondary** is pale gray. **Primary** uses the accent color for the one main action of a surface, a sheet's confirm button included, at the trailing edge. **Destructive** is a pale red fill with red text, never solid red, and never the default button, so Return never deletes. Only Show All and Show More, which show more of a list, have no fill.
- **A symbol on its own is a gray circle,** such as the More (…) and Add (+) buttons at a row's end. On a header row every control is plain and shows its shape only under the pointer: an index page's Search, Filter and New, and a Settings section's filter pop-up. So is the Close (×) button inside a banner, the toast, a chip or a field. The toolbar and the corner keep the system's glass.
- **Two arrows choose a value; one arrow opens a menu.** A pop-up button shows `chevron.up.chevron.down`; a pull-down menu of commands shows `chevron.down`. Both are gray, with no outline.
- **A button that opens a sheet, a dialog, a chooser, a confirmation or a browser page ends in an ellipsis** (…, one character). A button that acts at once, only shows something, or is a menu button has none. A symbol before a label takes the label's weight and size, never bold.
- Keyboard focus is a gray ring that follows the button's shape, never blue.
- A switch is a capsule no larger than 24 points. A search field is the system's: white, with a hairline edge, a capsule. Chips, tokens and text fields keep their rounded-rectangle corners, so a value never reads as a button.
- A sheet puts a destructive action alone at the leading edge, and Cancel and the primary action at the trailing edge. A text field has its label above it, such as Name. The button reads Delete, not Delete Collection.
- What is built today: `MappButtonStyle` draws rounded rectangles at 22 and 28 points, and Settings' `SettingsButton` uses the system's bordered style, which already draws a capsule at the large size. Not yet on the style: the empty states' Open Settings and Connect buttons, the sign-in, connecting and disconnecting views, and the buttons the item page's web editor draws itself.

## Keycaps

- Wherever MAPP draws a shortcut itself, it uses the palettes' keycaps: small and outlined, one glyph each, with no fill. Menus are the system's and keep its glyphs.
- The palettes' rows and bar, quick add's Add button and the value panel's Return hint on a create row draw them.

## Messages

- A toast rises at the bottom of the window, centered over the content (the column to the right of the sidebar, not the sidebar or the right sidebar), with Undo where an action can be undone. It never appears at the top of the page.
- It is a solid bar 44 points tall with 12-point corners: a symbol, the message, Undo as a small primary button and a close button. A window shows one at a time (`ToastPresenter`, held by the window's `DetailsPresentation`, so another workspace does not drop it and another window never shows it), and a new toast replaces the one showing.
- It leaves on its own after 5 seconds, since the design system gives no time. It waits while the pointer is over it, then starts its time again. It leaves at once when Undo or the close button is used. VoiceOver announces it.
- Undo runs the undo the action registered with the window's undo manager, once. It is bound to that step, not to its name (`StepUndo`): the move is registered in an undo group of its own, and the toast goes the moment any later step is registered, undone or redone (Edit > Undo or Redo included), so Undo never takes back something else. Where another undo group is already open the move shares it, and the toast offers no Undo. Edit > Undo still works after the toast has gone, and a failed undo is reported as it is without the toast.
- Items moved to Recently Deleted show it, by every route: the row and item actions, the palette, the Delete key, the menu command, the board and the gallery. One item says "Moved “Kitchen quotes” to Recently Deleted", naming it, or "Moved to Recently Deleted" when it has no name; several say how many. Deleting a collection will use it (Agreed designs).
- Left to build: the design boards (F11, L5) add a View button. The built toast has none yet, and has no other message than the move to Recently Deleted.
- A question before something that can't be undone is Apple's own alert, as today. MAPP draws none of its own.

## Related pages

- [Views and lists](views-and-lists.md)
- [Value components](value-components.md)
- [Agreed designs](agreed-designs.md)
- [Rejected designs](rejected-designs.md)
