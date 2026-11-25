---
summary: What an item's page and right sidebar show, in what order, and what a person may arrange.
paths:
  - MarfaMac/Editor/PageHeader.swift
  - MarfaMac/Model/PagePlacements.swift
  - MarfaMac/Model/Items/Page*.swift
  - MarfaMac/Model/Items/PropertyRow.swift
  - MarfaMac/Model/Items/SidebarSections.swift
  - MarfaMac/Views/Item*Inspector*.swift
  - MarfaMac/Views/ItemCorner.swift
  - MarfaMac/Views/WebPageItemPage.swift
  - MarfaMac/Views/VersionHistory*.swift
  - editor/src/header.ts
---

# The item page

An item's page is its title, pinned properties, property block and text. One page serves every type. A type decides only which properties go where, so no page is built for a type.

## Rules

- **The app decides and the page draws.** `PagePins` and `PropertyRow` decide which values show and where; the web header draws what it is sent. A rule added in `editor/src/header.ts` would be missing from the sidebar, Customize Layout and VoiceOver.
- **Nothing a person can read is lost by arranging.** A value is in the pins or the block, never both. A pinned row that an event's time pushes out goes back to the block, and the right sidebar lists every property whatever the page hides.
- **Nothing sits between the title and the pins**, and nothing else uses the space under a title, because the page reads the same from type to type.
- **An empty value is the word Empty where the person can set it, and absent where they cannot.** No placeholder stands for a missing pin.
- **A value is cut, never reworded.** The whole value is its help and is in the right sidebar.
- **A linked item that cannot be read, is gone or is in the bin shows nothing**, never an id. A choice its field does not list still draws as its word.
- **An email or phone is a row**, not a chip in the header, because it opens something. Latitude and longitude are one row, Location.
- **A kind's header extends the general one** (`PageHeaderKind`): an event's time, a person's job, a reading item's description. What a header draws, no pin or row repeats.
- **A stale pin stays stored and is not drawn**, so a property that comes back is pinned again.

## Right sidebar

- **It always lists everything**, in sections that keep whether they are open from item to item.
- **What has been typed and not saved is kept** when the item changes or the sidebar closes (`ItemPropertyDraft`). A refused tag goes to the clipboard and the person is told.
- **With nothing chosen it is one quiet line** for what the place lists (`InspectorPrompt`), or blank where another pane already says so.
- **It holds no buttons that act on a container**, because the person may make it narrow.

## Customize Layout

- **A layout belongs to a type.** Every item of the type follows it, at once, in every window, and a child type does not inherit it.
- **It changes no item**, so a read-only item can be laid out, and a lock does not stop it.
- **Linked From has one place**, the page or the sidebar, which both halves of the panel read and write.
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
