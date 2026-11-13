# Item page

Status: Built in v0.0.43.

Where it lives: `ItemPageHeader`, `PagePinsView` and `PageChip` for the header; `PropertyRow`, `PagePlacements`, `PageLayout` and `PagePins` for what the page shows; `ItemInspector` for the right sidebar; `ItemLayoutPanel` for arranging; `ValueEditing/` for editing a value; `VersionHistoryWorkspace` for history. The web part of the header is `editor/src/header.ts`.

The item page shows one item: its title, its pinned properties, its text and its property block. It is the same for every type, and each type decides only which properties go where.

## Header

- **The title** has no line under it. It shows two lines before it is cut, and Settings > Editor > Page Layout raises that to as many as five (`titleLines`).
- **Pins** sit directly under the title, with nothing between the title and the pins. A page pins at most four properties (`PagePlacement.pinLimit`). With no choice made, a type pins its own list first, then the status, the parent and the last edit. An event's time is the first pin and takes one of the four, so no event page has a date tile.
- A pin that holds a list shows its first value and "+N more" (`PagePins.listLimit`). Its help carries every value. A pin that is too long is cut with an ellipsis and shows whole on hover.
- A pin that is stale, or that the header draws itself, is not drawn, and a stale one stays in storage. A pinned row is not also in the property block, and the pin an event's time pushes out goes back to the block.
- A pin sits in a slot 150 points wide at 13-point text, so a pin stays in the same place from page to page. Slots fill a row while another fits and wrap only where none does, by the width of the page's column and not the window's.
- A pin with nothing to show reads as the gray word Empty where the person can set a value, and is left out where they cannot. No dotted place or placeholder box stands in for one.
- A pin's key carries the same icon as its row, at the key's size. Every value is 13-point text whatever its kind, and the label column of a row is 120 points wide.
- Nothing repeats a logo beside a key that already shows it.
- A person's email and phone are rows of the property block that open a mail or phone link, never chips in the header.
- The header's chips are the value components. See [Value components](value-components.md).

Agreed, not built:

- Type, source and updated are the default pins, in place of the defaults above.
- A pin shows at most two labels or people before "+N", and the gaps between pins stay tight so that four fit as often as possible. Today a pin shows one.
- When four slots do not fit a row, two do. Today the row takes as many as fit.
- A cover or a picture sits beside the title: a wide picture stays low (280 points), and a square or tall one is smaller. There is no landscape cover for now. The text under a cover is the page's own text.
- A banner is a component only. Where it lives (an item, an extension, a type or a view) is open.
- A document is drawn as paper on a gray surface, with the paper's edge on the title's, and a document's pages take the list pane's place.
- A viewer's zoom shows the percentage only, and a full-screen picture closes from the right. Viewers are experimental.
- A page for a saved web page shows only a byline on the line above its title.

## Property block

The block lists the item's other properties under the pins, each a row with a key and a value.

- A value at rest in a row is cut after one line, or three for text and word lists. A value in a Details cell of the right sidebar keeps to two lines (`InspectorMetrics.cellValueLines`). The agreed rule is two lines in every row, with the whole value in the right sidebar.
- A page folds the block after six rows (`PropertyRow.foldAfter`), with Show N More to open the rest.
- Changes apply as made. A value edits in the panel described in [Value components](value-components.md).
- A row's symbol sits in a fixed frame, so every label shares one left edge.
- A pinned property appears at the top of the page, and an unpinned one does not. No placeholder stands in for a pin.
- An empty value is the gray word Empty, never a bordered plus button.
- Agreed, not built: under the pointer, a row shows only Copy. Today Copy is in the row's menu.

## Right sidebar

The right sidebar (`ItemInspector`) always lists every property, in sections: Details, Properties, Relationships, Links in This Page, Linked From, Tags and others. Each section's open state is kept across items. The page may show fewer rows than the sidebar.

- Each section is a grouped box on the sidebar's background, under a label that reads its name and then its count. The chevron that folds the box is trailing, at the far end of the row.
- Inside a grouped box, dividers stop short of both edges.
- Details holds its facts as cells.
- Each kind of link is its own section.
- Copy in the sidebar is a few words, never several lines of guidance. A button's copy stays tight, such as "Restore Version".
- Pop-up arrows are gray, not blue.
- Agreed, not built: a place is a name and an arrow with no extra copy, and bento cells may sit among the sections.

## Customize Layout

Customize Layout turns the right sidebar into the editor of the page's layout, for the item's type, and it applies to every item of that type. It is in the menu bar, the toolbar's More menu and the context menu.

- **Page** arranges the rows in three groups: Pinned (up to four), On the Page and Hidden. A person drags a row, uses the pin on a row, or chooses Move Up or Move Down.
- **Sidebar** orders, removes and adds the sidebar's own sections.
- Linked From has one setting that puts it at the foot of the page or in the sidebar. The sidebar's section order names it only while it is in the sidebar.
- Use Defaults takes back every choice for the type. It sits quietly in the Layout Options menu beside the first heading. There is no footer of Done and Use Defaults, and no bar across the window.
- The mode finishes from the system's blue Done button, which takes the Details button's place. Customize Layout is offered only while a page is showing.
- Page and Sidebar is the system's segmented control, as wide as the boxes under it.
- In Sidebar, a row has a handle, the section's name and count, and a minus in a circle. A dashed Add Section opens its list under it, and From Apps appears only where real linked data exists.
- The page and the sidebar stay in view and follow each change at once. The choice is MAPP's own and changes no item, so a read-only item can be laid out too; the rule for code is in [`MAPP/Model/AGENTS.md`](../MAPP/Model/AGENTS.md).

The choices are stored as `pagePlacements`. See [Settings storage](settings-storage.md). Layout is per type with no inheritance today; the agreed look store changes that. See [Looks](looks.md).

## Saved web pages

A page for a saved web page shows its description under the title (`ReadingHeader`). The Reader and Original switch sits in the window's toolbar for a page with an article, never on the page. The byline above its title is agreed and not built; see Header.

## Version History

Version History opens as its own workspace (`VersionHistoryWorkspace`): a thread of versions (`VersionThreadColumn`) beside the page as it was (`VersionPageColumn`). The thread groups versions newest first under This Week, Last Week and then a heading for each month (`VersionThread`), in blocks on the sidebar's gray under a large title.

- The thread takes the place of the window's left sidebar, which hides while history shows.
- Cancel and Restore Version are toolbar items before the right sidebar's toggle (`VersionHistoryWorkspace`). The agreed placement is over the right sidebar at the full glass height, never over the page. Restore Version is blue only when it can restore, and gray glass otherwise. Right-clicking a version also offers Restore Version.
- The right sidebar's sections (This Version, Changed Here, Changed Since) have no chevron, and each value sits just after its label. A changed title reads Changed, and a text change reads a count of added and removed words.
- On the page, added words are tinted with the accent color, and removed words are gray and struck through. The page shows the version with its normal pins, and a status reads as plain text.

## Text on the page

- **Link looks** are a setting (Settings > Editor > Links, `LinkLook`), and Mark is the default. Mark is the type's icon in color, then the title with a dotted line. The others are Underline, Tinted Pill, Pill, Quiet and Text. In every look the pointer is a hand, and a link to an item that does not exist keeps its dashed line, which Mark draws as lighter dots.
- **Highlights** are yellow. Agreed, not built: soft yellow, the accent color and a color of the person's own are settings. A pen-style highlight is dropped.
- **Tables** in the text are a box with a gray header and lines between the columns, with lighter grips and more room above. Inkkit draws them, and MAPP sets only their spacing, grip color and header through Inkkit's tokens (`editor/src/style.css`). The header's weight is 500 today; the agreed weight is regular.
- **A caption** under a picture is light gray, and a file's name is a link with a hover state. Agreed, not built.
- **Every look is a setting with a default.** MAPP gives Inkkit the look it draws with.

## Change Type

Change Type is a panel like status (`TypeChangePanel`), opened from the page's type chip or from the command. It is never a sheet or a menu.

## Spacing

Gaps on the page come from a 4-point step, with named gaps between the title and the pins, the pins and the properties, and the properties and the text. The values are a first pass that the screens may change.

## Rules that hold on the page

- Linked From and Customize Layout live in a row of actions above the title that takes no room. When it shows is in [`editor/AGENTS.md`](../editor/AGENTS.md).
- A person's name and the status words are Marfa's. The look changes how they are drawn, not what they say.
- Dates follow the person's Date Format choice (`dateFormat`).

## Related pages

- [Value components](value-components.md)
- [Looks](looks.md)
- [Settings storage](settings-storage.md)
- [Rejected designs](rejected-designs.md)
