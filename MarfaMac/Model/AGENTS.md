# Model

Keep SwiftUI out. `MarfaLibrary` exposes the working copy through `ItemLibrary`.

## Items and types

- The app defines one type, its hidden settings (`PreferencesType`, `app.marfa-mac.preferences`, [docs](../../docs/marfa-and-the-mac-app.md)). Labels, fields, parents, status words, groups and icons come from `Catalogue`. Use type identifiers only for these rules.
  - `TypeID.isShipped` guards Marfa's `core`, `system` and `marfa` roots and the plugins' `common` root. `TypeID.isHidden` hides `system` and `app`. Edit only the owner's `user` types. The edit checks `provenance.origin` in `GET /types` to refuse plugin types with their own root (`TypeDefinitionEdit.run`). `MarfaSync` names `system.view` to sync saved views.
  - Tasks (`Catalogue.isTask`) use `due_at` and `priority` on `core.task` and its children. `Catalogue.isStartDate` recognizes `starts_at` on tasks and events. Task priority color follows rank (`OptionTone.tone(of:in:isPriority:)`). Files use the `core.file` family (`Catalogue.isFileType`).
  - `PageHeaderKind` walks the parents to choose a header. `LookPreset.suggested` uses fields and ancestry for highlights (`core.highlight`), files, people, reading and events. Name preset fields in `MarfaMapping` only. Collections use the `container` role (`Catalogue.isCollection`).
  - `NewRowTypes.starting` and `QuickAdd`'s Note fallback use offered types. `QuickAdd` offers File when the catalogue has its root. New Type can default its parent to Note if listed (`TypesModel.beginChild`).
- A field is a status only when it is of the `status` kind, and a list of entries only when it is an `array` of `object` with `items_fields` (`Field.Kind.list`), whatever it is called. Name no field in code. `ListEntries` is the only place that changes a list; every edit returns the whole list with the other entries as they were. The person's work on a list lives in `ListEditing`, not the rows.
- What a list row says is decided once, in `RowContent` (pure, no SwiftUI) from an item, the look of its type (`TypeLooks`) and the list (`RowList`); the row only draws. `RowContents`, held by the `Browser`, works it out once for each item value and drops it when the catalogue (`membershipRevision`), the looks, the list or the day changes, rereading links each pass, so no row body resolves a look or reads the catalogue ([docs](../../docs/looks.md)). A gallery or board card is drawn from the same pure rule (`RowContent.card`, shaped by `CardShape`) and a table's columns through `ItemTableLayout.columns`; all take the looks from `Browser.looks(in:)`, resolved once.
- Folders are facts on items, never places: the app syncs no folders and has no Folders section, Move To or New Folder.
- The app's own settings (`PagePlacements`, `SidebarLayouts`, `TypeLooks` and the rest) are kept in the defaults and synced by `PreferencesSync`. `PreferencesMap` places each or keeps it on this Mac; map new ones there. A store holding one rereads it with `reload()`. An unreadable stored setting is set aside under its store's `setAsideKey`, never removed.
- Which properties sit under an item page's title is decided once, in `PagePins` (pure, no SwiftUI), from `PagePlacements` and the header's `PageHeaderLead`; its doc comment says what a pin shows, leaves out or pushes out; the page draws and decides nothing ([docs](../../docs/item-page.md)). A list pin carries every value in its help (`PropertyRow.help`); the block and the sidebar show every value. Customize Layout and a field's menu store through `PagePlacements.apply` (`PageLayout`, pure) as the type's pins, what the page shows and `rowOrder`, and the sidebar half as `Choice.sidebar` (`SidebarSection`). Linked From's place is the one `linkedFrom` setting, which both halves read and write. Placement changes no item, so a read-only item can be laid out.
- Change Type is one queued edit (`ItemLibrary.changeType`, planned by `TypeChange.plan`), so it works offline. Nothing is left under a key the new type does not read, written twice or dropped.

## Commands and writes

- Every item command takes the whole selection, files too, and writes each item through the queued, offline-safe edit it would use alone, in one undo step. An item a command can't change is counted in `BatchSkips` and told once (`ItemLibrary.tellSkipped`).
- Moving several items to Recently Deleted asks first; one does not, as Undo restores it. Delete erases only items already in Recently Deleted, after their own dialog.
- Change Type, Restore, Undo and Redo judge the item as it stands, after open pages hand over their last edit if they touch its text, so a change made elsewhere is refused or worked on, not overwritten.
- Deleting permanently (`purge`), making, updating, renaming and deleting a view, choosing a type's icon, and changing This Marfa's settings need the server and are never queued. `ItemLibrary.reachesServer` is the one rule that offers them; the server's refusal is told. Saving a view's layout, columns or cards is the Mac's own and needs no server. Every other write goes to the copy's queue and can always be made.
- What a person typed into a sheet or panel (a view's title, a rename, a draft) stays there until the library takes it. A window that closes or changes library hands it over through `Notices.notKept`, as does a panel that ends any way but Cancel; only Cancel drops it.
- Quick add (`QuickAdd`, `Browser.saveQuickAdd`) never writes an empty item, makes it in one create so no required field is set after, and never drops text or files the kind cannot keep: adding waits until the person removes them.
- Files from outside (a Finder drop, a drop on a collection, Import from iPhone) become items only through `Browser.importFiles`, and what leaves in a drag is an `ItemReference`: its identity inside the app, a file named after the item outside it. An import's files go to the library they were dropped on; only the window's own steps (selecting, revealing) stop. Quick Look is shown temporary copies (see `BrowserQuickLook`).

## Places, views and search

- `SidebarPlan` is what the sidebar reads; `SidebarPlace` is the one definition of a place's symbol, destination and count. A file attached to another item is cut from the places in one place, `MarfaItemIndex.standalone`, so lists and counts agree.
- A type counts only its own items, never its subtypes (`MarfaItemIndex.activeByType`), so a count is its list's length. Include Subtypes changes only what the list shows (`Browser.placeItems`) and what Save as View writes for it (`ViewDraft.query`).
- A window whose filters differ from its saved view's lists a preview (`ItemLibrary.previewItems(ofView:query:)`, `ViewDraft.previewQuery`): the copy's answer to the view's query with the conditions shown as chips taken out, which the chips then narrow locally. It reads the copy, works offline and writes nothing; a query the copy refuses lists the view's own list, said once.
- Saved views live on the server. A view write uses the version last read. Leaving a setting out keeps another app's change to it. What a view cannot hold is left out and named. The Edit View panel (`ViewPanel`, `Browser+ViewPanel`) shows every change as made; Done only closes it, but makes a new view, and Escape before it makes nothing. `Browser.choicesChanged()` is the one funnel: it compares the window's choices with the last observed, registers one undo step, and for a saved view writes Marfa's part (name, query, sort, group) through `library.changeView` at once, per view in turn, never queued. A failed or invalid write keeps the window's choice, a conflicting one shows the view, and the person is told; an Undo after one never overwrites a change made elsewhere. The Mac's part (`ViewLayouts`, keyed by view ID) is stored as made, with its own undo step, and synced but for its widths. Only `Browser.forgetView`, reached from `Browser.deleteView`, forgets it: a view missing from a list proves nothing, since a failed read can list none. [docs/views-and-lists.md](../../docs/views-and-lists.md) says what each part holds.
- A view, a command or the palette asks the browser for a place's content (`Browser.tableContent(in:)`, `sections`, `paletteIndex`) and never builds an `ItemTableContent` or reads the library's items itself. A new `ItemLibrary` must bump `contentRevision` when its items or catalogue change, `membershipRevision` on a place change, and `namesRevision` on a title or name change.
- A column width is recorded only from a drag of the divider (`ColumnWidthTracker`), never from a layout measurement.
- The app shows the core's name and preview (`Item.name`, `Item.displayTitle`; `title` is only what it writes), labels (singular for one item's kind, plural for counts), dates (`Marfa.ItemDate`), excerpts and `types`/`states` filters, and parses and filters none itself. Search runs in the working copy; Search Items' Type filter, the leave-out and Include choices go into it (`SearchNarrowing`; ⌘K follows). A result list from a copy that is filling or behind (`isIncomplete`) never says nothing matches; an excerpt shows only while it describes the item; relevance never changes the sort.
- Relationship names are Marfa's (`EdgeType.label`, `reverseLabel`), never reworded.

## Remote pictures

- A picture at a web address is fetched only by `PictureFetcher`, only when `WebPictures.answer` allows it, and only for the editor's `pictures` message or a sealed page's `SealedPictures`. A saved file or the cache answers without a request, and printing and export never ask.
- `PictureAddressPolicy` checks every address and redirect before a request: `https` only, no sign-in, and no private, local or reserved address by name or by any resolved answer. `PictureFetcher` offers no identity and tells a picture's kind by its bytes, never SVG.
- **Known limit: DNS rebinding.** `URLSession` resolves the name again when it connects, so a server that answers the check with a public address and the connection with a private one is not stopped. Claim no more in the interface or the docs.
- A sealed web page (`SealedWebPage`) has no network, stored data or WebRTC, and reaches only its own pictures.
- `PageAnalyzer` loads a document into a sealed page of its own, never changing the page shown or the stored file, and reads it only through `SafeDOM`. A failure or a timeout is a document with no article; a cancelled analysis throws (see its doc comment).

## Changing libraries and quitting

- `Libraries` owns the `MarfaHost` and the library the windows read. With no copy open, a window shows the connect, waiting or failure page (`Libraries.mode`) and no other library.
- Before the host changes library and before the app quits, `Libraries.flushEditors` ends the open value panel (`ValueEditPresenter.handOff`), has every open page hand over its last edit and every unsaved title saved; a flush that fails or runs out of time cancels the step and tells the person why. It never waits on the server.
- A change of library resets each window (`Browser.adopt`): selections name items the other library may lack.

## Logs, reports and notices

- `Model/Telemetry/` is the one place for logs and signposts (`Telemetry.logger(_:)`, `Telemetry.signposter(_:)`); never make a `Logger` of your own. `Cost` stays the one mechanism the `Measure` plan reads.
- **Never log a person's text, titles, property values or keys.** Log kinds, durations and counts, with `privacy: .public` for those alone. Name an item by a count, never its id or title. A message that may quote the person's text uses the default (private) privacy.
- **Reports to WithMarfa.** Everything the app sends leaves through `Telemetry+Reports.swift`, a closed list of calls over `Reporting`; no call site reports itself, and only `Model/Telemetry/` imports `WithMarfaTelemetry`. A report carries only fixed words, numbers and flags: never a person's text, an item's id or title, the server's address, a path, or an error's message. `Reporting.Gate` keeps tests, previews and the isolated host from reporting.
- Every alert to the person goes through `Notices` (`tell`, `notKept`); add no other route. A change not kept goes to the clipboard the first time it is shown and is never written over before the person answers.

## Code Review Rules

- **Named type.** Flag tests for a type identifier, or hard-coded labels, fields or behavior for a type, outside Items and types above.
- **Library type leaks.** Flag a view, command or editor change that names `MarfaLibrary` outside a preview, offers Delete Immediately without checking `reachesServer`, or names an SF Symbol for a type. A type's icon comes from the catalogue (`Catalogue.icon(for:)`) and is drawn by `TypeGlyph`, which keeps a table by icon id.
- **Folder as a place.** Flag a change that brings back a folder as a sidebar place, a move between folders, or a folder the app keeps or syncs itself.
- **Fallback library.** Flag anything but the connect, waiting or failure page while no server's copy is open.
- **Unflushed switch.** Flag a change of library or a quit that does not first flush the open pages (`Libraries.flushEditors`), or that goes ahead when the flush fails. A window close waits for its editor's flush the same way (`EditorCloseDelegate`).
- **Picture fetched another way.** Flag a web picture fetched other than by `PictureFetcher` after `WebPictures.answer`, an address `PictureAddressPolicy` did not check at each redirect, or a claim that DNS rebinding is closed.
- **Person's text logged or reported.** Flag a log, signpost or report that carries a person's text, a title, an item's id, a key or an error's message as public.
- **Link does more.** Flag a `marfa://` link that skips `ItemLinkRoute`, writes, changes settings or connections, signs in, or calls the server.
