---
summary: The rules of the sidebar, toolbar, corner, menus, palettes, opening an item, the modal and item links.
paths:
  - MarfaMac/Model/Place.swift
  - MarfaMac/Model/Sidebar*.swift
  - MarfaMac/Model/ItemOpening.swift
  - MarfaMac/Model/ItemLink*.swift
  - MarfaMac/Model/Palette*.swift
  - MarfaMac/Views/Sidebar*.swift
  - MarfaMac/Views/Window*.swift
  - MarfaMac/Views/ItemModal.swift
  - MarfaMac/Views/CommandPalette*.swift
---

# The window

`docs/look.md` has the window's areas. `docs/commands.md` has every command and shortcut.

## Places

- **A window shows a place and one of its views** (`PlaceView`, `Place`, `ViewChoice`), each stored as a word. An unknown word is kept as written, and an unknown view reads as the place's own.
- **A window left in a place this copy cannot read** opens where a new window would, and keeps that place until the person moves (`Browser.laterPlace`).
- **A window follows its view to a new place,** with what it keeps for the view (`PlaceMemory`). Views sort by the app's order, a synced `viewOrder` row (`ViewOrders`), then title.
- **A window's snapshot and Start With have slots of their own** (`window`, `opening`, `openingLastPlace`). An earlier window of a place that still exists keeps its open item and scroll position, and one favorite opens where that item is listed. Files is no place: the person is told once.

## Sidebar

- **A person arranges the sidebar in place** (`SidebarLayout`): tabs, sections, order, colors and what is hidden. A place the layout does not name, such as a new type, shows after the rest.
- **A row whose thing is gone keeps its place in the layout**, so a thing that comes back, or is late in a sync, returns to where it was.
- **A shortcut acts, or goes somewhere, and is not a place** (`SidebarShortcut`). Search and New are shortcuts.
- **A row's menu is AppKit's** (`SidebarPlaceMenu`), because SwiftUI menus cannot hold the color swatches.
- **Go lists the same places, views and types** (`GoMenu`), hidden types too, so a window without its sidebar reaches them.
- **A sidebar row opens a place or one of its views.** A saved view opens at its home ([Two kinds of view](lists.md#two-kinds-of-view)).
- **The Library and the Feed keep the keys earlier copies gave All Items and Inbox** (`all`, `inbox`), so an arranged sidebar reads unchanged. A Recents row reads as nothing and stays stored. A section of a kind this copy does not know is left out alone and written back where it was; with only those, the sidebar shows no sections.
- **Recently Deleted is a page of Settings**, never a row.

## Toolbar

- **The top row is drawn in the content under a title the window hides** (`TopRowFrame`). A plain `toolbar` holds only the buttons: Search, View and Panel on a list; Favorite, Share and More as a group, then Panel, on a page.
- **One row serves every place and layout** (`TopRowContent`): title, count on its baseline, the control, then the views as pills. The count is part of the title's label.
- **The control** (All Items, Library, Feed) shows only where the place has Feed items, never on the Library's or the Feed's own page, and is quiet while it says Settings' default.
- **The views** scroll away with the rows and then stand beside the title; a calendar and a board have them there from the start.
- **The row folds by the room it has** (`TopRowFold`): the control, the Library's places into Browse, the views into N More, then one pill. It measures the toolbar (`ToolbarRoomProbe`) and holds no width.
- **A page's row is empty until its head has scrolled away,** then the item's title (Appearance > Title When Scrolling).
- **An on button is gray, never the accent.** An item that cannot act dims.
- **Trap:** hide the title on the window (`hidesWindowTitle`), or it returns in full screen. The row has its own drag and double click, and leaves the accessibility tree once scrolled away.

## Sidebar closed

- **The place, its views and the buttons share one row** beside the traffic lights, with Back and Forward kept. The title opens the sidebar's rows as a menu (`PlacesMenu`).

## Smallest window

- **The main window goes down to 760 by 520.** The panel folds under 1000 wide, the sidebar under 900, then the control, the views and a table's columns. Only what the window folded opens again.
- **The panel is 300 wide,** dragged within 260 to 440.

## Corner

- **The corner holds only controls for viewing** the page or list in front (`WindowCorner`, `PageCorner`): formats, text size, focus, zoom, pages. A command never goes there.
- **A control the person turned off in Settings is in More instead.**
- **The modal has no corner.**

## Menus and palettes

- **Every menu of items is one menu** (`ItemRowMenu`), in every layout.
- **The palette has the menu bar's commands under its headings, then items and places** (`CommandPalette`). Search Items is the same panel searching titles and text. Palette Actions lists what can be done with the chosen row.
- **Trap:** Actions grows out of the palette's bar with an ordinary transition, because a Liquid Glass morph hung the app.
- **A command that takes the keyboard says so** (`takesFocus`), so the palette does not give it back to the page first.

## Opening an item

- **Open, Return, a double click and a link follow Open Items** (`ItemOpening`), and the menu offers the other ways.
- **A modal and a full page show one item.** New Window takes several and asks first above a limit (`ItemWindows`).
- **The modal hosts the same page with the window's one editor** (`ItemModal`), so two editors never write one item. The page beside the list steps aside.
- **Escape, Close and a click outside save and close the modal.** Up and down follow the list behind it (`ListNeighbors`), and a link followed in it stays in it.
- **A full page's Back returns to the layout**, and the list's view options are not offered over it.

## Item links

- **An item's app link is `marfa://`, its Marfa's id, then its own,** both exact and lowercase (`ItemAppLink`). Any other form is refused.
- **A link only opens.** It never writes, signs in, changes a setting or calls the server, because any app or web page can send one.
- **It opens only when** the Marfa it names is the connected one, the copy holds the item, and the item is not in Recently Deleted. Otherwise the person is told why (`ItemLinkRoute`).
- **It opens in the main window last in front** (`ItemLinkOpener`), as a full page where Open Items says so and over the list otherwise. With no window open, one is opened.
- **The newest link wins** over one that waits for the library or a window. The link is decided again when a window takes it.
- **Copy Link copies the server's `https` address**, and the `marfa://` one where the server gives none. Copy Wiki Link copies the text form.
- **Trap:** a Debug test build registers another scheme (`ITEM_LINK_SCHEME`), so it never takes the installed app's links.
