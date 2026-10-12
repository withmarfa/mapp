# Editor host

The Swift side of the note editor: the web view, the controller that drives the page, the bridge's messages, the `mapp-embed:` scheme, and printing. The page's own source is in `editor/`; read `editor/AGENTS.md` before changing the bridge.

## Web view

- Use AppKit's `WKWebView` in an `NSViewRepresentable`, not SwiftUI's `WebView` and `WebPage`. An editor needs what they do not offer: printing, filtering WebKit's context menu rather than replacing it, routing Undo to the page's own history, dropped files, and focus. Revisit only when Apple makes editing, printing, and the scroll edge public in them.
- `WebViewChrome.swift` sets two WebKit settings that are not public API, as Apple's own `WebView` does: a clear background (`drawsBackground`) and the soft edge under the toolbar (`usesAutomaticContentInsetBackgroundFill`). Each is set only while WebKit responds to its selector, and the page must still work without it: it then keeps its own background and stops below the toolbar. Add no other private WebKit API.
- The navigation delegate allows only the page itself and `mapp-embed:` requests. Keep every other navigation cancelled.

## Embedded files

- `ItemLibrary.embeddedFile(_:in:)` in `EmbeddedFiles.swift` is the one place an embed becomes a file. Callers use `openEmbeddedFile(_:in:)`, which resolves through it and opens the result with `OpenFile`: the `mapp-embed:` scheme, the page's images for printing, Open and Show in Finder, and gallery thumbnails. Do not resolve an embed path anywhere else.
- It reads the path or name as Marfa's core does (`EmbedPaths`): relative to the note, `/` from the folder's root, a bare name nearest the note first, without regard to case. Keep it matching the core.
- It serves only a regular file inside the notes folder, reached without a symbolic link or a name starting with a dot.
- `OpenFile` opens the file with `O_NOFOLLOW_ANY` and keeps it only if the descriptor's own path (`F_GETPATH`) is inside the folder. Everything the page is told or served comes from that descriptor, so a folder changed after the check cannot put another file behind it. Never reopen by path after the check.
- The scheme handler streams the file in pieces and answers byte ranges, which WebKit's media playback needs.
- `EmbeddedFiles.opens` decides what Open may hand to another app. It never hands over a file that might run (a program, a script, a web page, a link file, anything marked executable, or a kind it cannot tell); such a file is shown in the Finder instead.

## Saving

- Each load of a note gets a generation, and each edit reports the generation and the version of the text it was typed on (`EditorController`). Never save an edit without its version, and never let an edit from an earlier generation save into the note now on the page.
- A failed capture of the page's last edit cancels quitting, closing the window, or changing libraries, and the person is told. The editor stays open so the text can be recovered.
- Images go into a note through `library.attach(_:to:)`, and the page inserts the returned link with `insertImages`. The editor then saves it like typing.

## Header

- The header is drawn in the page (see `editor/AGENTS.md`). `MAPP/Views/ItemPageHeader.swift` carries out its events: it saves the title through `setItemProperty` on Return or when the title loses focus, and keeps unsaved and refused titles per item in `DetailsPresentation` so they survive switching notes.
- A chip's menu opens under the chip's frame, which the page sends in its own coordinates. `EditorController` converts it to container coordinates, allowing for the covered top and the scroll offset.

## Printing and PDF export

- `PrintDocumentRenderer` renders InkKit's frozen portable HTML in a separate WebKit view, with images supplied through the checked file path above and readable descriptions for other files.
- PDF export renders the complete document, stops at 200 pages or 64 MB, and writes the destination atomically only after rendering succeeds, so a failed export leaves an existing file unchanged.

## Code Review Rules

- **Embed escapes the folder.** Flag any path that reads, serves, or opens an embedded file without `openEmbeddedFile(_:in:)`, follows a symbolic link, or reopens by path. Safe path: use the descriptor `OpenFile` returns.
- **Runnable file opened.** Flag any route that hands a file to another app without `EmbeddedFiles.opens`.
- **Unguarded private API.** Flag a private WebKit setting set without a `responds(to:)` check, or a new one without a stated reason.
- **Edit saved to the wrong place.** Flag a save without the version it was typed on, or one that can land in another note after the page changed notes.
