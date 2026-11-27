---
summary: What an item's page and the panel beside it show, in what order, and what a person may arrange.
paths:
  - MarfaMac/Editor/PageHeader.swift
  - MarfaMac/Model/PagePlacements.swift
  - MarfaMac/Model/Items/FieldMenu.swift
  - MarfaMac/Views/Looks/PageHeadView.swift
  - MarfaMac/Model/Items/Page*.swift
  - MarfaMac/Model/Items/PropertyRow.swift
  - MarfaMac/Model/Items/Panel*.swift
  - MarfaMac/Model/Items/PageOutline.swift
  - MarfaMac/Views/ItemPanel/*.swift
  - MarfaMac/Views/Item*Inspector*.swift
  - MarfaMac/Views/ItemCorner.swift
  - MarfaMac/Views/PageOpener.swift
  - MarfaMac/Views/FilePageHead.swift
  - MarfaMac/Views/FileItemContent.swift
  - MarfaMac/Views/ItemFileView.swift
  - MarfaMac/Views/FileMediaPage.swift
  - MarfaMac/Views/PlaybackBar.swift
  - MarfaMac/Views/WaveformView.swift
  - MarfaMac/Model/Items/MediaPlayback.swift
  - MarfaMac/Model/Items/PlaybackPlaces.swift
  - MarfaMac/Model/Items/WaveformEnvelope.swift
  - MarfaMac/Model/Items/PageOpenTarget.swift
  - MarfaMac/Views/WebPageItemPage.swift
  - MarfaMac/Views/VersionHistory*.swift
  - editor/src/header.ts
  - editor/src/notice.ts
  - editor/src/foot.ts
  - editor/src/card.ts
  - MarfaMac/Model/Items/PageFoot.swift
  - MarfaMac/Model/Items/LinkCard.swift
  - MarfaMac/Model/Items/PersonAddress.swift
  - MarfaMac/Views/PlaceMapImages.swift
  - MarfaMac/Views/LinkCard/*.swift
  - MarfaMac/Views/PageNoticeView.swift
---

# The item page

One item page serves every type. The type determines which fields appear and where the text sits.

## The head

- **One head, built once.** `PageHead` decides the kicker, pins and rows; `editor/src/header.ts` draws them on a page with text, `PageHeadView` on a saved web page, which has no menu or drag. A rule added in one drawing must be added in the other.
- **The kicker** is the type's mark and name, then Read Only, Feed or Archived where true. Its name opens Change Type where the item can change type.
- **Rows show what has a value, six at most, then Show N More,** which lists every property in the type's order, Empty where unset, hidden ones grey. On read-only and deleted pages nothing opens.
- **A type with no text shows its first six rows,** empty or not.
- **A row is dragged by its name.** A drag or Move Up or Down moves only that row in the type's one order.
- **An event's When row comes first.** It shows how far away the event is or says All Day. Each attendee's response appears in gray after their name.
- **A message has no title.** Its text follows the rows. In the message family (`PageHeaderKind.message`) From and To show each name, its address in gray (`PersonAddress`).
- **A highlight's passage leads,** at the title's size, with its rows after it (`PageHeader.textLeads`).
- **Long text stops after two lines;** an email, a phone and a number to call open.
- **A value is cut, never reworded,** and a linked item that cannot be read, is gone or is in the bin shows nothing, never an id.
- **Once the head is out of sight** the page says so with the item, title and mark (`DetailsPresentation.scrolledHead`).

## The foot

`PageFoot` lists nested Sub-Items with a count of all descendants. Incoming links appear newest first in Timeline for people and places, or in Linked From where Settings › Layouts puts it on the page. Collection membership does not count as an incoming mention. Show More adds 30 rows to each list independently, starting from 30.

A place with a point has a still map above its Timeline (`PlaceMapImages`). The page draws Apple Maps and a Legal link over it, and no box where MapKit gives no map.

## The card

A pause of 600 ms on a linked item (a chip, a foot or panel row, a link in the text) shows its type, name and up to two lines (`LinkCardContent`) from the counts `ItemCounts` holds, never from the server. It takes no focus or key (`LinkCardPresenter`) and goes on a scroll, key, click or leaving. Show Card, in a menu or for VoiceOver, shows it now. A missing, deleted or unreadable item has none.

## A row's menu

`FieldMenu` is the rule, and a row's name or a right-click opens it.

- **How a row shows belongs to the type** (`PagePlacements`, `RowShows`) and changes no item, so a read-only item can be arranged. A type nobody changed has no entry, so a better default reaches it; Settings › Layouts › Restore Defaults removes the entry.
- **Linked From has one place,** the page's foot or the panel's Links, chosen for a type in Settings › Layouts.
- **Actual Size is 13 points**, with a 24.7-point title and a 680-point reading column at the default width. A saved 15 stays at 15. Saved 11 and 12 display at 13. Page zoom scales Markdown, Source, plain text, Version History, Reader, and printed and exported text. Original keeps the site's styling.
- **Pinned properties are a setting, off** (Settings › Editor). While on, the status and the parent are pinned unless the person chose others, at most four, and a pinned row leaves the rows.

## The panel beside the page

- **It is white behind a hairline and closed by default,** with a pill for each of Outline, Links and Info the item has. One part has no pills.
- **A type remembers its pill** (`PanelParts`). A part the item lacks is not shown. With none remembered, one is chosen when the item opens.
- **Outline shows only for an item with headings, or a PDF.**
- **A group whose field the item may change has a plus on its heading and Remove in each link's menu** (`PanelLinkGroup.editableField`): In Collection, Excerpts and Attachments. The plus opens the page's own relation panel, and a removal is one undo step. Referenced By, Links in the Text, More From This Book and Thread are read only.
- **Links asks the server for nothing.** It uses edges the copy holds. A child, a collection's member and a file are left out of Referenced By, because each has a place. A link follows Open Items (`Browser.follow(link:)`).
- **In ends Info's facts,** a menu that moves the item between Library and Feed (`ItemLibrary.perform`), plain where it may not. Leaves the Feed can follow.

## What the page locks

The page and the panel draw what `Item.allows(_:)` answers, and never judge an item themselves.

| The item is | The page |
| --- | --- |
| Read only | Says Read Only in its kicker and locks the title, text, properties, and type. Tags, Favorite, collections, and links stay open |
| A file | Has no text and no Change Type. Its title, location and the fields a person may change stay open |
| In Recently Deleted | Keeps its head, and locks everything but Recover and Delete Immediately |

## Page notices

Quiet lines at the top of the column say what is not ordinary (`PageNotice.all`). The web head, a file's page and a saved web page draw them the same way, with one action at most and no fill. VoiceOver hears them once. The wash reaches 12 points beyond the text, with 22 points under it.

| The item has | The action |
| --- | --- |
| Been deleted | Recover |
| A copy saved beside it | Open Copy |
| Text that could not be read | None; the reason stands where the text would |
| A write held in the copy | None; Show Changes opens the Settings page that lists it |
| Values that could not be read | None |
| No file in Marfa | None |
| Pictures not loaded | Load Pictures, and a close for the page |

- **The first row that holds leads,** and a write that only waits says nothing. Unreadable text, a held write and a missing file are never hidden: each has its line under the first.
- **An action carries its item from the app,** and none writes or drops text. A write refused as too large keeps the latest text in the copy.

## The corner

`PageCorner.buttons` is the rule for what the corner holds, and `ItemCorner` draws it.

| The page | Its corner |
| --- | --- |
| Text that can be written | Formats, text size, Focus |
| Text that cannot, or a type with none | Text size, Focus |
| A web page with a Reader view | Reader or Original, text size, Focus |
| A web page without one | Focus |
| An image | Size, Focus |
| A PDF | Page (two or more), size, Focus |
| Audio, video, any other file, or one still arriving | Focus |
| An item in the modal | None |
| The column beside a layout | Open as Page |

- **The View menu has a command for each corner control.** It owns the shortcuts so each key is registered once.
- **Open leads wherever the page has somewhere outside the app** (`PageOpenTarget`): the browser, a file's app or Maps, named in its help.
- **A person can turn off formats, text size and Focus** (`PageCornerChoice`). One turned off is in the page's More menu.
- **Zoom keys size the file or the text, never both** (`FileViewCommands`, `TextZoomCommands`).
- **A size belongs to one file.** Another item's page opens fitted.
- **Focus belongs to one window and one item.** It hides the head only, so Linked From stays.
- **Escape closes the formats bar first, then leaves Focus.** A sheet, the palette and the new-item line keep Escape for themselves.

## Text and links

- **A plain click on a link places the caret**, because the page is for writing. Command-click, or Open Link at the caret, opens it.
- **A link to an item opens as Settings says** (`ItemOpening`), and one followed in the modal stays there. So does a link in a row, the foot, a panel or a file's page (`EditorController.follow`).
- **A right-click on a picture of an item offers Open Item and Copy Link,** then Open and Show in Finder.
- **An address that may not be opened**, such as a script, is refused; the rest of the link's menu stays.
- **Removing a link keeps its words.**

## Files and saved web pages

- **Audio and video play from one bar at the window's foot** (`PlaybackBar`): one item at a time, paused at first and where it was left (`PlaybackPlaces`). Leaving stops it. A transcript waits for Marfa.
- **A file's text is never edited here**, and its page is drawn around a viewer (`FileViewing`).
- **A picture, a PDF, audio and video keep their own scroller, with the head as its first inset** (`FileHeadSpace`), so the head scrolls away with the file. Any other file has no head.
- **A file's title is text in its head, not edited there;** rows the item may change open their editor (`FilePageHead`). Size and type are Info's, never rows.
- **Fit shows a picture whole in the page's column, never past its own size.** A PDF's pages are 600 points wide, or as wide as a narrower column.
- **A PDF's pages sit on gray or on white with a soft shadow** (`PDFBackground`). Choose the background in Editor settings or in View › PDF Background while a PDF is open. Outline says so when a PDF has no contents.
- **A saved web page loads nothing from the network by itself.** Its pictures wait until the person asks (`PageNotice`), and asking changes only what is shown, never the file.
- **A picture larger than the bitmap that the app keeps is softer when enlarged**, because a decoded picture must not take the window's memory.

## Version history

- **It takes the place of the left sidebar and the page** (`VersionHistoryWorkspace`), so nothing in it edits the item by mistake.
- **The page shows the version as it was**, with the fields it pins while Pinned Properties is on, added words tinted and removed words struck through.
