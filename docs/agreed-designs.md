# Agreed designs, not built yet

Status: Agreed, not built. Each design is drawn on MAPP Pages, and the MAPP design system holds its components. When a design is built, move its section to the page for its area and delete it here.

Where it lives: not built yet.

This page lists what has been agreed for MAPP and is not in the app yet, so the next build starts from one list. What was turned down is in [Rejected designs](rejected-designs.md).

## The sidebar

- The sidebar has one tab by default, with no tab bar. Once a person adds a second tab, tabs show at the top: the chosen tab shows its name, and a plus button adds one.
- A person customizes the sidebar from a Control-click on it (Customize Sidebar), which is built first, and in Settings > Sidebar. There is no button for it in the sidebar.
- While the sidebar is being customized, each row and section has a handle at its trailing edge, so the rows keep their places and the handles never crowd the marks. Each section has a menu: Show, Rename, Move Up, Move Down, Move to Tab and Hide Section. Add Shortcut and Add Section appear, and Done ends it.
- Any section can hold views, collections and sources.
- A view's mark is its symbol in its own color, with no tile. A person chooses the color from the view's context menu, a row of color dots, or in Settings > Sidebar. The color is kept on this Mac.
- A new library's shortcuts are New and Search. No shortcut makes an item of a type the person made.

## Items as an index

- Items is an index page like Collections and Sources: a table with no list column. Views and types keep the list column.
- Items has the tabs All, Yours (the library tier) and From Apps (the feed tier), and New Item on the page at the trailing edge of the tabs.
- The chosen item shows in the right sidebar, with Open.
- Tabs and a New button on the page appear only on the three index pages: Items, Collections and Sources. A view or a type is split by the sidebar, its filters and saved views, and New is the sidebar's New and Command-N.

## Making an item

- New Item on Items, the sidebar's New and Command-N open quick add, as built, in the type last used.
- New in a type's list opens quick add holding that type, its status and the fields it asks for.
- Quick add's main button is Add and Open: the new item opens the way Settings > Lists > Open Items In says, with the insertion point in its text.

## Opening an item

- Return, a double-click and Open open an item the way Settings > Lists > Open Items In says: **Modal** (the default), **Full Page** or **New Window**.
- A modal is a large page over the screen, which dims behind it. Its toolbar has full page, new window, Share, More and close.
- A full page takes the window, with a plain Back button at the toolbar's leading edge. The button has no label.
- An item can always open in a window of its own.
- The modal's toolbar starts with up and down arrows, which move to the item before or after it in the list behind. The right sidebar opens inside the modal.
- Every layout opens an item the same way: a table, board, gallery, timeline or calendar. A list with the page beside it keeps the page there.
- A row's context menu starts with Open, which follows the setting, then the other two ways (Open as Full Page, Open in New Window). Quick Look, Share, Add to Favorites, Tag, Add to Collection and Delete follow.

## Views

- Every place opens in a default view. A person can change the default view, but can't rename or delete it.
- Save as View… makes a second view with a name. It is the last item of View Options, shown only when there is something to keep. It is never in the toolbar. It opens New View's panel, filled in.
- Once a default view is changed, View Options offers Reset View above Save as View…, which puts it back.

## The toolbar and the bottom-right corner

- The toolbar holds the same buttons on every screen: Search, View Options, View As, Share, More and the right sidebar. A screen hides a button that does not apply. No screen adds its own controls to the toolbar.
- The page holds at most one main action, such as New Collection.
- The bottom-right corner of the window holds only how a person views the screen, as glass buttons like the toolbar's, each on its own. A card the corner opens, such as the month or the formats, opens above the buttons, which stay. The card is solid.
- The corner holds nothing that changes items, and it is empty on a screen with nothing to set, such as most lists. Every control in the corner and the toolbar is also a menu command.
- A corner button that is on is gray, never the accent color.
- **Focus** is the last button in the corner on every item's page, documents and web pages included. It moves the title into the toolbar and hides the properties, so the text gets the room. The sidebar, the list and the toolbar's buttons stay. The button again, or Escape, leaves it.
- What each screen's corner holds:
  - **Calendar:** Today, back and forward, Week or Month, and a month button. The month opens above the buttons at their width, with this week marked in gray. Choosing a day goes to its week. In a narrow window, Week or Month folds into one button with a menu.
  - **Note:** Aa, which opens the formats: the text style (Title, Heading, Subheading, Body) as a row; bold, italic, strikethrough, highlight, code and link; bulleted, numbered and checklist; quote, code block and table; then Standard or Full Width beside smaller, actual and larger text. Format leaves the toolbar; the Format menu stays. Then Focus.
  - **Image:** one zoom control, 100% with a menu that holds Fit and sizes. Clicking 100% lets a person type a size.
  - **PDF:** the page as "2 of 4" with arrows, the same zoom control, and Focus.
  - **Gallery:** the card size by name, such as Medium, with a menu.
  - **Timeline:** Today.
  - **A web page or newsletter with a Reader view:** Reader or Original, as one glass segmented control. The switch leaves the toolbar. A web page with no Reader view has no switch.
  - **Any other item's page:** Focus alone.

## Menus and empty states

- The menu bar holds every command the toolbar, the corner and the row menus offer.
- Go lists the places (Items, Sources, Collections, Inbox, Recents, Favorites), then the saved views and the types, as the sidebar holds them, with All Types for the rest.
- View holds the corner's commands with the view's own: on the Calendar, Today, Previous Week, Next Week, Week, Month and Show Month, with keyboard shortcuts. Recently Deleted leaves the View menu.
- Help holds MAPP Help, Keyboard Shortcuts, What's New in MAPP, Marfa Documentation and Report a Problem…, after the system's search field.
- An empty state has a title, one line under it of fewer than 40 characters, and a button only when there is something to do there. Items has none, since New Item is already on the page. A type has New and its name, such as New Project. Favorites and Inbox have no button.
- Recently Deleted is a page in Settings only, not a sidebar place.
- The corner's cards and the item's modal are solid. The palettes keep the material chosen in Settings > Appearance.

## Editing in place

- Add Tag and Add to Collection use the value panel under the value, as every other value does, not a sheet.
- A status's value panel ends with Edit Statuses, which opens the type in Settings > Types.
- A field's name on the page opens its menu: Rename Field, Edit Choices, Pin Under the Title, Move Up, Move Down, Hide on the type's pages, Edit the type in Settings, and Remove Field.
- A person edits only what Marfa allows: the words and fields a type adds itself. Inherited ones show a lock and the type they come from. A core type can't be changed, so a person adds words on a type of their own.

## Pages

- A code block and a file in an item show their actions as icons in a corner, under the pointer, with no words. Where a code block's language goes, and how it changes, is open.
- In the right sidebar, chips sit in the same white box as the rows.

## Settings

- Settings keeps its structure: the app's sidebar, the Settings list, then the page.
- A page is a column of sections. Each section has its title outside one card of rows. A row's description is one line, two at most.
- Settings > Sidebar is agreed: the tabs, each tab's sections, and the views with their colors. The other pages are being redesigned.

## Still open

- A cover picture on an item's page, and how Marfa would hold the choice of cover. It is parked.
- How the corner's controls are drawn on pages for each kind of item, such as a newsletter at its own width.
- A full-screen view beside Focus. Not now.
- A symbol of Focus's own. The boards use the system's full-screen arrows for now.

## Related pages

- [Rejected designs](rejected-designs.md)
- [Views and lists](views-and-lists.md)
- [Item page](item-page.md)
- [Components](components.md)
- [Value components](value-components.md)
