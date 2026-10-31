# MAPP

MAPP is a native macOS markdown notes app with a sidebar, a list, and a page, in the manner of Notes and Mail. It reads and writes a library only through a Marfa server, by the `marfa-swift` package's working copy, and names no item type of its own: what it shows of a type comes from the server's catalogue. With no server set, the window asks the person to connect. The note editor is a web page built on Inkkit and hosted in a `WKWebView`.

## Instruction files

Read the nested file before you change code under its directory:

- Before changing `editor/`, read `editor/AGENTS.md`.
- Before changing `MAPP/Editor/`, read `MAPP/Editor/AGENTS.md`.
- Before changing `MAPP/Model/`, read `MAPP/Model/AGENTS.md`.
- Before changing `MAPP/Model/Marfa/`, read `MAPP/Model/Marfa/AGENTS.md` as well.

Each `AGENTS.md` has a `CLAUDE.md` symlink beside it, because Claude Code reads only `CLAUDE.md` files when one exists in or above its working directory. Edit the `AGENTS.md`, never the link.

Keep each file under 200 lines and each chain from this file to a nested one under 32 KiB, since Codex stops reading at that size. Detail about one type belongs in its doc comment or a test.

## Conventions

- Use American English in code, comments, commits, and repository files.
- Use scoped Conventional Commits in the present tense, lowercase and short: `feat(app):`, `fix(editor):`, `test(model):`.
- Work on a branch and reach `main` through a pull request, squash-merged once the tests pass and a reviewer has read it.
- Make worktrees in `.claude/worktrees/` (`git worktree add .claude/worktrees/<name> -b <branch> origin/main`). Once the work is merged, remove the worktree and its local branch (`git worktree remove`, then `git branch -D`, because git sees a squash-merged branch as unmerged) and run `git pull --ff-only` on `main`. If git refuses a removal, report it rather than forcing it.
- GitHub-hosted checks (`.github/workflows/checks.yml`) run on pull requests, each only when its files changed; `Checks` is the one job to require, and nothing is retried. A draft pull request runs no Swift job: open as a draft, run the tests locally, and mark it ready once reviewed, so CI runs once. The workflow's comments say which change runs what. Run the `Unit` and `UI` plans locally before you merge.
- While working, run only the tests a change touches (`-only-testing:MAPPTests/<Suite>`), and every test once before merging.
- A test waits with `eventually` or `eventuallyAsking` (`MAPPTests/Waiting.swift`), never a loop of short sleeps. A suite with an `async` test carries `.hangLimit`, except a `Live` suite and `NavigationCostTests`; a test sets no limit of its own. A fixed sleep is only for checking that something did not happen, or for letting an animation or scroll settle in a UI test, with a comment saying what it gives time for.
- A comment says only why, never what the code already says.
- Put no absolute paths, machine names, account names, or credentials in any file.
- Keep no legacy: no compatibility shims, deprecation aliases, or migration paths. Removed means gone.
- Write no time estimates.

## Platform

- Target macOS 27 and Xcode 27 only. Write no `#available` checks and no fallbacks for earlier systems.
- Swift 6 language mode, main-actor isolation by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Unit tests use Swift Testing; UI tests use XCTest.
- Use SwiftUI, and AppKit only where SwiftUI cannot express something.
- Use native containers and controls (`NavigationSplitView`, `List`, toolbars, commands, system materials) so the system supplies the look. Custom chrome needs a reason. What the app adds is drawn to sit beside the system's own components, never as a web app's chrome.
- Check API and design questions against Apple's documentation and the Human Interface Guidelines, not memory.
- Every toolbar action is also a menu command, since a toolbar can be hidden or customized. The command palette (`MAPP/Views/CommandPalette.swift`) builds its own list, so add a new command there too. With the gallery or the table showing, the editor stays mounted but hidden, so offer an editor command in the palette only when `hasVisibleEditor`.
- Every user-facing string goes through the String Catalog. `MAPP/Localizable.xcstrings` is updated by building in Xcode; `xcodebuild` alone does not update it.
- `MainView` mounts one `NavigationSplitView` at a time and changes the workspace's identity to switch between them. Never change the column count of a split view that is already mounted. Keep state a person would notice (browser, editor, undo, columns, sidebar scroll) above that boundary.
- Large libraries: a view that lists items must not run every row's body for a change of selection or of one item. The types that keep this (`NoteList`, `SelectableList`, `GalleryCard`, `SoftSelection`, `Browser`'s cached content) say how in their doc comments; read them before changing a list, and measure with the `Measure` plan.
- App Sandbox and the hardened runtime stay on. Outgoing connections are allowed only for WebKit's page process, the Marfa server, `PictureFetcher` and `Reporting`. Neither page loads anything from the network itself.

## Data rules

These hold across the app. The nested files say how the library keeps them.

- Never drop or silently overwrite a person's text. A write that cannot be kept where it was meant to go is kept somewhere the person can get it back (a conflicted copy, the queue, the clipboard) and the person is told.
- Notes are held byte for byte. A note opened and left alone is never rewritten. An edit keeps the text of every block it did not reach.
- Views, commands, and the editor reach a library only through `ItemLibrary` (`MAPP/Model/Items/ItemLibrary.swift`), read from the environment's `library` value. Never test for a concrete library type in a view.
- Windows, selections, restoration, and drags name items by `ItemID`, never by path.
- Tests never touch the person's data. Under the unit tests' background-only host, previews and the sample library, `Libraries.standard()` uses `MemoryKeyStore`, a temporary store location and defaults of its own, never the Keychain or the saved server. UI tests open the sample library through `XCUIApplication.sample()` (`-MAPPSampleLibrary`), a library held in memory by `marfa-swift`'s fake working copy (`WorkingCopy.fake`). A unit test drives `MarfaLibrary` through `FakeItemSource` or the sample's fake copy, never a server. Only the `Live` test plan reaches a server, and only a test instance.

## Layout

- `MAPP.xcodeproj` uses folder-synchronized groups for `MAPP/`, `MAPPTests/`, and `MAPPUITests/`. Add a source file by creating it on disk; do not edit `project.pbxproj` to add files.
- Every file under `MAPP/` becomes an app resource unless the MAPP target's membership exceptions list it. The nested `AGENTS.md` and `CLAUDE.md` files are listed there; list any new one too, or two with one name fail the build as duplicate resources.
- The bundle identifier, display name, and version are build settings. Debug is `com.withmarfa.mapp.debug`, so it never shares the installed app's data or keychain items; Release is `com.withmarfa.mapp`. Key anything that must differ on `Bundle.main.bundleIdentifier`, never a literal. `MAPP/Info.plist` holds only what build settings cannot express.
- `MAPP/Model/`: the data model, free of SwiftUI (`Items/`, `Marfa/`, `Telemetry/`). `MAPP/Views/`: windows, panes, toolbars, commands, and Settings. `MAPP/Editor/`: the Swift host for the editor page. `editor/`: the page's TypeScript source. `Design/`: artwork not built into the app.
- `MAPP/Tuning/`: the Debug-only tuning panel (`#if DEBUG` throughout). When August wants to compare design values, add a knob there instead of building variants (`Tuning.swift` says how), and remove it in the change that settles the value.
- `MAPPTests/`: Swift Testing unit tests, hosted in the app's background-only `Debug Tests` build, which starts with no scene (`TestHost`). `FakeItemLibrary` holds items in memory for view models and the editor; `FakeItemSource` is a source the test drives, for `MarfaLibrary`.
- `MAPPUITests/`: XCTest UI tests that drive the running app through its accessibility tree.
- `TestPlans/`: `Unit` (the `MAPP` scheme's default) runs every unit test not tagged `live` (the `measure` suites skip by their own switch, since listing that tag too made Xcode run the Live tests); `Live` runs only those; `UI` (the `MAPP UI Tests` scheme's) runs the UI tests. `Measure` and `Measure UI` time the app and print lines for a person to read, never a gate; each suite's doc comment says what it measures. A plan given a server creates and deletes items there, so give it a test instance only, and name it with the `instance_id` that `GET <address>/` reports (`TEST_RUNNER_MARFA_TEST_INSTANCE_ID`): a run refuses an address that reports another.

## Commands

```sh
# Unit tests: no window, no Dock icon, so they can run while the Mac is in use.
xcodebuild -project MAPP.xcodeproj -scheme MAPP -destination 'platform=macOS' -derivedDataPath build test
# UI tests: take control of the keyboard and mouse.
xcodebuild -project MAPP.xcodeproj -scheme 'MAPP UI Tests' -destination 'platform=macOS' -derivedDataPath build test
# Before a release: the Live plan, against a Marfa test instance only. Without the address, key and instance id, each live test fails.
TEST_RUNNER_MARFA_API_URL=<address> TEST_RUNNER_MARFA_API_KEY=<key> TEST_RUNNER_MARFA_TEST_INSTANCE_ID=<instance_id> \
  xcodebuild -project MAPP.xcodeproj -scheme MAPP -testPlan Live -destination 'platform=macOS' -derivedDataPath build test
```

- Replace `test` with `build` to build only. The built app is `build/Build/Products/Debug/MAPP.app`.
- `Scripts/measure-ui.sh` times the window on a test instance's library, with the screen to itself; its header says how.
- A Debug build launched with `-MAPPSampleLibrary` uses a sample library held in memory (with `-MAPPSampleUnconfigured`, `-MAPPCollectionSample` or `-MAPPSelectItem <item id>` beside it). With `MAPP_TEST_MARFA_URL` and `MAPP_TEST_MARFA_KEY` set, it connects to that test server and keeps the key in memory only.
- The editor page has its own commands; see `editor/AGENTS.md`.

## Signing and releases

- Never commit a team identifier, a report destination (`MARFA_POSTHOG_HOST`, `MARFA_POSTHOG_PROJECT_TOKEN`) or a version. They go in the ignored `Config/Local.xcconfig`, and `MARKETING_VERSION` stays `0.0.0`. A build from this source signs to run locally and sends no reports.
- A version exists only as a git tag (`v0.0.x`, candidates `v0.0.x-rcN`). Tag soon after any merge to `main` that changes what a person sees or does; merges that change only tests, CI, docs or notes are not tagged. Before you sign, tag or check a release, read the README's Signing and Releasing sections: they hold the steps (candidates first, then the release, then App Store Connect to confirm).

## Code Review Rules

Report only a problem you can show: name the input, state, or step, and what goes wrong. Leave formatting to the tools. Nested files add rules for their own code.

- **Person's text lost.** Flag any path where a write that fails, is refused, or races another change is dropped or written over newer text. Safe path: keep it as a conflicted copy, in the queue, or on the clipboard, and tell the person.
- **Bytes rewritten.** Flag any change that rewrites a note the person did not edit, or changes blocks outside the edit. Safe path: edit in place and add a fixture to `editor/fixtures/corpus/` for any form found rewritten.
- **Library type leaks.** Flag a view, command, or editor change that names `MarfaLibrary` outside a preview, offers Delete Immediately without checking `reachesServer`, or names an item type other than Marfa's built-in ones (`PageHeaderKind` for the item page's header), or names an SF Symbol for a type (a type's icon is `ItemType.icon` from the catalogue, drawn by the SDK's `TypeIcon`).
- **Platform rules.** Flag `#available` checks, compatibility shims, hard-coded user-facing strings, a committed team identifier or version, and new custom chrome where a system control exists.
- **Tests touch real data.** Flag a test that reaches the Keychain, the default store location, or a server, and a UI test run without `-MAPPSampleLibrary`.
- **Stale instructions.** Flag a change that leaves an `AGENTS.md`, the README, or a comment untrue. Fix it in the same pull request.
