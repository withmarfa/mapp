# Editor page

The item editor's page: TypeScript on Inkkit, built by Vite into one self-contained file, `MarfaMac/Editor/Page/editor.html`. Its host is `MarfaMac/Editor/`; read `MarfaMac/Editor/AGENTS.md` before you change the bridge or anything the host serves. Read a module's doc comment before you change it.

## Build and dependencies

- **The built page and its notices are committed,** so the app builds without Node. After any change here, run `pnpm build` and commit `MarfaMac/Editor/Page/` with it. A build of an unchanged checkout leaves those files byte-identical.
- **Import only Inkkit's public facade,** `@aicayzer/inkkit`, and its stylesheet. If the facade lacks something, it needs a new Inkkit release (`aicayzer/inkkit`): say so.
- **Inkkit rejects a label it does not know.** The app's words and Inkkit's share `window.marfaLabels`, and `splitLabels` hands Inkkit only its own.

## Network and files

- **The page fetches nothing and never navigates.** Its Content-Security-Policy, in `editor/editor.html`, starts from `default-src 'none'`. Do not widen it.
- **What an embed is comes only from the `embeds` request,** asked with the embed's text exactly as written (`FileReference.raw`), and a file loads only through `marfa-embed:`. The page has no rule for what an embed names.
- **`embedsChanged(texts)` redraws just those embeds** with Inkkit's `refreshReferences`, which changes no document. Pictures and links are redrawn the same way.
- **An embed of an item shows as a file that is not found,** because the page never transcludes an item.
- **Keep Inkkit's frame sandbox.** A PDF is a card with Open; do not loosen the sandbox to paint it.
- **A file card's corner holds Quick Look before Open** (`src/file-actions.ts`). Inkkit refuses an action on a card that is a placeholder or opens when activated, so keep both off a file card.
- **A picture at a web address is asked of the app** (`src/pictures.ts`, `askPicture`), never of `embeds`. The page decides nothing of the setting. Printing and export ask with `'cached'`.
- **A waiting picture's Load button loads that picture alone** (`choose`), and only the bar at the top of the page loads them all (`chooseAll`).
- **Style a waiting picture with Inkkit's placeholder tokens** (`--inkkit-file-placeholder-*`). `src/style.css` adds rules only for what has no token.
- **A picture's width stays in its name, as `|400`,** in a Markdown picture and in an embed, because Obsidian reads both. Keep both forms working.

## Layout

- **Size text and the reading width in `rem`,** so the text size setting scales them, and keep other sizes on `--step`. The reading width comes from the page's margins, so a click beside the text places the caret.
- **The header (`src/header.ts`) is above Inkkit's root and the footer below it,** so they scroll as one surface. They are the app's. Do not move the header back into a native overlay.
- **Trap:** Inkkit's scroll container is `document.body`. Measured on `document.documentElement`, reveals and Find go wrong once the page has scrolled.
- **`--inkkit-column-inset`, set once on `body`, pads the text, the header and the footer.** Keep all three on it, and override no Inkkit selector to pad the text.
- **Draw property rows as flex rows, never a grid.** The comment in `style.css` says why.
- **The row above the title takes no room** and is only faded at rest, so a hover moves nothing and the keyboard and VoiceOver reach it.

## Header

- **The header draws what Swift sends and decides nothing:** not a kind, a type, which pins, a cap, an order or a menu. A pin's value keeps to one line and its whole text is the help.
- **It edits nothing and shows no error for a refused write.** A row flagged `editable` posts `editValue`, a field's name `fieldMenu`, a pin's button `headerMenu`, and Swift opens the editor or menu under the rectangle.
- **A dragged row posts `moveRow` with the whole order it shows,** folded rows included (`row-drag.ts`). Swift stores it and the page draws what comes back.
- **Report scrolling only when something changes for the toolbar** (`headerScrolledAway`, `contentUnderToolbar`), never at every scroll.

## Editing

- **Every option reaches the page as one set** (`window.editor.setOptions`), because each Inkkit call replaces its whole set. One option on a path of its own would reset the others.
- **`hidden-text` is not a fault.** An edit touched folded or unpainted text, and Inkkit has opened the section. A command is run once more after the next paint (`guardedCommand`), images are asked again by the app, and a refused replacement sends the matches again.
- **Input refused in folded text cannot be replayed,** because Inkkit drops it. The page posts `hiddenText`. Never drop a refused input without telling the person.
- **Inkkit paints the selection.** Set its color tokens on `:root`, and override no `::selection` or `::highlight` rule.
- **`appendImages` adds embeds after the last block in one undo step** and does nothing to an item loaded since. It refuses where it would change other text; keep the source comparison in `ItemEditor.appendImages`.

## Links

- **The page asks about items through the `items` handler,** which answers every request: `suggest`, `pick` and `resolve`. A command that gets nothing back leaves the line as typed. Change these with `MarfaMac/Editor/ItemRequests.swift`.
- **Forward `WikiLinkReference.raw` unchanged** through opening, resolution and cache identity, because Marfa binds each spelling separately. The page never guesses which item a name means.
- **A heading of the same item is revealed by its text** (`ItemEditor.revealHeading`), and the Outline by its place in the list (`ItemEditor.revealHeadingAt`), so two that read the same each have their own.
- **An address leaves to be opened only through `openLink` in `src/bridge.ts`,** which drops what Inkkit's `canOpenLink` refuses; the app checks nothing more. `linkMenu` carries `openable`, and the app opens its address only where that is true.
- **The page keeps no link menu.** The app builds it, and Edit Link and Remove Link come back as `format` and `unlinkSelected`.
- **Trap:** Inkkit reads a capital letter in a `setKeymap` key as Shift.
- **`src/links.ts` answers Inkkit from what the app last said,** for the item on the page only, and `linksChanged` asks again. Links are drawn again (`ItemEditor.drawLinksAgain`) without changing the text.
- **Check the app's icon and color first,** because Inkkit throws on one it cannot read. The page decides neither.
- **How a link looks is the app's setting** (`src/link-style.ts`). The page holds no look, accent, highlight color or font of its own beyond fallbacks.

## Bridge

- **Change `editor/src/bridge.ts` and `MarfaMac/Editor/EditorMessages.swift` in one commit,** with `editor/bridge-messages.json`, which lists every message, request and `window.editor` function and which both sides' tests read.
- **After each `load` the page posts `painted` with its generation,** unless a later load has taken over. The app ends its `item.open` signpost there.
- **The page posts `headings` after each load, and after an edit only when the list differs.** It is the Outline's only source.

## Byte preservation

- **Inkkit keeps the text of every block an edit did not reach,** and link definitions, embeds and `[[link]]` source. Only edited or new blocks take its canonical form. An embed it cannot write back as read stays a block of literal Markdown, and the page asks nothing for it.
- **`editor/fixtures/corpus/` holds unusual but valid Markdown.** Each text has one paragraph with `EDIT HERE`, which `editor/test/consumer.test.ts` edits and undoes, expecting every other byte back. Add a fixture for any form found rewritten.

## Commands

Run these in `editor/`: `pnpm install`, `pnpm test`, `pnpm typecheck`, `pnpm format:check` and `pnpm build`. The `EditorTests` suite (`MarfaMacTests/EditorTests*.swift`) runs the built page in real WebKit, so run it after a build.

## Code Review Rules

- **Page out of date.** Flag a change under `editor/` whose commit lacks the rebuilt `MarfaMac/Editor/Page/editor.html`.
- **Inkkit internals.** Flag an import from Inkkit other than `@aicayzer/inkkit` and its stylesheet.
- **Network or navigation.** Flag a widened Content-Security-Policy, a fetch or a navigation. Safe path: `marfa-embed:` for files, and `pictures` for a picture at a web address.
- **Rewritten source.** Flag a change that alters bytes outside the edited block, or a fix for a rewritten form without a fixture.
- **One-sided bridge.** Flag a message or request added, renamed or removed on one side only.
- **Unanswered page.** Flag an `items` request that the app can leave without an answer, because the page's command then waits for ever.
