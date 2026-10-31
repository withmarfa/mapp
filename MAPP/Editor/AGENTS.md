# Editor host

The Swift side of the note editor: the web view, the controller that drives the page, the bridge's messages, the `mapp-embed:` scheme, and printing. The page's own source is in `editor/`; read `editor/AGENTS.md` before changing the bridge. The types named here carry the detail in their doc comments; read them before changing their behavior.

## Web view

- Use AppKit's `WKWebView` in an `NSViewRepresentable`, not SwiftUI's `WebView` and `WebPage`, which lack printing, menu filtering, Undo routing, dropped files and focus. Revisit only when Apple makes editing, printing, and the scroll edge public in them.
- A private WebKit setting is allowed only when Apple's own `WebView` uses it, it is set only while WebKit responds to its selector, and the page still works without it (`WebViewChrome.swift`).
- The system's scroll edge never reaches the page, and the window's toolbar draws no background, so the app draws its own band under the toolbar (`ToolbarBand`, `bandsToolbar()`, `bandsFoot`). Do not rely on the system's edge for any view in this window.
- The navigation delegate allows only the page itself and `mapp-embed:` requests. Keep every other navigation cancelled.
- A window makes its editor once, in an `EditorSlot` held in `@State`. An editor made in a view's initializer builds a web view and loads the page in a process of its own each time SwiftUI makes the view's value again.
- Inkkit owns selection painting. The bridge only reports whether the web view has the keyboard in the key window (`window.editor.setHostActive`) and never changes focus or history to recolor a selection.

## Saving

- Each load of a note gets a generation, and each edit reports the generation and the version of the text it was typed on (`EditorController`). Never save an edit without its version, and never let an edit from an earlier generation save into the note now on the page.
- A note whose text the library cannot give (`body(of:)` is nil) is not opened: the page is emptied and made read-only under a generation no note owns (`clearPage`), so nothing typed there reaches any note.
- A failed capture of the page's last edit cancels quitting, closing the window, or changing libraries, and the person is told. A page that cannot hand over its edit within `EditorController.flushLimit` is given up on and the person is told. Flushes take turns; a close, quit or library change asked for during a hand-over waits for it (`EditorCloseDelegate`).
- Writing Tools run on the page (`writingToolsBehavior = .complete`). While `isWritingToolsActive`, an edit is held in `heldEdit` and not saved, so a half-finished rewrite never reaches the note; the finished text saves when the session ends (key-value observation of `WKWebView.isWritingToolsActive`). Anything that ends the held edit's generation (a flush, `show`, `clearPage`, the page's `ready`, its process ending) releases it first, so it is saved against the version it was made on and never replaced.
- Link in the Format menu asks for an address in a sheet (`WebLinkRequest`); `WebLinkAddress.normalized` adds `https://` to a bare host and refuses what Inkkit would, and an empty address removes the link. A colon ends a scheme only before `//` or after mailto and tel, so `example.com:8080` is a host. On a link the sheet starts from its address (`window.editor.linkAddress`).
- Images go in through `library.attach(_:to:)`, and the page inserts the returned links, saved like typing. One image that fails never stops the others, and each one not placed in the text is named to the person. Files attached in quick add wait in `EditorController.pendingEmbeds` until the page shows that item, and any that cannot be written into the text are named (`notInText`); the note's text is untouched.

## Embedded files and pictures

- `ItemLibrary.openEmbeddedFile(_:in:waiting:)` in `EmbeddedFiles.swift` is the one place an embed becomes a file. Do not resolve an embed anywhere else, and run no link or embed rule of MAPP's own: the library matches the embed's exact text against what Marfa's core bound it to (`Item.boundEmbeds`).
- `OpenFile` opens the file with `O_NOFOLLOW_ANY` and keeps it only if the descriptor's own path is an ordinary file inside the expected directory, under no dot name. Everything the page is told or served comes from that descriptor. Never reopen by path after the check.
- `EmbeddedFiles.opens` decides what Open may hand to another app: never a file that might run, which is shown in the Finder instead. The kept copy of a file is read-only.
- A picture at a web address is asked through the `pictures` handler (`PictureRequests`), never `embeds`. `PictureRequests.reply` is the one place the page's question becomes `WebPictures.answer`, after a saved file from the same address (`ItemLibrary.openSavedPicture`). The scheme serves only a file the cache or the item holds, never a fetch. How a picture is fetched and kept is in `Model/AGENTS.md`.
- `EditorController.watchEmbeds` and `watchLinks` tell the page only which embeds, saved pictures or links may differ, so the page redraws those alone. Showing a picture or marking a link never rewrites the note.

## Header

- The header is drawn in the page (see `editor/AGENTS.md`); `MAPP/Views/ItemPageHeader.swift` builds its data and carries out its events. The title saves through `setItemProperty`. A refused status, Remove Parent or title is shown and kept, never dropped.
- The editor builds the header again only when what it reads changes (`EditorController.showHeader`). Never read `contentRevision` or a whole list while building it, or an edit anywhere rebuilds the open page's header.
- A title is editable only where `ItemLibrary.canSetTitle(of:)` says so. Each window's unsaved and refused titles live in `EditorController.titleDrafts` until saved or discarded; `flushAll` tries them again, and a title still refused stops a quit, a library change or a window close and names the item.
- When a window goes, `windowWent()` removes its editor from `EditorController.open`. Closures the editor keeps, and the Format menu's focused editor, hold it weakly, or `flushAll` would visit a closed window.

## Linking to notes

- A link names a note by a spelling the library resolves to that note alone (`ItemLibrary.bodyLink(to:in:)`); where none does, there is no link and the person is told. Never write a link any other way.
- `NoteRequests` answers the page's `notes` messages; suggestions come from `NoteLinks.Index`, off the main actor. Link to Note (`NoteLinkPicker`) answers the page exactly once on every path: chosen, cancelled, the document replaced, the note left, the window gone, or the page's process ended.
- Following a link asks the library what that very link means (`ItemLibrary.resolveLink(_:in:)`, from its authored raw text) and never guesses by title. Only `resolved` opens a note; every other answer opens nothing and beeps. No note is made for a link. Wire `onOpenNote` wherever an editor is made.
- `NoteLink.raw` keeps the authored text inside the brackets and defines equality, so `[[Plan]]`, `[[Plan|Plan]]` and escaped separators stay distinct.

## Printing and PDF export

- `PrintDocumentRenderer` renders Inkkit's frozen portable HTML in a separate WebKit view, with images through the checked file path above. It reads pictures from the cache or a saved file only.
- PDF export stops at 200 pages or 64 MB and writes the destination atomically only after rendering succeeds, so a failed export leaves an existing file unchanged.

## Code Review Rules

- **Embed escapes its directory.** Flag any path that reads, serves, or opens an embedded file without `openEmbeddedFile(_:in:)`, follows a symbolic link, or reopens by path. Safe path: use the descriptor `OpenFile` returns.
- **Runnable file opened.** Flag any route that hands a file to another app without `EmbeddedFiles.opens`.
- **Editor made for every view value.** Flag an `EditorController`, a web view, or another costly object made in a view's initializer or given to `State(initialValue:)`. Safe path: `EditorSlot`, or make it in `.task` as Apple's `State` documentation shows.
- **Unguarded private API.** Flag a private WebKit setting set without a `responds(to:)` check, or a new one that Apple's own `WebView` does not use.
- **Link request left open.** Flag a path that ends Link to Note without answering the page once, or that writes a link without `bodyLink(to:)`.
- **Edit saved to the wrong place.** Flag a save without the version it was typed on, or one that can land in another note after the page changed notes.
