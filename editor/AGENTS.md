# Editor page

The note editor's page: TypeScript on Inkkit, built by Vite into one self-contained file, `MAPP/Editor/Page/editor.html`. The Swift host that loads it is in `MAPP/Editor/`; read `MAPP/Editor/AGENTS.md` before changing the bridge or anything the host serves.

## Rules

- The built page is committed so the app builds without Node. After any change in `editor/`, run `pnpm build` and commit `MAPP/Editor/Page/editor.html` with the change. A build of an unchanged checkout leaves the committed page byte-identical.
- Import only Inkkit's public facade, `@aicayzer/inkkit`, and its stylesheet. Never import Inkkit's Milkdown or ProseMirror internals. If the page needs something the facade lacks, it belongs in a new Inkkit release (`aicayzer/inkkit`); say so rather than reach past the facade.
- The page fetches nothing from the network and never navigates. Its Content-Security-Policy, in `editor/editor.html`, starts from `default-src 'none'` and allows the app's `mapp-embed:` scheme only for images, media, and frames. Do not widen it.
- The page learns what an embed is only through the `embeds` message, and loads an embedded file only through `mapp-embed:`.
- A PDF shows as a card with Open because WebKit does not paint local PDFs in Inkkit's sandboxed frame. Keep the frame sandbox; do not loosen it to show PDFs.
- An embed of a note (`.md`, `.markdown`, `.txt`, or a bare name such as `![[A note]]`) shows a reference card whose Open switches to source editing. It never transcludes the note. Embeds inside code stay text.
- An image's width is kept in its alt text as `![name|400](…)` or `![[name|400]]`, since Obsidian reads both. Keep both forms working.
- Size text and the reading width in `rem`, so the text size setting scales them. The reading width comes from the page's margins, so a click beside the text still places the caret.
- The item's header (the title and the type, status, and parent pins) is part of the page, drawn by `editor/src/header.ts` above Inkkit's root, so it scrolls with the text as one surface. It belongs to MAPP's page, not to Inkkit. Do not move it back into a native overlay that follows WebKit's scrolling.
- `--inkkit-column-inset`, set once on `body` in `editor/src/style.css`, is the inline padding of the text, which Inkkit reads, and of `#item-header`. Keep the header on that one value so their margins cannot drift, and override no Inkkit selector to pad the text.
- Inkkit rejects a label it does not know. `window.mappLabels` carries the app's own words (the header's, `noteReference` and `linkToNote`) beside Inkkit's labels, and `splitLabels` in `editor/src/editor.ts` hands Inkkit only its own. A word of the app's own never goes to Inkkit.
- Inkkit's slash menu is on with every built-in command and MAPP's own Link to Note, and `[[` offers the library's notes through the wiki link adapter. Because the adapter is set, a link typed in full, such as `[[Note]]`, becomes a link and is saved as typed; `editor/test/consumer.test.ts` covers it. The table shortcut and Option-Up and Option-Down to move a block are Inkkit's defaults. Leave `textInput.smartPunctuation` unset, so the page makes no curly quotes or dashes of its own; the system's Substitutions setting still applies, as in any Mac text field, and is not the page's to change. The labels for all of it come from the app's strings (`EditorController.editorLabels`); `editor/test/consumer.test.ts` reads that block and mounts Inkkit with it.
- The page asks the app about notes through the `notes` message handler, which answers each request: `suggest` for the titles to offer after `[[`, `pick` for Link to Note, which is answered when the person has chosen, however long that takes, and with nothing if they decline, and `resolve` for which of a note's links name no note. A command that gets nothing back leaves the line as typed. Change these with `MAPP/Editor/NoteRequests.swift`.
- A command-click (or Enter or Space on the focused link) on a `[[link]]` posts `openNote` with the link (its name, which may be a title, a path or an identity, any heading and any alias) and the note it was clicked in. The alias is part of the link because Marfa binds each spelling on its own. The app resolves it through the library and opens the note; the page never guesses which note a name means. A link to a heading of its own note, `[[#Heading]]`, is followed in the page (`NoteEditor.revealHeading`).
- Inkkit asks about each link as it draws it and wants the answer at once (`WikiLinkAdapter.resolve`), so `editor/src/links.ts` answers from what the app last said, draws a link as live until it knows otherwise, asks for the links of one pass over the note in one `resolve` request, and keeps the answers for the note on the page only. The app tells the page its library changed (`linksChanged`) and every answer is asked again; links are drawn again only if an answer changed. This never changes the note's text.
- Links are drawn again with Inkkit's `refreshReferences`, naming the notes whose answer changed (`NoteEditor.drawLinksAgain`). It changes no text, so it works in a read-only note and during composition, and it does nothing in source editing, where no link is drawn. `editor/test/links.test.ts` mounts the real Inkkit and covers all three. Inkkit (the version in `editor/package.json`) does not style wiki links (aicayzer/inkkit#159), so `editor/src/style.css` styles `.inkkit-wiki-link` and its `data-missing` mark.
- `window.editor.focusTitle(item)` gives the title the keyboard and selects its text once the header shows that item, for a new item; `focus` and `load` cancel a wait for it. It is used once.
- `window.editor.focusText(prefix)` gives the text the keyboard with the caret after `prefix`, the Markdown source typed before the caret in quick add, matched against the readable text by `caretOffset`, which passes over markup the page does not show. A null prefix puts the caret at the end; the app sends null when the prefix would be too long for one message (`PageCaret.limit`).
- `window.editor.appendImages(images, expected)` adds embeds after the last block of the text, for files attached in quick add after the item was made, with Inkkit's `appendImages`: no focus, no scroll, the selection stays on its text, one undo step, saved like typing, and nothing happens to a note loaded since (`expected`). It answers false in source editing and leaves the images to the app, which sends them again. A note that ends in a code fence left open refuses it (`preservation`, the page answers `commandError`); the text is untouched and the app tells the person the files are attached but not in the text. Do not write the images into the source here.
- The header's actions are native: the page sends the title's input and commit and each pin's menu request to the app, and the app saves through `setItemProperty` and opens native menus. A refused status or a refused Remove Parent is told under the pins (`propertyRejected`, `parentRejected`), each apart from the other. The page reports scrolling only when the header crosses under the toolbar (`headerScrolledAway`); do not post a message for every scroll.
- The pins under the title share one shape, drawn in `editor/src/style.css` from the interface text size: 24 point high at the default size, a 1 point separator edge and no fill (only hover fills), 12 point medium text and a symbol in the secondary color. A pin that opens a menu (status, and parent once it has a value) ends in a chevron; one with no value is empty, with a plus and a quieter edge. The app sends `opensMenu: false` for a pin that opens its chooser directly, as an empty parent does, and the page then draws no chevron. The status ring's color and fill come from the app in the pin's `mark`, since the catalogue holds neither. An empty parent pin still posts `headerMenu`, and the app opens the chooser. The app draws the symbols (`PageHeaderIcons`) and the page uses them as masks.
- The bridge has two sides: `editor/src/bridge.ts` and `MAPP/Editor/EditorMessages.swift`. Change both in the same commit.

## Byte preservation

- Inkkit keeps the text of every block an edit did not reach, and keeps link definitions, authored embeds, and `[[link]]` source. Only edited or new blocks take Inkkit's canonical form.
- `editor/fixtures/corpus/` holds notes in unusual but valid markdown. Each has one paragraph containing `EDIT HERE`, which `editor/test/consumer.test.ts` edits and undoes, and expects every other byte back. Add a fixture for any form found to be rewritten.

## Commands

Run these in `editor/`:

- `pnpm install`
- `pnpm test`: the page's tests, in Vitest with jsdom.
- `pnpm typecheck`
- `pnpm format:check`: Prettier. `pnpm format` rewrites.
- `pnpm build`: writes `MAPP/Editor/Page/editor.html`.

The `EditorTests` suite (`MAPPTests/EditorTests*.swift`) runs the built page in real WebKit through the app's bridge, so run the unit tests after `pnpm build`.

## Code Review Rules

- **Page out of date.** Flag a change under `editor/` whose commit does not include the rebuilt `MAPP/Editor/Page/editor.html`.
- **Inkkit internals.** Flag any import from Inkkit other than `@aicayzer/inkkit` and its stylesheet.
- **Network or navigation.** Flag a widened Content-Security-Policy, a fetch, or a navigation. Safe path: load embedded files through `mapp-embed:` only.
- **Rewritten source.** Flag a change that alters bytes outside the edited block, or a fix for a rewritten form without a corpus fixture.
- **One-sided bridge.** Flag a message added, renamed, or removed on one side of the bridge only, including a request to the `notes` handler.
- **Unanswered page.** Flag a `notes` request the app can leave without an answer, since the page's command then waits for ever.
