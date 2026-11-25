# Model

Keep SwiftUI out. `ItemLibrary` is the app's whole view of the working copy; `MarfaLibrary` is the one implementation. `docs/model.md` says what each owns.

## Types

- **Name no type, field or label in code.** They come from `Catalogue`. A type identifier is named only for these:
  - **Roots:** `TypeID.isShipped` guards Marfa's `core`, `system` and `marfa` roots and the plugins' `common`; `TypeID.isHidden` hides `system` and `app`. `MarfaSync` names `system.view`, and `PreferencesType` the app's own hidden settings.
  - **Families:** tasks (`Catalogue.isTask`, `Catalogue.isStartDate`), files (`Catalogue.isFileType`), the header (`PageHeaderKind`) and the suggested look (`LookPreset.suggested`); a preset's fields are named in `MarfaMapping`. Collections go by their role (`Catalogue.isCollection`), never an identifier.
  - **Starting points:** the Note fallback of `QuickAdd`, `NewRowTypes.starting` and `TypesModel.beginChild`, each only where the catalogue offers it.
- **Edit only a type the owner made.** `TypeDefinitionEdit` reads `provenance.origin` from `GET /types`, because a plugin's type can have its own root.
- **A field is a status only by its kind, and a list only by its shape** (`Field.Kind.list`), whatever it is called.
- **`ListEntries` alone changes a list.** Every edit returns the whole list with the other entries as they were.

## One rule decides, the view draws

- **What a list row or card says is `RowContent`,** which is pure, from the item, its type's look and the list (`RowList`). `RowContents` keeps it for each item value, so no row body resolves a look or reads the catalogue.
- **What sits under a page's title is `PagePins`,** and what a person chose for a type is `PagePlacements`.

## Settings the app keeps

- **`PreferencesMap` places each new setting** or keeps it on the Mac. A store that holds one reads it again in `reload()`.
- **An unreadable stored setting is set aside** under its store's `setAsideKey`, never removed, because a later version may read it.

## Commands and writes

- **Every item command takes the whole selection, files too,** and writes each item through the queued edit it would use alone, in one undo step. What it cannot change is counted in `BatchSkips` and told once (`ItemLibrary.tellSkipped`).
- **Moving several items to the bin asks first.** One does not, because Undo restores it. Delete erases only items already in the bin, after its own dialog.
- **Change Type, Restore, Undo and Redo judge the item as it stands,** after open pages hand over their last edit where they touch its text. A change made elsewhere is refused or worked on, never written over.
- **What needs the server is never queued:** `purge`, a view's making, change, renaming and deletion, a type's icon, the owner's settings. `ItemLibrary.reachesServer` is the one rule that offers them, and the server's refusal is told. Every other write goes to the copy's queue.
- **What a person typed into a sheet or panel stays there until the library takes it.** A window that closes or changes library, and a panel that ends any way but Cancel, hands it over through `Notices.notKept`. Only Cancel drops it.
- **Quick add makes an item in one create** (`Browser.saveQuickAdd`), so no required field is set after. It never writes an empty item or drops what the kind cannot keep.
- **Files from outside become items only through `Browser.importFiles`,** in the library they were dropped on, even after the window moves on. What leaves in a drag is an `ItemReference`: an identity inside the app, a file outside it.

## Places, views and search

- **A file attached to another item is left out of places in one place** (`MarfaItemIndex.standalone`).
- **A type counts only its own items, never its subtypes** (`MarfaItemIndex.activeByType`). Include Subtypes changes what the list shows (`Browser.placeItems`) and what a saved view is given (`ViewDraft.query`).
- **`Browser.choicesChanged()` is the one funnel for a place's choices.** It registers one undo step and, in a saved view, writes Marfa's part at once, on the version last read, never queued. A failed write keeps the window's choice, a conflict shows the view, and both are told.
- **A window whose filters differ from its view's lists a preview** (`ItemLibrary.previewItems(ofView:query:)`).
- **Ask the browser for a place's content** (`Browser.tableContent(in:)`, `sections`, `paletteIndex`). Never build an `ItemTableContent` or read the library's items in a view, because that repeats the work at every draw.
- **A new `ItemLibrary` must bump** `contentRevision` when items or the catalogue change, `membershipRevision` when places do, and `namesRevision` when a name does.
- **Names, previews, labels, dates and excerpts are the core's** (`Item.name`, `Item.displayTitle`, `Marfa.ItemDate`); `title` is only what the app writes. The app parses and filters none. Relationship names are Marfa's (`EdgeType.label`), never reworded.
- **A result list from a copy that is filling or behind** (`isIncomplete`) never says nothing matches. An excerpt shows only while it describes the item.

## Remote pictures

- **A picture at a web address is fetched only by `PictureFetcher`,** only when `WebPictures.answer` allows it, and only for the editor's `pictures` message or a sealed page's `SealedPictures`. Printing and export never ask.
- **`PictureAddressPolicy` checks every address and redirect before a request:** `https` only, no sign-in, no private, local or reserved address by name or by any resolved answer. `PictureFetcher` offers no identity and tells a kind by its bytes, never SVG.
- **Known limit: DNS rebinding.** `URLSession` resolves the name again when it connects, so a server can answer the check with a public address and the connection with a private one. Claim no more in the interface or the docs.
- **A sealed web page has no network, stored data or WebRTC** (`SealedWebPage`) and reaches only its own pictures. `PageAnalyzer` reads a document only through `SafeDOM`.

## Changing libraries and quitting

- **With no copy open, a window shows the connect, waiting or failure page** (`Libraries.mode`), never another library.
- **`Libraries.flushEditors` runs before the host changes library and before the app quits.** It ends the open value panel, takes every page's last edit and saves every title. A flush that fails or runs out of time cancels the step and says why. It never waits on the server.
- **A change of library resets each window** (`Browser.adopt`), because its selections name items the other may lack.

## Logs, reports and notices

- **`Model/Telemetry/` is the one place for logs and signposts** (`Telemetry.logger(_:)`). Never make a `Logger`, because its privacy rules would be its own.
- **Never log a person's text, titles, property values or keys.** Log kinds, durations and counts, with `privacy: .public` for those alone. A message that may quote text keeps the default privacy.
- **Reports leave only through `Telemetry+Reports.swift`,** a closed list over `Reporting`. A report holds fixed words, numbers and flags: no text, id, title, server address, path or error message. `Reporting.Gate` keeps tests and previews from reporting.
- **Every alert to the person goes through `Notices`** (`tell`, `notKept`). A change not kept goes to the clipboard the first time it is shown, and is never written over before the person answers.

## Code Review Rules

- **Named type.** Flag a test for a type identifier, or a hard-coded label, field or behavior for a type, outside the list under Types.
- **Library type leaks.** Flag a view, command or editor change that names `MarfaLibrary` outside a preview, offers Delete Immediately without `reachesServer`, or names an SF Symbol for a type. `TypeGlyph` draws `Catalogue.icon(for:)`.
- **Folder as a place.** Flag a folder as a sidebar place, a move between folders, or a folder the app syncs itself. A folder is a fact on an item.
- **Fallback library.** Flag anything but the connect, waiting or failure page while no server's copy is open.
- **Unflushed switch.** Flag a change of library, a quit or a window's close (`EditorCloseDelegate`) that goes ahead without its flush.
- **Picture fetched another way.** Flag a web picture that skips `WebPictures.answer`, `PictureFetcher` or the check at each redirect.
- **Person's text logged or reported.** Flag a log, signpost or report that carries text, a title, an item's id, a key or an error's message as public.
- **Link does more.** Flag a `marfa://` link that skips `ItemLinkRoute`, writes, signs in, changes a setting or calls the server.
