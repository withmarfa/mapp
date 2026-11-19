# Agreed designs, not built yet

Status: Agreed, not built. Each design is drawn on MAPP Pages, and the MAPP design system holds its components. When a design is built, move its section to the page for its area and delete it here.

Where it lives: not built yet.

This page lists what has been agreed for MAPP and is not in the app yet, so the next build starts from one list. What was turned down is in [Rejected designs](rejected-designs.md).

## Views

- Every place opens in a default view. A person can change the default view, but can't rename or delete it.
- Save as View… makes a second view with a name. It is the last item of View Options, shown only when there is something to keep. It is never in the toolbar. It opens New View's panel, filled in.
- Once a default view is changed, View Options offers Reset View above Save as View…, which puts it back.

## The toolbar and the bottom-right corner

- The toolbar holds the same buttons on every screen: Search, View Options, View As, Share, More and the right sidebar. A screen hides a button that does not apply. No screen adds its own controls to the toolbar.
- The page holds at most one main action, such as New Collection.
- The bottom-right corner is built (`WindowCorner`, [Views and lists](views-and-lists.md#the-bottom-right-corner)), with the Calendar's, the Timeline's and the Gallery's controls in it. The note's Aa and Focus and the file pages' controls below go into the same component.
- **Focus** is the last button in the corner on every item's page, documents and web pages included. It moves the title into the toolbar and hides the properties, so the text gets the room. The sidebar, the list and the toolbar's buttons stay. The button again, or Escape, leaves it.
- What each screen's corner holds:
  - **Note:** Aa, which opens the formats: the text style (Title, Heading, Subheading, Body) as a row; bold, italic, strikethrough, highlight, code and link; bulleted, numbered and checklist; quote, code block and table; then Standard or Full Width beside smaller, actual and larger text. Format leaves the toolbar; the Format menu stays. Then Focus.
  - **Image:** one zoom control, 100% with a menu that holds Fit and sizes. Clicking 100% lets a person type a size.
  - **PDF:** the page as "2 of 4" with arrows, the same zoom control, and Focus.
  - **A web page or newsletter with a Reader view:** Reader or Original, as one glass segmented control. The switch leaves the toolbar. A web page with no Reader view has no switch.
  - **Any other item's page:** Focus alone.

## Menus and empty states

- The menu bar holds every command the toolbar, the corner and the row menus offer.
- Go lists the places (Items, Sources, Collections, Inbox, Recents, Favorites), then the saved views and the types, as the sidebar holds them, with All Types for the rest.
- Recently Deleted leaves the View menu.
- Help holds MAPP Help, Keyboard Shortcuts, What's New in MAPP, Marfa Documentation and Report a Problem…, after the system's search field.
- Recently Deleted is a page in Settings only, not a sidebar place.

## Editing in place

What is not built yet. The built part is in [Value components](value-components.md) and [Item page](item-page.md).

- A status's value panel ends with Edit Statuses, which opens the type in Settings > Types. Settings > Types does not exist yet.
- A field's menu has Edit the type in Settings, which opens the same page, and waits for it too.
- Renaming a choice word is left out. A rename that carried the values to the new word is not in Marfa's contract, so the items that hold the old word would keep a word the type no longer lists. Choices can be added, reordered and taken out; a taken-out choice stays on the items that hold it.
- An empty In Collection row for an item in no collection. Add to Collection from the menu, the toolbar and the palette reaches it, and the page's own row appears once the item is in one.

## Pages

- Where a code block's language goes, and how it changes, is open. It stays as it is.

## Settings

- The other pages of Settings (Appearance, Lists, Library and Types) are being redesigned to the rules on the Settings page of [Views and lists](views-and-lists.md#settings), as Sidebar was.

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
