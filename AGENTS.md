# Marfa for Mac

Marfa for Mac is a macOS app for a Marfa server's items, with a sidebar, a list and a page. It works only through the `marfa-swift` package's working copy, names no item type but its hidden settings (`app.marfa-mac.preferences`), and holds no power another app lacks. Concepts and agreed designs are in `docs/`; each directory's rules are in its `AGENTS.md`.

## Read before you change

| If you change | Read first |
| --- | --- |
| `MarfaMac/Model/` | its `AGENTS.md`; for `Marfa/` also that folder's |
| `MarfaMac/Views/` or `MarfaMac/Settings/` | `AGENTS.md` there; for `Settings/Marfa/` also its own |
| `MarfaMac/Editor/` or `editor/` | both `AGENTS.md` files, since the bridge spans them |
| `MarfaMacTests/` | `MarfaMacTests/AGENTS.md` |
| How anything looks: a row, chip, card, page or panel | the matching page in `docs/`; `docs/glossary.md` lists the terms |
| What Marfa holds and what stays on the Mac | `docs/marfa-and-the-mac-app.md`, `docs/settings-storage.md` |

## Instruction files

- Each `AGENTS.md` has a `CLAUDE.md` symlink beside it, which delivers it to Claude Code. Edit the file, never the link. Codex loads no nested file, so the table above is how it finds the rest.
- Keep each file under 200 lines and each chain from this file to a nested one under 32,000 bytes (Codex stops at 32 KiB). Detail about one type belongs in its doc comment, a concept in `docs/`.
- List a new `AGENTS.md` under `MarfaMac/` and its link in the MarfaMac target's membership exceptions in `project.pbxproj`, or the build fails on duplicate resources.
- Run `python3 Scripts/check-instructions.py` after changing an instruction file, a doc or a name a doc cites. It checks the limits, links, membership exceptions and that each name on a doc's "Where it lives" line exists. CI runs it as `Instructions`, on drafts too.

## Working here

- Marfa for Mac is an app for items of every type. Names, strings and comments say "note" only for a `core.note`'s text, a type's own name or the Note callout.
- Use American English. Put no time estimates, absolute paths, machine or account names or credentials in files. A comment says only why.
- Use scoped lowercase Conventional Commits in the present tense: `feat(app):`, `fix(editor):`.
- Work on a branch in a worktree under `.claude/worktrees/` and reach `main` through a pull request. Merge it as `.agents/skills/land-a-pull-request/SKILL.md` says.
- CI runs each check only when its files changed, and retries nothing: `checks.yml` on pull requests, with `Checks` the one required check (green on a draft, which runs no Swift job), and `release-build.yml` on `main`.
- Keep no legacy: no shims, deprecation aliases or migration paths.

## Platform

- Target macOS 27 and Xcode 27 only, with no `#available` checks. Swift 6 language mode, main-actor isolation by default. Unit tests use Swift Testing; UI tests use XCTest.
- Use SwiftUI with native containers and controls, and AppKit only where SwiftUI cannot express something. Check API questions against Apple's documentation.
- Every user-facing string goes through the String Catalog. Building in Xcode updates `MarfaMac/Localizable.xcstrings`; `xcodebuild` alone does not.
- The app is not sandboxed and keeps the hardened runtime with no exceptions. Only WebKit's page process, the Marfa server, `PictureFetcher`, `Reporting`, the plugins release reader (`PluginRelease`) and Sparkle may connect out. Neither the item page nor a sealed web page loads from the network itself.

## Data rules

- Never drop or silently overwrite a person's text. A write that cannot be kept where meant is kept where the person can get it back (a conflicted copy, the queue, the clipboard) and the person is told.
- An item's Markdown text is held byte for byte. Opened and left alone, it is never rewritten; an edit keeps the text of every block it did not reach.
- Views, commands, and the editor reach a library only through `ItemLibrary`, read from the environment's `library` value, and name items by `ItemID`, never by path.
- This app's settings sync through the connected Marfa (`PreferencesSync`), but for what `PreferencesMap.staysOnMac` names.

## Project layout

- `MarfaMac.xcodeproj` uses folder-synchronized groups for `MarfaMac/`, `MarfaMacTests/` and `MarfaMacUITests/`. Add a file on disk, not in `project.pbxproj`. A file under `MarfaMac/` is a resource unless the MarfaMac target's membership exceptions list it. `Design/` is not in the app.
- Debug is `com.withmarfa.marfa.debug` and never shares the installed app's data or sign-ins, nor Marfa's command-line folder. `MarfaMac/Info.plist` claims it as the sign-in URL scheme. Key paths and names on `AppPaths.bundleIdentifier`, never a literal.
- To compare design values, add a knob to the Debug-only `MarfaMac/Tuning/` panel, not variants, and remove it once settled.

## Commands

The unit, UI and `Live` test commands, and measuring, are in `MarfaMacTests/AGENTS.md`; the editor page's commands are in `editor/AGENTS.md`.

## Signing and releases

- Never commit a team identifier, a report destination, an update feed or key or a version. They go in the ignored `Config/Local.xcconfig`; `MARKETING_VERSION` stays `0.0.0`.
- A version exists only as a git tag (`v0.0.x`, candidates `v0.0.x-rcN` for the beta channel), made soon after a merge to `main` that changes what a person sees or does; tests, CI and docs alone are not tagged. A tag starts `release.yml`, which publishes through Sparkle. Before you sign, tag or check a release, read the README's Signing and Releasing sections, and try a choice in a local build first.

## Code Review Rules

Report only a problem you can show: name the input, state or step, and what goes wrong. Leave formatting to the tools. Nested files add rules.

- **Person's text lost.** Flag any path where a write that fails, is refused or races another change is dropped or written over newer text. Safe path: a conflicted copy, the queue or the clipboard, and tell the person.
- **Bytes rewritten.** Flag any change that rewrites an item's text the person did not edit, or blocks outside the edit. Safe path: edit in place and add a fixture to `editor/fixtures/corpus/` for any form found rewritten.
- **Platform rules.** Flag `#available` checks, shims, hard-coded user-facing strings, a committed team identifier, report destination, update setting or version, and custom chrome where a system control exists.
- **Note for item.** Flag a name, string, comment or doc that says note where it means any item. Safe path: say item, or the type's own name from the catalogue.
- **Stale instructions or docs.** Flag a change that leaves an `AGENTS.md`, a `docs/` page, the README or a comment untrue; fix it in the same pull request.
