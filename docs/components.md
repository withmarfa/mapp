# Components

Status: Built, not yet released. The one button style and the keycaps below are drawn by one type each in the sheets, quick add, the value panels, the banners and the palettes. The last two Buttons lines say what is not on it yet. The toast is built for items moved to Recently Deleted; the Messages lines say what is left.

Where it lives: `MappButtonStyle`, `MappButtonRole`, `MappButtonSize`, `FieldLabel`, `KeyCap` and `ShortcutKeys`, under `MAPP/Views/`; `ToastView` there and `ToastPresenter` and `StepUndo` under `MAPP/Model/`.

The design system's Button and Toast components hold the exact fills and measures; `MappButtonStyle` and `ToastView` read them from there. What was turned down is in [Rejected designs](rejected-designs.md).

## Buttons

- Every button that MAPP draws is a rounded rectangle, at two sizes: 22 points with 7-point corners, and 28 points with 9-point corners. Only an icon-only button and the toolbar's glass buttons are round.
- **Primary** uses the accent color, at most once on a surface, at the trailing edge. **Secondary** has a pale gray fill. **Plain** has no fill until the pointer is over it.
- **Destructive** is the secondary button in red: a pale red fill and red text, never solid red. It is never the default button, so Return never deletes.
- Keyboard focus is a gray ring, never blue.
- A menu among buttons is an outlined button with a chevron, the same height as the buttons beside it.
- A sheet puts a destructive action alone at the leading edge, and Cancel and the primary action at the trailing edge. A text field has its label above it, such as Name. The button reads Delete, not Delete Collection.
- The toolbar's glass buttons, the system's menus, alerts and text fields, and a Settings page's own controls stay the system's.
- Not yet on the style: the empty states' Open Settings and Connect buttons, the sign-in, connecting and disconnecting views, the file pages' Open and zoom buttons, and the buttons the item page's web editor draws itself.

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
- [Rejected designs](rejected-designs.md)
