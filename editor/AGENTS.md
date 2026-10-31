# Editor page

The note editor's page: TypeScript on Inkkit, built by Vite into one self-contained file, `MAPP/Editor/Page/editor.html`. The Swift host that loads it is in `MAPP/Editor/`; read `MAPP/Editor/AGENTS.md` before changing the bridge or anything the host serves. The modules named here say in their doc comments how they draw and what they ask; read them before changing their behavior.

## Build and dependencies

- The built page and its license notices are committed so the app builds without Node. After any change in `editor/`, run `pnpm build` and commit `MAPP/Editor/Page/` with the change. A build of an unchanged checkout leaves those files byte-identical. The host-generated notice follows this app's lockfile; Inkkit's notices (`INKKIT-THIRD-PARTY-NOTICES.txt`) cover what it bundles, Pele among them.
- Import only Inkkit's public facade, `@aicayzer/inkkit`, and its stylesheet. Never import Inkkit's Milkdown or ProseMirror internals. If the page needs something the facade lacks, it belongs in a new Inkkit release (`aicayzer/inkkit`); say so rather than reach past the facade.
- Inkkit rejects a label it does not know. `window.mappLabels` carries the app's own words beside Inkkit's, and `splitLabels` in `editor/src/editor.ts` hands Inkkit only its own.

## Network and files

- The page fetches nothing from the network and never navigates, including for a picture at a web address, which it asks the app for. Its Content-Security-Policy, in `editor/editor.html`, starts from `default-src 'none'` and allows the app's `mapp-embed:` scheme only for images, media, and frames. Do not widen it.
- The page learns what an embed is only through the `embeds` message, and loads an embedded file only through `mapp-embed:`. It asks with the embed's text exactly as written (`FileReference.raw`: alias, size suffix, escapes, a table cell's `\|`), and the app answers from what Marfa's core bound that text to. The page applies no rule of its own for what an embed names. `embedsChanged(texts)` has the page forget those answers and redraw just those embeds with Inkkit's `refreshReferences`, which changes no document.
- An embed of a note is not a file and shows as File Not Found: the page never transcludes a note. A PDF shows as a card with Open; keep Inkkit's frame sandbox and do not loosen it to paint PDFs.
- A picture at a web address is never asked of the `embeds` handler and never fetched by the page. `src/pictures.ts` (`WebPictures`) asks the app through the `pictures` message (`askPicture` in `src/bridge.ts`) and draws each picture's state; the page decides nothing of the setting or of which items Always applies to. Printing and export ask with `'cached'` (`printable()` sets `cacheOnly`), so they show only what the app already holds. A loaded picture is drawn again with `refreshReferences`, which changes no document.
- An image's width is kept in its alt text as `![name|400](…)` or `![[name|400]]`, since Obsidian reads both. Keep both forms working.

## Layout

- Size text and the reading width in `rem`, so the text size setting scales them. The reading width comes from the page's margins, so a click beside the text still places the caret.
- The item's header (`editor/src/header.ts`) is drawn above Inkkit's root and its footer below it, so both scroll with the text as one surface. They belong to MAPP's page, not to Inkkit. Do not move the header back into a native overlay.
- `--inkkit-column-inset`, set once on `body` in `editor/src/style.css`, pads the text, `#item-header` and `#item-footer`. Keep all three on that one value, and override no Inkkit selector to pad the text.
- The header draws the rows and the kind Swift sends (`PropertyRow`, `PageHeaderKind` as `kind`, `showsTitle`, `showsText`, `symbol`, `mark`) and never decides a kind, names a type, or loads anything. A link value posts `openItem` or `openLink`; nothing else in the property block is edited here.
- Keep every size on the 4 point grid (`--step`) and scale it with the interface text size. Draw property rows as flex rows, never a grid (the comment in `style.css` says why).

## Editing

- Inkkit's slash menu is on with every built-in command and MAPP's own Link to Note, and `[[` offers the library's notes through the wiki link adapter. Leave `textInput.smartPunctuation` unset, so the page makes no curly quotes or dashes of its own. `editor/test/consumer.test.ts` mounts Inkkit with the app's labels (`EditorController.editorLabels`).
- Inkkit paints the selection. The page sets its colors as `--inkkit-selection-background` and `--inkkit-inactive-selection-background` on `:root`; override no `::selection` or `::highlight` rule. `window.editor.setHostActive` changes no focus, text or history.
- `window.editor.appendImages(images, expected)` adds embeds after the last block in one undo step, saved like typing, and does nothing to a note loaded since. It refuses in source editing and with `preservation` where it would change any other text; keep the defensive source comparison in `NoteEditor.appendImages`, and never write the images into the source here.
- The header's actions are native: the page sends the title's input and commit and each pin's menu request, and the app saves and opens menus. The page reports scrolling only when something changes for the toolbar (`headerScrolledAway`, `contentUnderToolbar`); do not post a message for every scroll.

## Links

- The page asks the app about notes through the `notes` message handler, which answers every request: `suggest` after `[[`, `pick` for Link to Note (answered when the person has chosen or declined), and `resolve`. A command that gets nothing back leaves the line as typed. Change these with `MAPP/Editor/NoteRequests.swift`.
- Opening a `[[link]]` posts `openNote` with its exact authored `raw` text. Forward `WikiLinkReference.raw` unchanged through opening, resolution and cache identity: Marfa binds each spelling separately. The page never guesses which note a name means. A link to a heading of its own note is followed in the page (`NoteEditor.revealHeading`).
- `editor/src/links.ts` answers Inkkit's `WikiLinkAdapter.resolve` from what the app last said, for the note on the page only, and `linksChanged` asks again. Links are drawn again with `refreshReferences` (`NoteEditor.drawLinksAgain`), which never changes the note's text. Inkkit styles wiki links; the page adds no rule for them.

## Bridge

- The bridge has two sides: `editor/src/bridge.ts` and `MAPP/Editor/EditorMessages.swift`. Change both in the same commit.
- After each `load` the page posts `painted` with its generation once the browser has drawn the document, and not if a later `load` or `reload` has given the page another generation by then. The app ends its `item.open` signpost there.

## Byte preservation

- Inkkit keeps the text of every block an edit did not reach, and keeps link definitions, authored embeds, and `[[link]]` source. Only edited or new blocks take Inkkit's canonical form. Where Inkkit cannot write an embed back as it was read, it keeps the block as literal Markdown and the page asks nothing for it.
- `editor/fixtures/corpus/` holds notes in unusual but valid markdown. Each has one paragraph containing `EDIT HERE`, which `editor/test/consumer.test.ts` edits and undoes, and expects every other byte back. Add a fixture for any form found to be rewritten.

## Commands

Run these in `editor/`: `pnpm install`, `pnpm test` (Vitest with jsdom), `pnpm typecheck`, `pnpm format:check` (`pnpm format` rewrites), and `pnpm build`, which writes `MAPP/Editor/Page/editor.html`.

The `EditorTests` suite (`MAPPTests/EditorTests*.swift`) runs the built page in real WebKit through the app's bridge, so run the unit tests after `pnpm build`.

## Code Review Rules

- **Page out of date.** Flag a change under `editor/` whose commit does not include the rebuilt `MAPP/Editor/Page/editor.html`.
- **Inkkit internals.** Flag any import from Inkkit other than `@aicayzer/inkkit` and its stylesheet.
- **Network or navigation.** Flag a widened Content-Security-Policy, a fetch, or a navigation. Safe path: load embedded files and pictures through `mapp-embed:` only, and ask the app, through `pictures`, for a picture at a web address.
- **Rewritten source.** Flag a change that alters bytes outside the edited block, or a fix for a rewritten form without a corpus fixture.
- **One-sided bridge.** Flag a message added, renamed, or removed on one side of the bridge only, including a request to the `notes` handler.
- **Unanswered page.** Flag a `notes` request the app can leave without an answer, since the page's command then waits for ever.
