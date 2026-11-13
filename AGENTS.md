# MAPP

MAPP is a native macOS markdown notes app with a sidebar, a list and a page, like Notes and Mail. It reads and writes a library only through a Marfa server, by the `marfa-swift` package's working copy, and names no item type of its own. The note editor is a web page built on Inkkit in a `WKWebView`. Concepts and agreed designs are in `docs/`; a directory's rules are in the `AGENTS.md` beside its code.

## Read before you change

| If you change | Read first |
| --- | --- |
| `MAPP/Model/` | `MAPP/Model/AGENTS.md`; for `Marfa/` also `MAPP/Model/Marfa/AGENTS.md` |
| `MAPP/Views/` | `MAPP/Views/AGENTS.md` |
| `MAPP/Editor/` or `editor/` | both `AGENTS.md` files, since the bridge spans them |
| `MAPPTests/` | `MAPPTests/AGENTS.md` |
| How anything looks: a row, chip, card, page or panel | the matching page in `docs/`; `docs/glossary.md` lists the terms |
| What Marfa holds and what stays on the Mac | `docs/marfa-and-mapp.md`, `docs/settings-storage.md` |

## Instruction files

- Each `AGENTS.md` has a `CLAUDE.md` symlink beside it. Edit the file, never the link.
- Claude Code reads `AGENTS.md` only when no `CLAUDE.md` exists in or above the working directory, so each link is what delivers its file. Codex loads no nested file below where it starts, so the table above is how it finds the rest.
- Keep each file under 200 lines and each chain from this file to a nested one under 32,000 bytes, since Codex stops reading at 32 KiB (32,768 bytes). Detail about one type belongs in its doc comment, and a concept in `docs/`, stated once and linked.
- List a new `AGENTS.md` under `MAPP/` and its link in the MAPP target's membership exceptions in `project.pbxproj`, or the build fails on duplicate resources.

## Working here

- Use American English. Put no time estimates, absolute paths, machine or account names or credentials in any file. A comment says only why.
- Use scoped lowercase Conventional Commits in the present tense: `feat(app):`, `fix(editor):`.
- Work on a branch in a worktree under `.claude/worktrees/` and reach `main` through a pull request, squash-merged once the tests pass and a reviewer has read it. Then run `git worktree remove`, `git branch -D` (a squash-merge looks unmerged) and `git pull --ff-only`.
- CI (`.github/workflows/checks.yml`) runs on a pull request that is ready, each check only when its files changed, and retries nothing; `Checks` is the one job to require. A draft runs no Swift job: run the tests yourself and mark it ready once reviewed.
- Keep no legacy: no shims, deprecation aliases or migration paths.

## Platform

- Target macOS 27 and Xcode 27 only, with no `#available` checks. Swift 6 language mode, main-actor isolation by default. Unit tests use Swift Testing; UI tests use XCTest.
- Use SwiftUI with native containers and controls, and AppKit only where SwiftUI cannot express something. Check API questions against Apple's documentation.
- Every user-facing string goes through the String Catalog. Building in Xcode updates `MAPP/Localizable.xcstrings`; `xcodebuild` alone does not.
- App Sandbox and the hardened runtime stay on. Outgoing connections are allowed only for WebKit's page process, the Marfa server, `PictureFetcher` and `Reporting`. Neither the note page nor a sealed web page loads anything from the network itself.

## Data rules

- Never drop or silently overwrite a person's text. A write that cannot be kept where it was meant to go is kept where the person can get it back (a conflicted copy, the queue, the clipboard) and the person is told.
- Notes are held byte for byte. A note opened and left alone is never rewritten; an edit keeps the text of every block it did not reach.
- Views, commands, and the editor reach a library only through `ItemLibrary`, read from the environment's `library` value, and name items by `ItemID`, never by path.
- Mac settings are never written to Marfa (`docs/settings-storage.md`).

## Project layout

- `MAPP.xcodeproj` uses folder-synchronized groups for `MAPP/`, `MAPPTests/` (unit tests) and `MAPPUITests/` (UI tests). Add a source file by creating it on disk, not by editing `project.pbxproj`. Every file under `MAPP/` becomes an app resource unless the MAPP target's membership exceptions list it. `Design/` holds artwork that is not built into the app.
- Debug is `com.withmarfa.mapp.debug` and never shares the installed app's data or sign-ins; `MAPP/Info.plist` claims it as the sign-in's URL scheme. Key anything that must differ on `Bundle.main.bundleIdentifier`, never a literal.
- To compare design values, add a knob to the Debug-only `MAPP/Tuning/` panel, not variants, and remove it once the value is settled.

## Commands

The unit, UI and `Live` test commands, and measuring, are in `MAPPTests/AGENTS.md`; the editor page's commands are in `editor/AGENTS.md`.

## Signing and releases

- Never commit a team identifier, a report destination (`MARFA_POSTHOG_HOST`, `MARFA_POSTHOG_PROJECT_TOKEN`) or a version. They go in the ignored `Config/Local.xcconfig`; `MARKETING_VERSION` stays `0.0.0`.
- A version exists only as a git tag (`v0.0.x`, candidates `v0.0.x-rcN`), made soon after a merge to `main` that changes what a person sees or does; tests, CI and docs alone are not tagged. Before you sign, tag or check a release, read the README's Signing and Releasing sections.
- TestFlight is for internal testers: tag freely to put a change in front of them. Use a local build when a choice needs trying before it ships.

## Code Review Rules

Report only a problem you can show: name the input, state or step, and what goes wrong. Leave formatting to the tools. Nested files add rules.

- **Person's text lost.** Flag any path where a write that fails, is refused or races another change is dropped or written over newer text. Safe path: a conflicted copy, the queue or the clipboard, and tell the person.
- **Bytes rewritten.** Flag any change that rewrites a note the person did not edit, or blocks outside the edit. Safe path: edit in place and add a fixture to `editor/fixtures/corpus/` for any form found rewritten.
- **Platform rules.** Flag `#available` checks, shims, hard-coded user-facing strings, a committed team identifier, report destination or version, and custom chrome where a system control exists.
- **Stale instructions or docs.** Flag a change that leaves an `AGENTS.md`, a `docs/` page, the README or a comment untrue; fix it in the same pull request.
