# Agreed designs, not built yet

Status: Agreed, not built. Each design is drawn on MAPP Pages, and the MAPP design system holds its components. When a design is built, move its section to the page for its area and delete it here.

Where it lives: not built yet.

This page lists what has been agreed for MAPP and is not in the app yet, so the next build starts from one list. What was turned down is in [Rejected designs](rejected-designs.md).

## Buttons

- Every button that MAPP draws is a rounded rectangle, at two sizes: 22 points with 7-point corners, and 28 points with 9-point corners. Only an icon-only button and the toolbar's glass buttons are round.
- **Primary** uses the accent color, at most once on a surface, at the trailing edge. **Secondary** has a pale gray fill. **Plain** has no fill until the pointer is over it.
- **Destructive** is the secondary button in red: a pale red fill and red text, never solid red. It is never the default button, so Return never deletes.
- Keyboard focus is a gray ring, never blue.
- A menu among buttons is an outlined button with a chevron, the same height as the buttons beside it.
- A sheet puts a destructive action alone at the leading edge, and Cancel and the primary action at the trailing edge. A text field has its label above it, such as Name. The button reads Delete, not Delete Collection.

## Selection and hover

- A chosen row, card or table row is gray at 8% of the label color, and a row under the pointer is gray at 4.7%. Neither is ever blue.
- A chosen gallery card keeps a soft 3-point ring in the same gray.
- A table row under the pointer shows its open control as the arrow alone.

## Keyboard shortcuts and messages

- Wherever MAPP draws a shortcut itself, it uses the palettes' keycaps: small and outlined, one glyph each, with no fill. Menus are the system's and keep its glyphs.
- A toast rises at the bottom of the window, centered over the content, with Undo where an action can be undone. It never appears at the top of the page.
- A question before something that can't be undone is Apple's own alert, as today.

## The sidebar

- The sidebar has one tab by default, with no tab bar. Once a person adds a second tab, tabs show at the top: the chosen tab shows its name, and a plus button adds one.
- A person customizes the sidebar from a Control-click on it (Customize Sidebar), which is built first, and in Settings > Sidebar. There is no button for it in the sidebar.
- While the sidebar is being customized, each row and section has a handle at its trailing edge, so the rows keep their places and the handles never crowd the marks. Each section has a menu: Show, Rename, Move Up, Move Down, Move to Tab and Hide Section. Add Shortcut and Add Section appear, and Done ends it.
- Any section can hold views, collections and sources.
- A view's mark is its symbol in its own color, with no tile. A person chooses the color from the view's context menu, a row of color dots, or in Settings > Sidebar. The color is kept on this Mac.
- A new library's shortcuts are New and Search. No shortcut makes an item of a type the person made.

## Collections and Sources

- Collections and Sources are one kind of page, an index of containers, drawn as a table.
- Collections has the tabs All, Yours (the library tier) and From Apps (the feed tier). Sources has All, Apps (signed in) and Keys.
- A collection's icon is gray. A type's icon in a table is in the type's color, with no tile.
- The chosen container shows in the right sidebar, with no buttons there. The table takes the window's width when the right sidebar is closed.
- Deleting a collection asks with Apple's alert, then shows the toast with Undo.
- Where Search and New Collection go is decided with the toolbar.

## Editing in place

- Add Tag and Add to Collection use the value panel under the value, as every other value does, not a sheet.
- A status's value panel ends with Edit Statuses, which opens the type in Settings > Types.
- A field's name on the page opens its menu: Rename Field, Edit Choices, Pin Under the Title, Move Up, Move Down, Hide on the type's pages, Edit the type in Settings, and Remove Field.
- A person edits only what Marfa allows: the words and fields a type adds itself. Inherited ones show a lock and the type they come from. A core type can't be changed, so a person adds words on a type of their own.

## Pages

- A code block and a file in a note show their actions as icons in a corner, under the pointer, with no words. Where a code block's language goes, and how it changes, is open.
- In the right sidebar, chips sit in the same white box as the rows.
- The favorites mark is a heart everywhere. The gallery card, the table and the note's actions still draw a star.

## Settings

- Settings keeps its structure: the app's sidebar, the Settings list, then the page.
- A page is a column of sections. Each section has its title outside one card of rows. A row's description is one line, two at most.
- Settings > Sidebar is agreed: the tabs, each tab's sections, and the views with their colors. The other pages are being redesigned.

## Still open

- The toolbar's look, and what it holds in each place.
- The corner at the bottom right of the window.

## Related pages

- [Rejected designs](rejected-designs.md)
- [Views and lists](views-and-lists.md)
- [Item page](item-page.md)
- [Value components](value-components.md)
