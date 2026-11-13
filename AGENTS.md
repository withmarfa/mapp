# MAPP

MAPP is a native macOS markdown notes app with a sidebar, a list, and a page, in the manner of Notes and Mail. It reads and writes a library only through a Marfa server, by the `marfa-swift` package's working copy, and names no item type of its own. The note editor is a web page built on Inkkit in a `WKWebView`. Concepts and agreed designs are in `docs/`; the rules for a directory are in the `AGENTS.md` beside its code.

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
- Claude Code reads `AGENTS.md` directly only when no `CLAUDE.md` exists in or above the working directory. A parent folder may hold one, and Claude Code then ignores `AGENTS.md`, so each link is what delivers its file. Codex reads one file per directory from the root down to where it starts and loads no nested file below that, so the table above is how it finds the rest.
- Keep each file under 200 lines and each chain from this file to a nested one under 32 KiB, since Codex stops reading there. Detail about one type belongs in its doc comment, and a concept in `docs/`, stated once and linked, never copied.
- List a new `AGENTS.md` under `MAPP/` and its link in the MAPP target's membership exceptions in `project.pbxproj`, or the build fails on duplicate resources.

## Working here

- Use American English. Put no time estimates, absolute paths, machine or account names, or credentials in any file. A comment says only why.
- Use scoped Conventional Commits, present tense and lowercase: `feat(app):`, `fix(editor):`.
- Work on a branch in a worktree under `.claude/worktrees/` and reach `main` through a pull request, squash-merged once the tests pass and a reviewer has read it. Then remove the worktree (`git worktree remove`), delete the branch with `git branch -D` (a squash-merge looks unmerged) and run `git pull --ff-only` on `main`.
- CI (`.github/workflows/checks.yml`) runs on a pull request that is ready; `Checks` is the one job to require. A draft runs no Swift job, so run the tests yourself and mark it ready once reviewed.
- Keep no legacy: no shims, deprecation aliases, or migration paths.

## Platform

- Target macOS 27 and Xcode 27 only, with no `#available` checks. Swift 6 language mode, main-actor isolation by default. Unit tests use Swift Testing; UI tests use XCTest.
- Use SwiftUI and native containers and controls, and AppKit only where SwiftUI cannot express something. Check API and design questions against Apple's documentation and the HIG.
- Every user-facing string goes through the String Catalog. Building in Xcode updates `MAPP/Localizable.xcstrings`; `xcodebuild` alone does not.
- App Sandbox and the hardened runtime stay on. Outgoing connections are allowed only for WebKit's page process, the Marfa server, `PictureFetcher` and `Reporting`.

## Data rules

- Never drop or silently overwrite a person's text. A write that cannot be kept where it was meant to go is kept where the person can get it back (a conflicted copy, the queue, the clipboard), and the person is told.
- Notes are held byte for byte. A note opened and left alone is never rewritten; an edit keeps the text of every block it did not reach.
- Views, commands, and the editor reach a library only through `ItemLibrary`, read from the environment's `library` value, and name items by `ItemID`, never by path.
- Mac settings are never written to Marfa (`docs/settings-storage.md`).

## Project layout

- `MAPP.xcodeproj` uses folder-synchronized groups for `MAPP/`, `MAPPTests/`, and `MAPPUITests/`. Add a source file by creating it on disk, not by editing `project.pbxproj`. Every file under `MAPP/` becomes an app resource unless the MAPP target's membership exceptions list it.
- Debug is `com.withmarfa.mapp.debug` and never shares the installed app's data or sign-ins. Key anything that must differ on `Bundle.main.bundleIdentifier`, never a literal.
- To compare design values, add a knob to the Debug-only `MAPP/Tuning/` panel, not variants, and remove it in the change that settles the value.

## Commands

```sh
xcodebuild -project MAPP.xcodeproj -scheme MAPP -destination 'platform=macOS' -derivedDataPath build test
```

Replace `test` with `build` to build only. UI tests, the `Live` plan and measuring are in `MAPPTests/AGENTS.md`; the editor page's commands are in `editor/AGENTS.md`.

## Signing and releases

- Never commit a team identifier, a report destination (`MARFA_POSTHOG_HOST`, `MARFA_POSTHOG_PROJECT_TOKEN`) or a version. They go in the ignored `Config/Local.xcconfig`, and `MARKETING_VERSION` stays `0.0.0`.
- A version exists only as a git tag (`v0.0.x`, candidates `v0.0.x-rcN`), made soon after a merge to `main` that changes what a person sees or does; tests, CI, docs and notes alone are not tagged. Before you sign, tag or check a release, read the README's Signing and Releasing sections.

## Code Review Rules

Report only a problem you can show: name the input, state, or step, and what goes wrong. Leave formatting to the tools. Nested files add rules of their own.

- **Person's text lost.** Flag any path where a write that fails, is refused or races another change is dropped or written over newer text. Safe path: keep it as a conflicted copy, in the queue or on the clipboard, and tell the person.
- **Bytes rewritten.** Flag any change that rewrites a note the person did not edit, or changes blocks outside the edit. Safe path: edit in place and add a fixture to `editor/fixtures/corpus/` for any form found rewritten.
- **Platform rules.** Flag `#available` checks, shims, hard-coded user-facing strings, a committed team identifier, report destination or version, and custom chrome where a system control exists.
- **Stale instructions or docs.** Flag a change that leaves an `AGENTS.md`, a page in `docs/`, the README or a comment untrue. Fix it in the same pull request.
