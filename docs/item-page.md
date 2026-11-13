# Item page

Status: Built in v0.0.43.

Where it lives: `ItemPageHeader`, `PagePinsView` and `PageChip` for the header; `PropertyRow`, `PagePlacements`, `PageLayout` and `PagePins` for what the page shows; `ItemInspector` for the right sidebar; `ItemLayoutPanel` for arranging; `ValueEditing/` for editing a value; `VersionHistoryWorkspace` for history. The web part of the header is `editor/src/header.ts`.

The item page shows one item: its title, its pinned properties, its text and its property block. It is the same for every type, and each type decides only which properties go where.

## Header

- **The title** has no line under it. It shows two lines before it is cut, and Settings > Editor > Page Layout raises that to as many as five (`titleLines`).
- **Pins** sit directly under the title. A page pins at most four properties (`PagePlacement.pinLimit`). With no choice made, a type pins its own list first, then the status, the parent and the last edit. An event's time is the first pin and takes one of the four.
- A pin that holds a list shows its first value and "+N more" (`PagePins.listLimit`).
- A pin sits in a slot 150 points wide at 13-point text, so a pin stays in the same place from page to page. Pins wrap only where no slot is left.
- A pin with nothing to show reads as the grey word Empty where the person can set a value, and is left out where they cannot. No dotted place or placeholder box stands in for one.
- A pin's key carries the same icon as its row.
- The header's chips are the value components. See [Value components](value-components.md).

## Property block

The block lists the item's other properties under the pins, each a row with a key and a value.

- A value at rest in a row is cut after one line, or three for text and word lists.
- A page folds the block after six rows (`PropertyRow.foldAfter`), with Show N More to open the rest.
- Changes apply as made. A value edits in the panel described in [Value components](value-components.md).

The right sidebar (`ItemInspector`) always lists every property, in sections: Details, Properties, Relationships, Links in This Page, Linked From, Tags and others. Each section's open state is kept across items. The page may show fewer rows than the sidebar.

## Customize Layout

Customize Layout turns the right sidebar into the editor of the page's layout, for the item's type, and it applies to every item of that type. It is in the menu bar, the toolbar's More menu and the context menu.

- **Page** arranges the rows in three groups: Pinned (up to four), On the Page and Hidden. A person drags a row, uses the pin on a row, or chooses Move Up or Move Down.
- **Sidebar** orders, removes and adds the sidebar's own sections.
- Linked From has one setting, `linkedFrom`, that puts it at the foot of the page or in the sidebar. The sidebar's section order names it only while it is in the sidebar.
- Use Defaults takes back every choice for the type.
- The page and the sidebar stay in view and follow each change at once. The choice is MAPP's own, and it never changes the item, so a read-only item can be laid out too.

The choices are stored as `pagePlacements`. See [Settings storage](settings-storage.md). Layout is per type with no inheritance today; the agreed look store changes that. See [Looks](looks.md).

## Saved web pages

A page for a saved web page shows its description under the title (`ReadingHeader`). A Reader and Original switch sits in the toolbar for a page with an article.

## Version History

Version History opens as its own workspace (`VersionHistoryWorkspace`): a thread of versions (`VersionThreadColumn`) beside the page as it was (`VersionPageColumn`). The thread groups versions newest first under This Week, Last Week and then a heading for each month (`VersionThread`).

## Rules that hold on the page

- The row of actions above the title shows only while the pointer is over the header.
- A person's name and the status words are Marfa's. The look changes how they are drawn, not what they say.
- Dates follow the person's Date Format choice (`dateFormat`).

## Related pages

- [Value components](value-components.md)
- [Looks](looks.md)
- [Settings storage](settings-storage.md)
- [Rejected designs](rejected-designs.md)
