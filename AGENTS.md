# Marfa for Mac

A macOS app for a Marfa server's items. It works only through the `marfa-swift` package's working copy, names no item type but its own hidden settings, and holds no power that another app lacks.

## Before you change anything

`docs/` and the nested `AGENTS.md` files hold what the code and its tests cannot show. Read the rows that fit.

| If you change | Read |
| --- | --- |
| Files in a folder with an `AGENTS.md`, or under one | That file and those above it. Claude Code loads them by itself; Codex loads only those from the root down to its start folder, so open the others |
| `MarfaMac/Editor/` or `editor/` | Both `AGENTS.md` files |
| What something is, or its name | `docs/model.md`, and `docs/concepts.md` for the model the app is being built to |
| How anything looks | `docs/look.md`; then search `docs/rejected.md` |
| Sidebar, toolbar, corner, palette, opening an item | `docs/window.md` |
| A command, a menu or a shortcut | `docs/commands.md` |
| A view, layout, filter, group, index or search | `docs/lists.md` |
| What a row, card or column says | `docs/type-looks.md` |
| An item's page or its panel | `docs/item-page.md` |
| Making an item, its type, or a value's panel | `docs/editing.md`, `docs/value-panels.md` |
| The Settings window | `docs/settings-window.md`; for `Settings/Marfa/`, `docs/owner-settings.md` |
| Where a setting is kept | `docs/settings-sync.md` |
| A part of v0.1 you are asked to build | Its row in `docs/agreed.md` |

## Keeping this true

- **A page says what is on `main`.** The pull request that changes the fact changes the page, and one that builds a row of `docs/agreed.md` deletes it.
- **Add a rule only if no code, test or doc comment can hold it,** and to one place: a folder's rule to its `AGENTS.md`, a product rule to its page, one type's oddity to its doc comment.
- **Run `python3 Scripts/check-instructions.py`** after you change one of these files or a name it cites. It checks word budgets, names, links and repeats.
- **Edit `AGENTS.md`, never the `CLAUDE.md` symlink beside it.** List a new one under `MarfaMac/`, and its link, in the MarfaMac target's membership exceptions in `project.pbxproj`, or the build fails on duplicates.

## Working here

- Say "note" only for a `core.note`'s text, a type's name or the Note callout.
- Use American English. Put no time estimates, absolute paths, machine or account names or credentials in files. A comment says only why.
- Use scoped lowercase Conventional Commits in the present tense: `feat(app):`, `fix(editor):`.
- Work in `.claude/worktrees/`. `.agents/skills/land-a-pull-request/SKILL.md` says what to run and how to merge; the folders' `AGENTS.md` files have the commands.
- Keep no shims, aliases or migration paths.

## Platform

- Target macOS 27 and Xcode 27 only, with no `#available` checks.
- Use SwiftUI's native containers and controls, and AppKit only where SwiftUI cannot.
- Every user-facing string goes through the String Catalog. After an `xcodebuild` build, run `Scripts/sync-strings.sh <derived data>`.
- The app is not sandboxed. Release keeps the hardened runtime with no exceptions. Only WebKit's page process, the Marfa server, `PictureFetcher`, `Reporting`, the plugins release reader (`PluginRelease`), MapKit and Sparkle may connect out. Neither the item page nor a sealed web page loads from the network itself.

## Data rules

- Never drop or silently overwrite a person's text. A write that cannot be kept where meant is kept where the person can get it back (a conflicted copy, the queue, the clipboard or Downloads) and the person is told.
- An item's Markdown text is held byte for byte. Opened and left alone, it is never rewritten; an edit keeps the text of every block it did not reach.
- Views, commands and the editor reach a library only through `ItemLibrary`, read from the environment's `library` value, and name items by `ItemID`, never by path.
- This app's settings sync through the connected Marfa (`PreferencesSync`), but for what `PreferencesMap.staysOnMac` names.

## Project layout

- `MarfaMac.xcodeproj` uses folder-synchronized groups for `MarfaMac/`, `MarfaMacTests/` and `MarfaMacUITests/`. Add a file on disk only. A file under `MarfaMac/` is a resource unless the MarfaMac target's membership exceptions list it.
- Debug is `com.withmarfa.marfa.debug` and never shares the installed app's data or sign-ins, nor Marfa's command-line folder. Key paths and names on `AppPaths.bundleIdentifier`, never a literal.
- To compare design values, add a knob to the Debug-only `MarfaMac/Tuning/`, not variants.

## Signing and releases

- Never commit a team identifier, a report destination, an update feed or key or a version. They go in the ignored `Config/Local.xcconfig`; `MARKETING_VERSION` stays `0.0.0`.
- A version exists only as a git tag. Before you sign, tag or check a release, read the README's Signing and Releasing sections.

## Code Review Rules

Report only a problem you can show: the input, state or step, and what goes wrong.

- **Person's text lost.** Flag a write that fails, is refused or races another change and is dropped or written over newer text. Safe path: a conflicted copy, the queue, the clipboard or Downloads, and tell them.
- **Bytes rewritten.** Flag any change that rewrites an item's text the person did not edit, or blocks outside the edit. Safe path: edit in place and add a fixture to `editor/fixtures/corpus/` for any form found rewritten.
- **Platform rules.** Flag `#available` checks, shims, hard-coded user-facing strings, a committed team identifier, report destination, update setting or version, and custom chrome where a system control exists.
- **Note for item.** Flag a name, string, comment or doc that says note where it means any item. Safe path: say item, or the type's own name from the catalogue.
- **Stale instructions or docs.** Flag a change that leaves an `AGENTS.md`, `docs/` page, the README or a comment untrue. Name the page: its `paths` match the changed file.
