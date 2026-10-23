# MAPP

MAPP is a native macOS markdown notes app with a sidebar, a list, and a page, in the manner of Notes and Mail. It reads a library from one of two places: a folder of markdown files the person chooses, or a Marfa server through the `marfa-swift` package's working copy. The note editor is a web page built on InkKit and hosted in a `WKWebView`.

## Instruction files

Read the nested file before you change code under its directory:

- Before changing `editor/`, read `editor/AGENTS.md`.
- Before changing `MAPP/Editor/`, read `MAPP/Editor/AGENTS.md`.
- Before changing `MAPP/Model/`, read `MAPP/Model/AGENTS.md`.
- Before changing `MAPP/Model/Marfa/`, read `MAPP/Model/Marfa/AGENTS.md` as well.

Each `AGENTS.md` has a `CLAUDE.md` symlink beside it, because Claude Code reads only `CLAUDE.md` files when one exists in or above its working directory. Edit the `AGENTS.md`, never the link.

## Conventions

- Use American English in code, comments, commits, and repository files.
- Use scoped Conventional Commits in the present tense, lowercase and short: `feat(app):`, `fix(editor):`, `test(model):`.
- Work on a branch and reach `main` through a pull request, squash-merged once the tests pass and a reviewer has read it.
- Make worktrees in `.claude/worktrees/` (`git worktree add .claude/worktrees/<name> -b <branch> origin/main`). Once the work is merged, remove the worktree and its local branch (`git worktree remove`, then `git branch -D`, because git sees a squash-merged branch as unmerged) and run `git pull --ff-only` on `main`. If git refuses a removal, report it rather than forcing it.
- No CI runs on pull requests: Xcode Cloud only archives tagged releases, and GitHub runs only Dependabot. Run the tests locally before you merge.
- While working, run only the tests a change touches (`-only-testing:MAPPTests/<Suite>`), and every test once before merging.
- A comment says only why, never what the code already says.
- Put no absolute paths, machine names, account names, or credentials in any file.
- Keep no legacy: no compatibility shims, deprecation aliases, or migration paths. Removed means gone.
- Write no time estimates.

## Platform

- Target macOS 27 and Xcode 27 only. Write no `#available` checks and no fallbacks for earlier systems.
- Swift 6 language mode, main-actor isolation by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Unit tests use Swift Testing; UI tests use XCTest.
- Use SwiftUI, and AppKit only where SwiftUI cannot express something.
- Use native containers and controls (`NavigationSplitView`, `List`, toolbars, commands, system materials) so the system supplies the look. Custom chrome needs a reason. What the app adds, such as the palette, the column search, and the page, is drawn to sit beside the system's own components as if it were theirs, in the manner of the Codex app or Craft Docs, never a web app's chrome.
- Check API and design questions against Apple's documentation and the Human Interface Guidelines, not memory.
- Every toolbar action is also a menu command, since a toolbar can be hidden or customized. The command palette (`MAPP/Views/CommandPalette.swift`) builds its own list, so add a new command there too.
- With the gallery or the table showing, the editor stays mounted but hidden. Menu commands get no focused editor then (`MainView`), but the palette holds the editor directly, so offer an editor command there only when `hasVisibleEditor`.
- Every user-facing string goes through the String Catalog. `MAPP/Localizable.xcstrings` is updated by building in Xcode; `xcodebuild` alone does not update it.
- `MainView` mounts one `NavigationSplitView` at a time (the three-column list, or the two-column split the gallery and the table share), and changes the workspace's identity when it switches between them, which is also what moving from the gallery or the table to Settings does: Settings is a place in the three-column split, with its pages in the content column and the page in the detail column, so macOS releases the outgoing toolbar. Never change the column count of a split view that is already mounted. Browser, editor, draft, undo, and column state live above that boundary.
- App Sandbox and the hardened runtime stay on. The sandbox allows outgoing connections for two reasons: WebKit's page process needs them, and a Marfa library talks to its server. The editor page itself loads nothing from the network.

## Data rules

These hold across the app. The nested files say how each library keeps them.

- Never drop or silently overwrite a person's text. A write that cannot be kept where it was meant to go is kept somewhere the person can get it back (a conflicted copy, the queue, the clipboard) and the person is told.
- Notes are held byte for byte. A note opened and left alone is never rewritten. An edit keeps the text of every block it did not reach.
- Views, commands, and the editor reach a library only through `ItemLibrary` (`MAPP/Model/Items/ItemLibrary.swift`), read from the environment's `library` value. Never test for a concrete library type in a view.
- Windows, selections, restoration, and drags name items by `ItemID`, never by path.
- Tests never touch the person's data. Under unit tests hosted in the app and UI tests, `Libraries.standard()` uses `MemoryKeyStore`, a temporary store location, and a `NotesFolder` on its own defaults, never the Keychain, the saved server, or the person's notes folder. UI tests open a sample folder (`-MAPPSampleFolder`); a unit test that needs a folder makes its own and a `NotesFolder(defaults:)`.

## Layout

- `MAPP.xcodeproj` uses folder-synchronized groups for `MAPP/`, `MAPPTests/`, and `MAPPUITests/`. Add a source file by creating it on disk; do not edit `project.pbxproj` to add files.
- Every file under `MAPP/` becomes an app resource unless the MAPP target's membership exceptions list it. The nested `AGENTS.md` and `CLAUDE.md` files are listed there; list any new one too, or it is copied into the app, and two with one name fail the build as duplicate resources.
- The bundle identifier, display name, and version are build settings. A Debug build has its own bundle identifier, `com.withmarfa.mapp.debug`, so it never shares the installed app's container, defaults, saved server, Marfa store or keychain items; Release is `com.withmarfa.mapp`. Key anything that must differ between them (the keychain service) on `Bundle.main.bundleIdentifier`, never a literal. `MAPP/Info.plist` holds only what build settings cannot express (the note drag type) and is excluded from the app's resources.
- `MAPP/Model/`: the data model, free of SwiftUI. `Items/` holds the library protocol and item types; `Marfa/` holds the Marfa library.
- `MAPP/Views/`: windows, panes, toolbars, commands, and Settings.
- `MAPP/Editor/`: the Swift host for the editor page. `editor/`: the page's TypeScript source.
- `MAPPTests/`: Swift Testing unit tests, hosted in the app. `FakeItemLibrary` holds items in memory for testing view models without a folder or server. `FakeItemSource` is a source the test drives, for testing `MarfaLibrary` without a server.
- `MAPPUITests/`: XCTest UI tests that drive the running app through its accessibility tree.
- `Design/`: artwork that is not built into the app.

## Commands

- Build and run every test:

  ```sh
  xcodebuild -project MAPP.xcodeproj -scheme MAPP -destination 'platform=macOS' -derivedDataPath build test
  ```

  The UI tests take control of the keyboard and mouse. Add `-only-testing:MAPPTests` to run the unit tests alone.
- Replace `test` with `build` to build only. The built app is `build/Build/Products/Debug/MAPP.app`.
- A Debug build launched with `-MAPPSampleFolder` opens a fresh folder of sample notes in the app's temporary directory and an isolated Marfa host. The UI tests use it. `-MAPPSelectItem <item id>` with it selects that item once the library holds it, for a run nobody can click.
- To point that Debug build at a test server, run its binary with `MAPP_TEST_MARFA_URL` and `MAPP_TEST_MARFA_KEY` in the environment: the isolated host connects to that server, keeping the key in memory only.
- The editor page has its own commands; see `editor/AGENTS.md`.

## Signing

- A checkout builds without a developer account and signs to run locally. `Config/Signing.xcconfig`, the project's base configuration, leaves the team empty and includes the ignored `Config/Local.xcconfig`.
- To sign with the team, run `infisical run -- scripts/render-local-signing.sh`, which writes `Config/Local.xcconfig` from Infisical.
- Never commit a team identifier, and never edit the rendered file by hand.

## Versions and releases

- A version exists only as a git tag: `v` followed by the version, such as `v0.0.5`. Every version is `0.0.x` until the first public release, and each release is the latest tag plus `0.0.1`.
- Never write a version into a file. `MARKETING_VERSION` stays `0.0.0` in the repository.
- To release when a release is called, tag the merged commit on `main` with the next version and push the tag. A tag beginning with `v` starts the Xcode Cloud workflow, which archives the app and gives it to internal TestFlight testers. There is no other distribution, so no Sparkle and no notarization.
- In the cloud checkout, `ci_scripts/ci_post_clone.sh` writes `Config/Local.xcconfig` from the workflow secret `MAPP_DEVELOPMENT_TEAM` and sets `MARKETING_VERSION` from the tag. Xcode Cloud numbers the builds.
- Agents cannot see Xcode Cloud. Check a release in App Store Connect: the build for the tag's version appears under TestFlight.

## Code Review Rules

Report only a problem you can show: name the input, state, or step, and what goes wrong. Leave formatting to the tools. Nested files add rules for their own code.

- **Person's text lost.** Flag any path where a write that fails, is refused, or races another change is dropped or written over newer text. Safe path: keep it as a conflicted copy, in the queue, or on the clipboard, and tell the person.
- **Bytes rewritten.** Flag any change that rewrites a note the person did not edit, or changes front matter, a byte-order mark, line endings, or blocks outside the edit. Safe path: edit in place and add a fixture to `editor/fixtures/corpus/` for any form found rewritten.
- **Library type leaks.** Flag a view, command, or editor change that names `NoteLibrary` or `MarfaLibrary` outside a preview, or offers a write without checking `capabilities`.
- **Platform rules.** Flag `#available` checks, compatibility shims, hard-coded user-facing strings, a committed team identifier or version, and new custom chrome where a system control exists.
- **Tests touch real data.** Flag a test that reaches the Keychain, the default store location, or a person's folder, and a UI test run without `-MAPPSampleFolder`.
- **Stale instructions.** Flag a change that leaves an `AGENTS.md`, the README, or a comment untrue. Fix it in the same pull request.
