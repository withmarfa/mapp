# Components

Status: Built, not yet released. The one button style and the keycaps below are drawn by one type each in the sheets, quick add, the value panels, the banners and the palettes. The last two Buttons lines say what is not on it yet.

Where it lives: `MappButtonStyle`, `MappButtonRole`, `MappButtonSize`, `FieldLabel`, `KeyCap` and `ShortcutKeys`, under `MAPP/Views/`.

The design system's Button component holds the exact fills and measures; `MappButtonStyle` reads them from there. What was turned down is in [Rejected designs](rejected-designs.md).

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

## Related pages

- [Views and lists](views-and-lists.md)
- [Value components](value-components.md)
- [Rejected designs](rejected-designs.md)
