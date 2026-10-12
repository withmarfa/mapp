# Editor page

The note editor's page: TypeScript on InkKit, built by Vite into one self-contained file, `MAPP/Editor/Page/editor.html`. The Swift host that loads it is in `MAPP/Editor/`; read `MAPP/Editor/AGENTS.md` before changing the bridge or anything the host serves.

## Rules

- The built page is committed so the app builds without Node. After any change in `editor/`, run `pnpm build` and commit `MAPP/Editor/Page/editor.html` with the change. A build of an unchanged checkout leaves the committed page byte-identical.
- Import only InkKit's public facade, `@aicayzer/inkkit`, and its stylesheet. Never import InkKit's Milkdown or ProseMirror internals. If the page needs something the facade lacks, it belongs in a new InkKit release (`aicayzer/inkkit`); say so rather than reach past the facade.
- The page fetches nothing from the network and never navigates. Its Content-Security-Policy, in `editor/editor.html`, starts from `default-src 'none'` and allows the app's `mapp-embed:` scheme only for images, media, and frames. Do not widen it.
- The page learns what an embed is only through the `embeds` message, and loads an embedded file only through `mapp-embed:`.
- A PDF shows as a card with Open because WebKit does not paint local PDFs in InkKit's sandboxed frame. Keep the frame sandbox; do not loosen it to show PDFs.
- An embed of a note (`.md`, `.markdown`, `.txt`, or a bare name such as `![[A note]]`) shows a reference card whose Open switches to source editing. It never transcludes the note. Embeds inside code stay text.
- An image's width is kept in its alt text as `![name|400](…)` or `![[name|400]]`, since Obsidian reads both. Keep both forms working.
- Size text and the reading width in `rem`, so the text size setting scales them. The reading width comes from the page's margins, so a click beside the text still places the caret.
- The item's header (the title and the type, status, and parent chips) is part of the page, drawn by `editor/src/header.ts` above InkKit's root, so it scrolls with the text as one surface. It belongs to MAPP's page, not to InkKit. Do not move it back into a native overlay that follows WebKit's scrolling.
- One CSS rule in `editor/src/style.css` sets the inline padding of both `#item-header` and the text. Keep the header and the text in that one rule so their margins cannot drift.
- The header's actions are native: the page sends the title's input and commit and each chip's menu request to the app, and the app saves through `setItemProperty` and opens native menus. The page reports scrolling only when the header crosses under the toolbar (`headerScrolledAway`); do not post a message for every scroll.
- The bridge has two sides: `editor/src/bridge.ts` and `MAPP/Editor/EditorMessages.swift`. Change both in the same commit.

## Byte preservation

- InkKit keeps the text of every block an edit did not reach, and keeps link definitions, authored embeds, and `[[link]]` source. Only edited or new blocks take InkKit's canonical form.
- `editor/fixtures/corpus/` holds notes in unusual but valid markdown. Each has one paragraph containing `EDIT HERE`, which `editor/test/consumer.test.ts` edits and undoes, and expects every other byte back. Add a fixture for any form found to be rewritten.

## Commands

Run these in `editor/`:

- `pnpm install`
- `pnpm test`: the page's tests, in Vitest with jsdom.
- `pnpm typecheck`
- `pnpm format:check`: Prettier. `pnpm format` rewrites.
- `pnpm build`: writes `MAPP/Editor/Page/editor.html`.

`MAPPTests/EditorTests.swift` runs the built page in real WebKit through the app's bridge, so run the unit tests after `pnpm build`.

## Code Review Rules

- **Page out of date.** Flag a change under `editor/` whose commit does not include the rebuilt `MAPP/Editor/Page/editor.html`.
- **InkKit internals.** Flag any import from InkKit other than `@aicayzer/inkkit` and its stylesheet.
- **Network or navigation.** Flag a widened Content-Security-Policy, a fetch, or a navigation. Safe path: load embedded files through `mapp-embed:` only.
- **Rewritten source.** Flag a change that alters bytes outside the edited block, or a fix for a rewritten form without a corpus fixture.
- **One-sided bridge.** Flag a message added, renamed, or removed on one side of the bridge only.
