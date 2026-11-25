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

- **Search and New, the Library and the Feed, then Pinned, Types and the person's sections** (`SidebarLayout`). Only the Library has a count; Search opens the palette.
- **Pinned holds views, collections and items.** A saved view stays pinned until taken out.
- **A type counts its items and its kinds'.** Five show, then "N More".
- **Under the pointer** a type, a kind and a collection show a plus for the count, and a heading Add and More. Sections never fold.
- **Appearance can draw the sidebar white** (`SidebarColor`).
- **Customize Sidebar works in place:** each faint place opens a menu of what can go there.
- **A row whose thing is gone keeps its place.**
- **Go lists the same places, views and types** (`GoMenu`), and the Archive, which no row opens.

### A layout an earlier copy stored

- **What this copy cannot read is written back as it was.**
- **An earlier Library or Views section is kept and drawn as nothing.** This copy adds `places` and `pinned` where they stood; Pinned keeps the Views section's name and hidden state.
- **What the person put under Library or Views is read under Pinned;** their own sections keep theirs. `views` in `hidden` hides every saved view.
- **Recently Deleted is a page of Settings**, never a row.

## Toolbar

- **The top row is drawn in the content under a hidden title;** a plain `toolbar` holds the buttons.
  - It folds by the room it has. In the toolbar it needs a measured width, and an error, larger text or a closed sidebar sends everything to the overflow menu.
  - It keeps one line with the sidebar closed or larger text, and VoiceOver reads it in order.
- **An on button is gray, never the accent.**
- **An item that cannot act dims**, so the row keeps its shape.
- **Trap:** the row needs its own drag gesture and double click to move and zoom the window, and the window must hide its title, which returns in full screen.

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
