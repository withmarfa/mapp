# Model

The data model, free of SwiftUI: the `ItemLibrary` protocol, `MarfaLibrary` over a Marfa server's working copy, and `Libraries`, which holds the host and the library the windows read. Before changing `Marfa/`, also read `MAPP/Model/Marfa/AGENTS.md`. Read a type's doc comment before changing it.

## Items and types

- MAPP names no item type of its own. A type's label, fields, parent, status words, groups and icon come from the server's catalogue (`Catalogue`). Code never tests a type by its identifier, with two exceptions: a child of `core.task` carries `due_at` and `priority` (`Catalogue.isTask`), and `PageHeaderKind` walks up the parents for an item page's header. A collection is a type that plays the `container` role (`Catalogue.isCollection`), never a type's name.
- A field is a status only when it is of the `status` kind, and a list of entries only when it is an `array` of `object` with `items_fields` (`Field.Kind.list`), whatever it is called. Name no field in code. `ListEntries` is the only place that changes a list; every edit returns the whole list with the other entries as they were. The person's work on a list lives in `ListEditing`, never in the rows.
- Folders are facts on items, never places: MAPP syncs no folders and has no Folders section, Move To or New Folder.
- What the item page shows of a type (`PagePlacements`), the sidebar layout (`SidebarLayouts`), column widths and, for a saved view, its layout, columns and Hide Empty Groups (`ViewLayouts`) are MAPP's own settings on this Mac, never written to Marfa. An unreadable stored sidebar layout or page placement is set aside under its own key (`SidebarLayouts.setAsideKey`, `PagePlacements.setAsideKey`), never removed.
- Which properties sit under an item page's title is decided once, in `PagePins` (pure, no SwiftUI), from `PagePlacements` and the header's `PageHeaderLead`; the page draws and decides nothing. A type pins at most four, and a stored list longer than that shows its first four. A pin that is empty, stale or said by the header's own line is not drawn, and a stale one stays in storage. A pinned row is not also in the property block. Customize Layout arranges a type's rows in three groups (`PageLayout`, pure): Pinned, On the Page and Hidden. It stores through `PagePlacements.apply` as the type's pins, what the page shows and `rowOrder`, which the property block follows, with rows it does not name after those it does. It changes no item, so a read-only item can be laid out.
- Change Type is one queued edit (`ItemLibrary.changeType`, planned by `TypeChange.plan`), so it works offline. Nothing is left under a key the new type does not read, written twice, or dropped.

## Commands and writes

- Every item command takes the whole selection, files too, and writes each item through the queued, offline-safe edit it would use alone, in one undo step. An item a command can't change is counted in `BatchSkips` and told in one notice (`ItemLibrary.tellSkipped`).
- Moving several items to Recently Deleted asks first; one does not, since Undo puts it back. Delete never erases a live item: only items already in Recently Deleted are erased, after their own dialog.
- Change Type, Undo, Redo and Restore wait for every open page to hand over its last edit, and judge on the item as it then stands, so a change made elsewhere is refused or worked on as it is, never overwritten.
- Deleting for good (`purge`), saving, updating, renaming and deleting a view, choosing a type's icon, and changing This Marfa's settings need the server and are never queued. `ItemLibrary.reachesServer` is the one rule that offers them, and the server's refusal is told. Every other write goes to the copy's queue and can always be made.
- What a person typed into a sheet or panel stays there until the library takes it (a new view's title in `ViewTitleForm` and a rename in `ViewPanel`, This Marfa's draft in `InstanceSettingsModel`, quick add's draft). A window that closes or changes library hands it over through `Notices.notKept`, and so does a panel that ends in any way but the person's own Cancel (a change of place, the sidebar closing, another panel opening, the view gone); only Cancel drops it.
- Quick add (`QuickAdd`, `Browser.saveQuickAdd`) never writes an empty item, makes the item in one create so a required field is never set after it, and never drops text or files the chosen kind cannot keep: adding waits until the person removes them.
- Files from outside (a Finder drop, a drop on a collection, Import from iPhone) become items only through `Browser.importFiles`, and what leaves in a drag is an `ItemReference`: its identity inside the app, a file named after the item outside it. An import's files go to the library they were dropped on; only the window's own steps (selecting, revealing) stop. Quick Look is shown copies of the first few items, in screen order, and told when the selection had more; they are removed when it closes, the window changes library or another window takes the panel. Temporary copies live in a folder named by the process; launch removes only folders of processes no longer running.

## Places, views and search

- `SidebarPlan` is what the sidebar and Settings > Sidebar both read; `SidebarPlace` is the one definition of a place's symbol, destination and count. A file attached to another item is cut from the places in one place, `MarfaItemIndex.standalone`, so lists and counts agree.
- A type counts only its own items, never its subtypes (`MarfaItemIndex.activeByType`), so a count is its list's length. Include Subtypes changes only what the list shows (`Browser.placeItems`).
- A window whose filters differ from its saved view's lists a preview (`ItemLibrary.previewItems(ofView:query:)`, `ViewDraft.previewQuery`): the copy's answer to the view's query with the conditions shown as chips taken out, which the chips then narrow locally. It reads the copy, works offline and writes nothing; a query the copy refuses lists the view's own list and says so once.
- Saved views live on the server. A view write is based on the version the window read, so a change made elsewhere is refused, never overwritten. What a view cannot hold is left out and named first. The Edit View panel (`ViewPanel`, `Browser+ViewPanel`) changes nothing until Save: Marfa's part (name, query, sort, group) is sent first, and the Mac's part (`ViewLayouts`, keyed by view ID) is written only after Marfa takes its part, so a refusal leaves nothing half saved. Layout, columns, cards and Hide Empty Groups are held per window (`viewWorking`) and count in `hasViewChanges`; Revert and Cancel restore them. Column widths are the one exception, kept at once (`Browser.keepWidths`); the app, not the table, owns a view's column order and visibility, because `TableColumnCustomization` cannot separate them from widths. Never write Mac settings to Marfa. Only `Browser.deleteView` forgets them: a view missing from a list proves nothing, since a failed read publishes an empty one. A layout the Mac holds none of stays nil and follows the window; the app's own change of layout goes through `Browser.set(layout:)` so it is never taken for the person's.
- A view, a command or the palette asks the browser for a place's content (`Browser.tableContent(in:)`, `sections`, `paletteIndex`) and never builds an `ItemTableContent` or reads the library's items itself. A new `ItemLibrary` must bump `contentRevision` whenever its items or catalogue change, and `membershipRevision` whenever an item comes, goes or changes which places hold it.
- A column width is recorded only from a drag of the divider (`ColumnWidthTracker`), never from a layout measurement.
- MAPP shows the core's name and preview (`Item.name`, `Item.displayTitle`; `title` is only what it writes), labels (singular where one item's kind is picked, plural for counts), dates (`Marfa.ItemDate`), excerpts and `types`/`states` filters; it parses and filters none itself. Search runs in the working copy, never the server. A result list from a copy that is filling or behind (`isIncomplete`) never says nothing matches; an excerpt shows only while it still describes the item. Relevance never changes the stored sort.
- Relationship names are Marfa's (`EdgeType.label`, `reverseLabel`), never localized or reworded.

## Remote pictures

- A picture at a web address is fetched only by `PictureFetcher`, only when `WebPictures.answer` allows it, and only for the editor's `pictures` message or a sealed page's `SealedPictures`. A saved file or the cache answers without a request; printing and export never ask the website.
- `PictureAddressPolicy` checks every address and redirect before a request: `https` only, no sign-in, and no private, local or reserved address by name or by any resolved answer. `PictureFetcher` offers no identity or password and tells a picture's kind by its bytes, never SVG.
- **Known limit: DNS rebinding.** `URLSession` resolves the name again when it connects, so a server that answers the check with a public address and the connection with a private one is not stopped. Do not claim more than this in the interface or the docs.
- A sealed web page (`SealedWebPage`) has no network, stored data or WebRTC, and reaches only its own pictures.

## Changing libraries and quitting

- `Libraries` owns the `MarfaHost` and the library the windows read. With no copy open, a window shows the connect, waiting or failure page (`Libraries.mode`); there is no other library to fall back to.
- Before the host changes library and before the app quits, `Libraries.flushEditors` has every open page hand over its last edit and every unsaved title saved; a flush that fails or runs out of time cancels the step and tells the person why. It never waits on the server, so quitting offline is not held up.
- A change of library resets each window (`Browser.adopt`): selections name items the other library may lack.

## Logs, reports and notices

- `MAPP/Model/Telemetry/` is the one place for logs and signposts (`Telemetry.logger(_:)`, `Telemetry.signposter(_:)`); never make a `Logger` of your own. `Cost` stays the one mechanism the `Measure` plan reads.
- **Never log a person's text, titles, property values or keys.** Log kinds, durations and counts, with `privacy: .public` for those alone. Name an item by a count, never its id or title. A message that may quote the person's text uses the default (private) privacy.
- **Reports to WithMarfa.** Everything the app sends leaves through `Telemetry+Reports.swift`, a closed list of calls over `Reporting`; no call site reports itself, and only `MAPP/Model/Telemetry/` imports `MarfaTelemetry`. A report carries only fixed words, numbers and flags: never a person's text, an item's id or title, the server's address, a path, or an error's message. `Reporting.Gate` keeps tests, previews and the isolated host from reporting.
- Every alert to the person goes through `Notices` (`tell`, `notKept`); add no other route. A change not kept goes to the clipboard the first time it is shown and is never written over before the person answers.

## Code Review Rules

- **Named type.** Flag code that tests for an item type by its identifier, or gives one a label, field or behavior of its own, outside `PageHeaderKind`'s header choice. Flag an SF Symbol named for a type.
- **Folder as a place.** Flag a change that brings back a folder as a sidebar place, a move between folders, or a folder MAPP keeps or syncs itself.
- **Fallback library.** Flag a change that shows anything but the connect, waiting or failure page while no server's copy is open.
- **Unflushed switch.** Flag a change of library or a quit that does not first flush the open pages (`Libraries.flushEditors`), or that goes ahead when the flush fails. A window close waits for its editor's flush the same way (`EditorCloseDelegate`).
- **Picture fetched another way.** Flag a picture at a web address fetched other than by `PictureFetcher` after `WebPictures.answer`, an address not checked by `PictureAddressPolicy` at each redirect, or a claim that DNS rebinding is closed.
- **Person's text logged or reported.** Flag a log, signpost or report that carries a person's text, a title, an item's id, a key or an error's message as public.
