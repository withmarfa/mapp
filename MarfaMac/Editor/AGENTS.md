# Editor host

The Swift side of the item editor. The page is in `editor/`; read `editor/AGENTS.md` before you change the bridge. Read a type's doc comment before you change it.

## Web view

- **Use AppKit's `WKWebView` in an `NSViewRepresentable`,** because SwiftUI's `WebView` lacks printing, menu filtering, Undo routing, dropped files and focus.
- **A private WebKit setting is allowed only when** Apple's own `WebView` uses it, WebKit responds to its selector, and the page works without it (`WebViewChrome.swift`).
- **Trap:** the system's scroll edge never reaches the page and the toolbar draws no background, so the app draws its own band (`ToolbarBand`, `bandsFoot`). No view in this window may rely on the system's edge.
- **Keep the bridge's decoding hand-written.** `MarfaMacTests/EditorBridgeTests.swift` checks it against `editor/bridge-messages.json`.
- **A script error the page reports is logged,** never shown as the notice's words (`EditorController.tellPageFault`).
- **The navigation delegate allows only the page itself and `marfa-embed:`** (`EditorController+Navigation.swift`). Keep every other navigation canceled.
- **A window makes its editor once, in an `EditorSlot` held in `@State`.** One made in a view's initializer starts a web process each time SwiftUI makes the value again.
- **Inkkit owns selection painting.** The app only reports whether the web view has the keyboard (`setHostActive`).

## Saving

- **Never save an edit without its generation and its version.** Each load of an item gets a generation, and an edit from an earlier one never saves into the item now on the page. An edit that is too old, or does not decode (`EditorMessage.unreadableChange`), goes through `Notices.notKept`.
- **An item whose text the library cannot give is not opened.** The page is emptied and read-only under a generation no item owns (`clearPage`).
- **A failed hand-over cancels a quit, a window's close or a library change,** and the person is told what to do, never the page's or WebKit's text. A page that takes longer than `EditorController.flushLimit` is given up on, and the person is told.
- **A page that goes down may have lost the last typing** (`EditorController.pageWentDown`). The person is told once, and until it is back or they answer (`lossHoldsFlush`), leaving the window fails. Going to another item works.
- **A page that ends again before it settles, or is not ready in time, is not reloaded** (`settleTime`, `reloadLimit`). A page still loading for the first time holds nothing typed.
- **Hand-overs take turns.** A close, quit or library change asked for during one waits for it (`EditorCloseDelegate`).
- **While Writing Tools run, an edit is held in `heldEdit`,** so a half-finished rewrite never reaches the item. Anything that ends its generation saves it first, on the version it was made on.
- **Each image that could not be placed in the text is named to the person,** and one that fails never stops the others. Quick add's files wait in `EditorController.pendingEmbeds` until the page shows that item.
- **Text typed into folded text is lost by Inkkit** (`EditorMessage.hiddenText`), so the person is told that it was not added.
- **Address rules are Inkkit's** (`normalizeLinkAddress`, `canOpenLink`). The app keeps none of its own.
- **The Outline lists only headings the page reported for the load now on it** (`EditorController.outline`). The app parses no headings.

## Embedded files and pictures

- **`ItemLibrary.openEmbeddedFile(_:in:waiting:)` is the one place an embed becomes a file,** by matching its exact text against what the core bound it to (`Item.boundEmbeds`). Open, Quick Look and printing go through it.
- **`OpenFile` opens with `O_NOFOLLOW_ANY`** and keeps the file only if the descriptor's own path is an ordinary file inside the expected directory, under no dot name. Never reopen by path after the check.
- **`EmbeddedFiles.opens` decides what another app may be handed,** never a file that might run: that is shown in the Finder. Quick Look runs nothing, so the rule does not apply to it. The kept copy of a file is read-only.
- **A picture at a web address is asked through the `pictures` handler** (`PictureRequests.reply`), after a saved file from the same address (`ItemLibrary.openSavedPicture`). The scheme serves only what the cache or the item holds.
- **Tell the page only which embeds, pictures or links may differ** (`EditorController.watchEmbeds`, `watchLinks`). `watchLinks` follows `namesRevision` and `membershipRevision`, never `contentRevision`, which a keystroke moves. Showing a picture or marking a link never rewrites the text.

## Header

- **The page draws the header and the app builds its data** (`MarfaMac/Views/ItemPageHeader.swift`) and carries out its events. Swift alone decides which rows are editable (`PropertyRow.editable`) and what a field's menu holds (`FieldMenu`).
- **A value opens in `ValueEditPresenter` under the rectangle the page sends,** and is written through the library as in the right sidebar. A refusal is told in the panel, never on the page.
- **A dragged row goes through `PageLayout.listing` and `PagePlacements`,** as in Customize Layout: it sets the order for the type and changes no item.
- **Customize Layout belongs to the window** (`DetailsPresentation.isCustomizingLayout`), and Escape from the page ends it.
- **Build the header only when what it reads changes** (`EditorController.showHeader`). Reading `contentRevision` or a whole list there rebuilds it at an edit anywhere.
- **A title is editable only where `ItemLibrary.canSetTitle(of:)` says so.** Unsaved and refused titles stay in `EditorController.titleDrafts`, and one still refused stops a quit, a library change or a close and names the item.
- **When a window goes, `windowWent()` removes its editor from `EditorController.open`.** Whatever else keeps an editor holds it weakly, or `flushAll` visits a closed window.

## Linking to items

- **The core reads links** (`linkParts(in:)`, `ItemLibrary.linkAnswers(of:in:)`). The app parses no link, folds no name, and passes the page's `raw` on as written.
- **A link is written only by `ItemLibrary.bodyLink(to:in:)`:** `[[Title]]` where the core answers `bound` for that item (`LinkAnswer.names`), and otherwise `[[identity|Title]]`.
- **Never write a form that the core and Inkkit read differently.** `ItemLinks.spells` refuses such a title and `ItemLinks.label` repairs a label.
- **`ItemRequests` answers the page's `items` requests.** Link to Item (`ItemLinkPicker`) answers exactly once on every path: chosen, canceled, the item left, the window gone or the page ended.
- **A suggestion is offered only where `LinkAnswer.offers` holds,** and a reply marks a link with a type only where the core binds it to one item held (`ItemLibrary.linkReadings`).
- **Following a link asks the core what that very link means** (`EditorController.openItemLink`), never by title. Only `bound` opens at once; otherwise a menu offers the items the name answers to, and a name of none beeps. No item is made for a link.
- **Wire `onOpenItem` wherever an editor is made.** A main window also sets `onFollowItemLink`, which follows Open Items.
- **A link's menu is built from `linkMenuEntries`** for the load it was asked on. Open Link is dimmed unless the page said `openable`.
- **`ItemLink.raw` defines equality,** so `[[Plan]]` and `[[Plan|Plan]]` stay distinct.

## Printing and PDF export

- **`PrintDocumentRenderer` renders Inkkit's frozen HTML in a separate web view,** with files through the checked path and pictures from the cache or a saved file only.
- **An export has a page and a size limit and is written atomically at the end,** so a failed one leaves an existing file unchanged.

## Code Review Rules

- **Embed escapes its directory.** Flag a path that reads, serves or opens an embedded file without `openEmbeddedFile`, follows a symbolic link, or reopens by path. Safe path: the descriptor `OpenFile` returns.
- **Runnable file opened.** Flag a route that hands a file to another app without `EmbeddedFiles.opens`.
- **Editor made for every view value.** Flag an `EditorController`, web view or other costly object made in a view's initializer or given to `State(initialValue:)`. Safe path: `EditorSlot`, or `.task`.
- **Unguarded private API.** Flag a private WebKit setting without a `responds(to:)` check, or one that Apple's own `WebView` does not use.
- **Link request left open.** Flag a path that ends Link to Item without one answer, writes a link without `bodyLink(to:in:)`, or parses, escapes or folds a link's text.
- **Edit saved to the wrong place.** Flag a save without the version it was typed on, or one that can land in another item.
