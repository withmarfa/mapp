---
summary: What an item's page and the panel beside it show, in what order, and what a person may arrange.
paths:
  - MarfaMac/Editor/PageHeader.swift
  - MarfaMac/Model/PagePlacements.swift
  - MarfaMac/Model/Items/Page*.swift
  - MarfaMac/Model/Items/PropertyRow.swift
  - MarfaMac/Model/Items/Panel*.swift
  - MarfaMac/Model/Items/PageOutline.swift
  - MarfaMac/Views/ItemPanel/*.swift
  - MarfaMac/Views/Item*Inspector*.swift
  - MarfaMac/Views/ItemCorner.swift
  - MarfaMac/Views/WebPageItemPage.swift
  - MarfaMac/Views/VersionHistory*.swift
  - editor/src/header.ts
---

# The item page

An item's page is its title, pinned properties, property block and text. One page serves every type. A type decides only which properties go where, so no page is built for a type.

## Rules

- **The app decides and the page draws.** `PagePins` and `PropertyRow` decide which values show and where; the web header draws what it is sent. A rule added in `editor/src/header.ts` would be missing from Customize Layout and VoiceOver.
- **Nothing a person can read is lost by arranging.** A value is in the pins or the block, never both. A pinned row that an event's time pushes out goes back to the block, and the right sidebar lists every property whatever the page hides.
- **Nothing sits between the title and the pins**, and nothing else uses the space under a title, because the page reads the same from type to type.
- **An empty value is the word Empty where the person can set it, and absent where they cannot.** No placeholder stands for a missing pin.
- **A value is cut, never reworded.** The whole value is its help.
- **A linked item that cannot be read, is gone or is in the bin shows nothing**, never an id. A choice its field does not list still draws as its word.
- **An email or phone is a row**, not a chip in the header, because it opens something. Latitude and longitude are one row, Location.
- **A kind's header extends the general one** (`PageHeaderKind`): an event's time, a person's job, a reading item's description. What a header draws, no pin or row repeats.
- **A stale pin stays stored and is not drawn**, so a property that comes back is pinned again.

## The panel beside the page

- **It is white behind a hairline and closed by default,** with a pill for each part the item has: Outline, Links, Info. One part has no pills. Info is not About, because Marfa has a link named About.
- **A type remembers its pill** (`PanelParts`). A part the item lacks is not shown, and a word this version does not know is no choice.
- **Outline shows only for an item with headings, or a PDF.** Its counts are worked out off the main thread. The page does not say which heading is in view.
- **Links asks the server for nothing.** It is made from edges the copy holds. A child, a collection's member and a file are left out of Referenced By, because each has a place. A link follows Open Items (`Browser.follow(link:)`).
- **In is the last fact in Info,** a menu that moves the item between Library and Feed as the Keep and Move to Feed commands do (`ItemLibrary.perform`), and plain where it may not move.
- **Who keeps the item is said once at the top of Info,** with the reason `Item.obstacle(to:)` gives, so the page and the line never disagree. Only the read-only case has one: a connector that carries changes back needs an owner's call.
- **History is asked for only while Info shows** (`PanelHistory`), once for each version. Version 1 says No earlier versions.
- **Properties, Relationships and Tags and a sync problem stay in Info** until the page's rows and notices carry them.
- **What has been typed and not saved is kept** when the item changes or the panel closes (`ItemPropertyDraft`).

## What the page locks

The page and the right sidebar draw what `Item.allows(_:)` answers, and never judge an item themselves.

| The item is | The page |
| --- | --- |
| Read only | Locks the title, text, properties, and type. Tags, Favorite, collections, and links stay open |
| A file | Has no text and no Change Type. Its title, location and the fields a person may change stay open |
| In Recently Deleted | Locks everything but Recover and Delete Immediately |

## Customize Layout

- **A layout belongs to a type.** Every item of the type follows it, at once, in every window, and a child type does not inherit it.
- **It changes no item**, so a read-only item can be laid out, and a lock does not stop it.
- **A type nobody customized has no entry** (`PagePlacements`), so a better default reaches it. Use Defaults removes the entry.
- **Escape ends it, and Focus waits for it**, because it arranges the header that Focus hides.
- **Trap:** `Choice.pins` of nil means the default pins and an empty list means no pins. Treating one as the other pins properties that a person removed. `PagePlacement` gives the defaults.

## The corner

`PageCorner.buttons` is the rule for what the corner holds, and `ItemCorner` draws it.

| The page | Its corner |
| --- | --- |
| Text that can be written | Formats, text size, Focus |
| Text that cannot | Text size, Focus |
| A web page with a Reader view | Reader or Original, text size, Focus |
| A web page without one | Focus |
| An image | Size, Focus |
| A PDF | Page, size, Focus |
| Any other file, or one still arriving | Focus |
| An item in the modal | None |

- **Every control in the corner is also a command in the View menu**, and the corner's own menus bind no keys, because a key registered twice works for neither.
- **A person can turn off formats, text size and Focus** (`PageCornerChoice`). One turned off is in the page's More menu.
- **Zoom keys size the file or the text, never both** (`FileViewCommands`, `TextZoomCommands`).
- **A size belongs to one file.** Another item's page opens fitted.
- **Focus belongs to one window and one item.** It hides the title and the properties only, so Linked From and a collection's contents stay.
- **Escape closes the formats bar first, then leaves Focus.** A sheet, the palette and quick add keep Escape for themselves.
- **The formats bar runs the Format menu's commands** (`FormatsBar`), with no code of its own.

## Text and links

- **A plain click on a link places the caret**, because the page is for writing. Command-click, or Open Link at the caret, opens it.
- **A link to an item opens as Settings says** (`ItemOpening`), and one followed in the modal stays there. A link in the property block or in Linked From shows the item in the list.
- **Opening is refused for an address that may not be opened**, such as a script, and the rest of the link's menu stays.
- **Every look of a link reads the same under the pointer** (`LinkLook`), and a link to nothing keeps its dashes in all of them.
- **Removing a link keeps its words.**

## Files and saved web pages

- **A file's text is never edited here**, and its page is drawn around a viewer (`FileViewing`).
- **A saved web page loads nothing from the network by itself.** Its pictures wait until the person asks (`PicturesWaitingCallout`), and asking changes only what is shown, never the file.
- **A picture larger than the bitmap that the app keeps is softer when enlarged**, because a decoded picture must not take the window's memory.

## Version history

- **It takes the place of the left sidebar and the page** (`VersionHistoryWorkspace`), so nothing in it edits the item by mistake.
- **The page shows the version as it was**, with its pins, added words tinted and removed words struck through.
- **Restoring is a new version**, and Restore Version is offered only when it can be done (`VersionHistoryMode`).
