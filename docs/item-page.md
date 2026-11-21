# Item page

Status: Built in v0.0.43. Opening an item as a modal or a full page, and the page's corner (Focus, Aa on a text page, Reader or Original, an image's size, a PDF's page and size), are built, not yet released.

Where it lives: `ItemPageHeader`, `PagePinsView` and `PageChip` for the header; `PropertyRow`, `PagePlacements`, `PageLayout` and `PagePins` for what the page shows; `ItemInspector` for the right sidebar; `ItemLayoutPanel` for arranging; `ValueEditing/` for editing a value; `FieldMenu`, `FieldMenuPresenter` and `FieldEditSheet` for a field's menu; `VersionHistoryWorkspace` for history; `PageCorner`, `ItemCorner` and `FormatsCard` for the corner; `FileViewing`, `FilePagesControl`, `FileZoomControl` and `FileViewCommand` for an image's and a PDF's size and page. The web part of the header is `editor/src/header.ts`.

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
- A type with a latitude and a longitude shows one Location row in place of them, which opens a map to set the pin on. It can be pinned like any row, and a pinned Location shows the place's name. The numbers are rows of their own only while Show Coordinates is on. See [Composed properties](composed-properties.md).
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
- An item's Location is its name beside a small pin and opens the same map as the page's Location.
- Each kind of link is its own section.
- Copy in the sidebar is a few words, never several lines of guidance. A button's copy stays tight, such as "Restore Version".
- Pop-up arrows are gray, not blue.
- Chips sit in the same white box as the rows: the Tags section's tags and the chips of a property's value draw inside their section's box (`InspectorBox`), never loose on the sidebar's background.
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

A page for a saved web page shows its description under the title (`ReadingHeader`). The Reader and Original switch sits in the page's corner for a page with an article ([The page's corner](#the-pages-corner)), never in the toolbar. The byline above its title is agreed and not built; see Header.

## The page's corner

Built, not yet released.

The page's corner is the window's bottom-right corner (`WindowCorner`, [Views and lists](views-and-lists.md#the-bottom-right-corner)) on an item's page. It sits over the page and ends where the right sidebar begins. Its buttons are in `PageCorner.buttons`, and `ItemCorner` draws them.

- **Focus** is the last button on every item's page: a note, a task, an event, a document, a file and a web page. A list or a collection's browser has none. It moves the title into the toolbar, where it shows as the scrolled title does with the item's type under it ("Note"; for a PDF whose pages are counted, "PDF, 4 pages"), and hides the title and the properties, so the text gets the room. What follows the text stays: Linked From and a collection's Contents. The sidebar, the list, the right sidebar and the toolbar's buttons stay. The button is gray while Focus is on. The button again, Escape, or View > Leave Focus (⇧⌘F, also in the palette) leaves it. ⌃⌘F is the system's Full Screen, so Focus does not take it.
- **Focus belongs to one window and one item.** Choosing another item puts the page back in its normal look, and so does the item's page going away, as when the item is deleted. Customize Layout arranges the header Focus hides, so starting it ends Focus, and Focus waits until it is done.
- **Aa** is a glass button before Focus on every page that is the editor, such as a note, a task or an event. It opens the formats card above the buttons, solid, as wide as 340 points or the column allows. The card holds the text style (Title, Heading, Subheading, Body) as a row with the current one on a gray pill; bold, italic, strikethrough, highlight, code and link joined in one capsule; bulleted, numbered and checklist; quote, code block and table; a line; then Standard or Full Width beside smaller, actual and larger text. Each button runs the command the Format menu or the View menu runs, with no code of its own. A format the caret cannot take, and every format on a page that cannot be written, is dimmed. Aa shows only where the page is the editor. The Format toolbar item is gone; Bold, Italic and the two lists stay in the toolbar's tray, and the Format menu stays. View > Show Formats is the menu command.
- **Escape** closes the formats card first, and leaves Focus on a second press, whether the keyboard is in the page or in the window's other columns. The command palette, quick add and a sheet keep Escape for themselves. The card closes by itself when the item changes.
- **A web page or newsletter with a Reader view** has Reader or Original as the system's segmented control, as the Calendar's Week or Month is, before Focus. The switch is not in the toolbar. A web page with no Reader view has no switch.
- **An image** has one size control before Focus: the size as a percentage, such as "100%", with a chevron that opens a menu. The menu holds Fit, then 50%, 75%, 100%, 150% and 200% with the chosen one ticked, then Zoom In and Zoom Out. Clicking the percentage opens a small field to type a size in: Return applies it, Escape or a click elsewhere cancels it, and a size outside 10% to 400% takes the nearest end (the field's help names the range). Thousands separators follow the system's region, so "1,000" is read as a thousand where the region groups with a comma. Something that is not a number leaves the field open in red. The image opens fitted, and the control then reads the size Fit gives, such as "34%". Fit never enlarges a picture past 100%, so a small picture opens at "100%". 100% is the picture's own pixels as points. The bitmap is held to 3,000 pixels a side, so a larger picture is softer past 50%. The header row's three zoom buttons are gone.
- **A PDF** has the page as "2 of 4" between up and down chevrons, then the same size control, then Focus. The chevrons are dimmed at the first and last page, and a one-page PDF reads "1 of 1" with both dimmed. The page follows scrolling. Typing a page number is not offered. The size is the PDF view's own: Fit fits the width, held to 10% to 400%, and a pinch becomes the chosen size. The page reads the page the view reached.
- **A file that is still downloading, fails to load or has no pages** has Focus alone until the file is ready, and so has any file that is neither an image nor a PDF.
- **The size belongs to one file.** Another item's page opens fitted, and an open size field goes with the item it was opened on.
- **Menu and palette.** While an image or PDF page shows, View holds Zoom In (⌘+), Zoom Out (⌘−), Actual Size (⌘0) and Zoom to Fit, and for a PDF Next Page and Previous Page, with the same entries in the palette. These keys size the file and the text-size commands (`TextZoomCommands`) are not offered then, so a key sizes the file or the text and never both. Settings > Appearance still holds the interface's text size. The corner's own menu binds no keys, because the View menu's commands hold them.
- **Any other item's page** has Focus alone.

Focus hides only the header's title and properties. The page keeps its look (a reading page stays in its reading type) and the footer, so Linked From and a collection's Contents stay, and a collection with nothing in it still shows its contents.

Open: a symbol of Focus's own. The corner uses the system's full-screen arrows for now.

## Version History

Version History opens as its own workspace (`VersionHistoryWorkspace`): a thread of versions (`VersionThreadColumn`) beside the page as it was (`VersionPageColumn`). The thread groups versions newest first under This Week, Last Week and then a heading for each month (`VersionThread`), in blocks on the sidebar's gray under a large title.

- The thread takes the place of the window's left sidebar, which hides while history shows.
- Cancel and Restore Version are toolbar items before the right sidebar's toggle (`VersionHistoryWorkspace`). The agreed placement is over the right sidebar at the full glass height, never over the page. Restore Version is blue only when it can restore, and gray glass otherwise. Right-clicking a version also offers Restore Version.
- The right sidebar's sections (This Version, Changed Here, Changed Since) have no chevron, and each value sits just after its label. A changed title reads Changed, and a text change reads a count of added and removed words.
- On the page, added words are tinted with the accent color, and removed words are gray and struck through. The page shows the version with its normal pins, and a status reads as plain text.

## Text on the page

- **Link looks** are a setting (Settings > Editor > Links, `LinkLook`), and Mark is the default. Mark is the type's icon in color, then the title with a dotted line. The others are Underline, Tinted Pill, Pill, Quiet and Text. In every look the pointer is a hand, and a link to an item that does not exist keeps its dashed line, which Mark draws as lighter dots.
- **Highlights** are soft yellow, or the color chosen in Settings > Appearance > Highlights: orange, green, blue, pink, purple or the accent color ([Settings](settings.md#appearance)). A color of the person's own is not offered. A pen-style highlight is dropped.
- **Tables** in the text are a box with a gray header and lines between the columns, with lighter grips and more room above. Inkkit draws them, and MAPP sets only their spacing, grip color and header through Inkkit's tokens (`editor/src/style.css`). The header's weight is 500 today; the agreed weight is regular.
- **A caption** under a picture is light gray, and a file's name is a link with a hover state. Agreed, not built.
- **Every look is a setting with a default.** MAPP gives Inkkit the look it draws with.

## Code blocks and files in the text

A code block and a file in an item draw their actions as icons in a corner of the block, with no words, and the words are the icon's name for VoiceOver and the hover. Inkkit draws them; MAPP chooses which. A code block's actions are Inkkit's own (copy and wrap), and where its language goes is still open.

- A file card's corner holds Quick Look, then Open. Quick Look is an eye, drawn from MAPP's own image (`editor/src/file-actions.ts`) and named for the file, such as "Quick Look Budget.csv".
- The card asks the app through the `quickLookEmbed` message, with the item and the embed's text exactly as written. The app answers from what Marfa's core bound that text to (`EditorController.quickLookEmbed`) and shows the library's kept copy in the shared Quick Look panel, which one window holds at a time. A reference to another item than the one on the page, or one the library no longer binds to a file, shows nothing and tells the person why. The item's text is never changed.
- A card that is missing or could not be read has no Quick Look. A PDF's card has it.

## Change Type

Change Type is a panel like status (`CommandValuePanels`), opened from the page's type chip or from the command. It is never a sheet or a menu.

## A field's menu

A field's name on the page opens its menu (`FieldMenu`, drawn by `FieldMenuPresenter`): Rename Field, Edit Choices, Pin Under the Title, Move Up, Move Down, Hide on the type's pages (named, as Hide on Job Pages) and Remove Field, which is red, with Edit Value first where only the menu reaches the value, as for a link. The web header sends the row and the name's rectangle, and the app opens the menu under it.

- **Mac's own.** Pin, Move Up, Move Down and Hide are the item type's placement on this Mac (`PagePlacements`). They write nothing to Marfa, and a lock does not stop them.
- **Marfa's.** Rename Field, Edit Choices and Remove Field change the type for every item in every app (`FieldEditing`, `TypeDefinitionEdit`). They need the server and are never queued. MAPP reads the type again just before it sends the change, and refuses it if the field no longer matches what the page showed. The server takes no version with a change, so another app's change that lands between that read and the write is overwritten.
- **What a person may change.** A field the type declares itself and no type above it does. An inherited field, including one a child redeclares to require it or narrow its choices, shows a lock and the type it comes from, and a type Marfa provides (`core`, `system`, `marfa`) is locked whole. The title, text and source-link fields can be renamed but not removed.
- **Rename** changes the field's label only, to a name no other field has, of 100 characters at most. A key is never renamed, because Marfa carries no values to a new name.
- **Edit Choices** adds, orders and takes out choices; a choice the field already offers is shown as text and never retyped. Items that hold a choice taken out keep it. The last choice can't be taken out.
- **Remove Field** asks first (an alert) and says the items keep their values, which an app can still read.

## Opened as a modal or a full page

Built, not yet released. Where an item opens is Settings > General > Open Items ([Views and lists](views-and-lists.md#opening-an-item)).

- A modal is a large, solid page over the window, with the window dimmed behind it (`ItemModal`). It is 1000 points wide, centered, with 60 points above and below; the right sidebar adds its own width to the card, as far as the window has room, and the page keeps nearly its width. Customize Layout opened in it shows Done in place of the Details button. It hosts the same page the window shows, with the window's one editor, so no second editor writes the item: the page beside the list steps aside while the modal is open.
- The modal's toolbar holds, from the leading side: up and down arrows, full page and new window, Share and More, the right sidebar (filled while it is open), and close. The up and down arrows move to the item before or after it in the list behind, and the selection follows, and Back does not stop at each item stepped over. They are dimmed at the first and last item. The right sidebar opens inside the modal.
- Escape, the close button and a click on the dimmed area close the modal, and what was typed is saved as it closes. The modal also closes when another item, place or layout is chosen, when Version History opens, and when its item is gone from the library, and a search puts it, or a full page, away in every layout. An item that leaves the list while the modal is open closes it with the selection that held it.
- New window from the modal closes it and opens the item in a window, after saving what was typed.
- A link followed from the modal opens in the modal.
- A full page takes the window in place of the layout, with a plain Back button at the toolbar's leading edge. The button has no label; Back in the View menu and Command-[ do the same. It is available from the list as well as from the other layouts. A full page has no view options.

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
