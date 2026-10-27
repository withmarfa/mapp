# MAPP

MAPP is a native macOS markdown notes app with a sidebar, a list, and a page, in the manner of Notes and Mail. It reads and writes a library only through a Marfa server, by the `marfa-swift` package's working copy, and names no item type of its own: what it shows of a type comes from the server's catalogue. With no server set, the window asks the person to connect. The note editor is a web page built on Inkkit and hosted in a `WKWebView`.

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
- GitHub-hosted checks (`.github/workflows/checks.yml`) run on pull requests, each only when its files changed: the editor's tests, typecheck, format check and a rebuild of the page that must match the committed `editor.html`; and the app's `Unit` test plan, then a build of the UI tests, which never run there, and, beside them, a Release build. A change that touches only views, the String Catalog, assets or UI tests compiles everything but skips the unit-test run, since those tests cover logic, not styling. A draft pull request runs no Swift job: open the pull request as a draft, run the tests locally, and mark it ready when it is reviewed, so CI runs once. A failed test fails the check; nothing is retried. The final job, `Checks`, always runs and is the one to require. Xcode Cloud only archives tagged releases. Run the `Unit` and `UI` plans locally before you merge.
- While working, run only the tests a change touches (`-only-testing:MAPPTests/<Suite>`), and every test once before merging.
- A test waits for what it needs with `eventually` or `eventuallyAsking` (`MAPPTests/Waiting.swift`), never a loop of short sleeps or its own time limit: a wait returns as soon as its condition holds, and the shared limit allows for a slow hosted runner. A fixed sleep is only for checking that something did not happen, with a comment saying what it gives time for.
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
- `MainView` mounts one `NavigationSplitView` at a time (the three-column list, or the two-column split the gallery and the table share), and changes the workspace's identity when it switches between them, which is also what moving from the gallery or the table to Settings does: Settings is a place in the three-column split, with its pages in the content column and the page in the detail column, so macOS releases the outgoing toolbar. Never change the column count of a split view that is already mounted. Browser, editor, undo, and column state live above that boundary.
- App Sandbox and the hardened runtime stay on. The sandbox allows outgoing connections for two reasons: WebKit's page process needs them, and the library talks to its Marfa server. The editor page itself loads nothing from the network.

## Data rules

These hold across the app. The nested files say how the library keeps them.

- Never drop or silently overwrite a person's text. A write that cannot be kept where it was meant to go is kept somewhere the person can get it back (a conflicted copy, the queue, the clipboard) and the person is told.
- Notes are held byte for byte. A note opened and left alone is never rewritten. An edit keeps the text of every block it did not reach.
- Views, commands, and the editor reach a library only through `ItemLibrary` (`MAPP/Model/Items/ItemLibrary.swift`), read from the environment's `library` value. Never test for a concrete library type in a view.
- Windows, selections, restoration, and drags name items by `ItemID`, never by path.
- Tests never touch the person's data. Under the unit tests' background-only host, previews and the sample library, `Libraries.standard()` uses `MemoryKeyStore`, a temporary store location and defaults of its own, never the Keychain or the saved server. UI tests open the sample library through `XCUIApplication.sample()` (`-MAPPSampleLibrary`), a library held in memory by `marfa-swift`'s fake working copy (`WorkingCopy.fake`). A unit test drives `MarfaLibrary` through `FakeItemSource` or the sample's fake copy, never a server. Only the `Live` test plan reaches a server, and only a test instance.

## Layout

- `MAPP.xcodeproj` uses folder-synchronized groups for `MAPP/`, `MAPPTests/`, and `MAPPUITests/`. Add a source file by creating it on disk; do not edit `project.pbxproj` to add files.
- Every file under `MAPP/` becomes an app resource unless the MAPP target's membership exceptions list it. The nested `AGENTS.md` and `CLAUDE.md` files are listed there; list any new one too, or it is copied into the app, and two with one name fail the build as duplicate resources.
- The bundle identifier, display name, and version are build settings. A Debug build has its own bundle identifier, `com.withmarfa.mapp.debug`, so it never shares the installed app's container, defaults, saved server, Marfa store or keychain items; Release is `com.withmarfa.mapp`. Key anything that must differ between them (the keychain service) on `Bundle.main.bundleIdentifier`, never a literal. `MAPP/Info.plist` holds only what build settings cannot express (the note drag type) and is excluded from the app's resources.
- `MAPP/Model/`: the data model, free of SwiftUI. `Items/` holds the library protocol and item types; `Marfa/` holds the Marfa library.
- `MAPP/Views/`: windows, panes, toolbars, commands, and Settings.
- `MAPP/Editor/`: the Swift host for the editor page. `editor/`: the page's TypeScript source.
- `MAPPTests/`: Swift Testing unit tests. They are hosted in the app built with the `Debug Tests` configuration, which marks it background-only (`LSBackgroundOnly`), so the host never shows in the Dock, never becomes the active app and puts no window in front of the person; under XCTest it starts a bare `NSApplication` with no scene (`TestHost` in `MAPP/MAPPApp.swift`). `FakeItemLibrary` holds items in memory for testing view models and the editor without a server. `FakeItemSource` is a source the test drives, for testing `MarfaLibrary` without a server.
- `MAPPUITests/`: XCTest UI tests that drive the running app through its accessibility tree.
- `TestPlans/`: the test plans. `Unit`, the `MAPP` scheme's default, runs every unit test except those tagged `live`; `Live` runs only those; `Measure` runs only the tests tagged `measure`, which the other plans leave out by their own switch (the plan sets `MAPP_MEASURE`), which time and count what moving around a window costs on 650 generated items (`NavigationCostTests`, `Cost`) and print `COST|`, `COUNT|` and `HOSTED|` lines for a person to read, never a gate (`xcodebuild -testPlan Measure`, in a Debug Tests build); `UI`, the `MAPP UI Tests` scheme's, runs the UI tests.
- `Design/`: artwork that is not built into the app.

## Commands

- Build and run the unit tests:

  ```sh
  xcodebuild -project MAPP.xcodeproj -scheme MAPP -destination 'platform=macOS' -derivedDataPath build test
  ```

  They show no window and no Dock icon, so they can run while the Mac is in use.
- Run the UI tests, which take control of the keyboard and mouse:

  ```sh
  xcodebuild -project MAPP.xcodeproj -scheme 'MAPP UI Tests' -destination 'platform=macOS' -derivedDataPath build test
  ```

- Before a release, run the `Live` plan against a Marfa test instance, never a server that holds a person's data. Its tests create, edit and delete items there. Pass the instance's address and a key for it through xcodebuild's `TEST_RUNNER_` prefix, which hands them to the tests without it:

  ```sh
  TEST_RUNNER_MARFA_API_URL=<address> TEST_RUNNER_MARFA_API_KEY=<key> \
    xcodebuild -project MAPP.xcodeproj -scheme MAPP -testPlan Live -destination 'platform=macOS' -derivedDataPath build test
  ```

  Without them, each live test fails rather than skips.
- Replace `test` with `build` to build only. The built app is `build/Build/Products/Debug/MAPP.app`.
- A Debug build launched with `-MAPPSampleLibrary` connects an isolated Marfa host to a sample library held in memory for the length of the run. The UI tests use it. Add `-MAPPSampleUnconfigured` to start with no server set instead, as a first launch does, `-MAPPCollectionSample` for tasks and events, and `-MAPPSelectItem <item id>` to select that item once the library holds it, for a run nobody can click.
- To point that Debug build at a test server, run its binary with `MAPP_TEST_MARFA_URL` and `MAPP_TEST_MARFA_KEY` in the environment: the isolated host connects to that server, keeping the key in memory only.
- The editor page has its own commands; see `editor/AGENTS.md`.

## Signing

- A checkout builds without a developer account and signs to run locally. `Config/Signing.xcconfig`, the project's base configuration, leaves the team empty and includes the ignored `Config/Local.xcconfig`.
- To sign with a team, write `DEVELOPMENT_TEAM = <team ID>` into `Config/Local.xcconfig`. How a contributor keeps that line is their own; the repository holds no tool for it.
- Never commit a team identifier.

## Versions and releases

- A version exists only as a git tag: `v` followed by the version, such as `v0.0.5`. Every version is `0.0.x` until the first public release, and each release is the latest release tag plus `0.0.1`.
- A **release candidate** is a tag with `-rc` and a number after the version it is a candidate for, such as `v0.0.25-rc1`, then `-rc2`. It builds as version 0.0.25 with the next build number, so TestFlight shows one version with several builds and the version number grows only when a release is cut. A candidate is never counted as the latest release tag.
- **Tag soon after any merge to `main` that changes what a person sees or does**, within reason. Take the next candidate of the next version by default. Cut the release itself (`v0.0.25`) when a candidate has been tried, when a logical set of work is complete, or when the brief says so. Merges that change only tests, CI, docs or notes are not tagged. A tag build only archives, and the team's Xcode Cloud allowance is far from used, so do not hold work back to save version numbers.
- Never write a version into a file. `MARKETING_VERSION` stays `0.0.0` in the repository.
- To release or make a candidate, tag the merged commit on `main` and push the tag. A tag beginning with `v` starts the Xcode Cloud workflow, which archives the app and gives it to internal TestFlight testers. There is no other distribution, so no Sparkle and no notarization.
- In the cloud checkout, `ci_scripts/ci_post_clone.sh` writes `Config/Local.xcconfig` from the workflow secret `MAPP_DEVELOPMENT_TEAM` when the workflow sets one (otherwise Xcode Cloud signs with its own managed signing) and sets `MARKETING_VERSION` from the tag, without a `-rc` suffix. A tag build stops if the tag is not a version or the version was not written. Xcode Cloud numbers the builds.
- Agents cannot see Xcode Cloud. Check a release in App Store Connect: the build for the tag's version appears under TestFlight.

## Code Review Rules

Report only a problem you can show: name the input, state, or step, and what goes wrong. Leave formatting to the tools. Nested files add rules for their own code.

- **Person's text lost.** Flag any path where a write that fails, is refused, or races another change is dropped or written over newer text. Safe path: keep it as a conflicted copy, in the queue, or on the clipboard, and tell the person.
- **Bytes rewritten.** Flag any change that rewrites a note the person did not edit, or changes blocks outside the edit. Safe path: edit in place and add a fixture to `editor/fixtures/corpus/` for any form found rewritten.
- **Library type leaks.** Flag a view, command, or editor change that names `MarfaLibrary` outside a preview, offers Delete Immediately without checking `canPurge`, or names an item type other than Marfa's built-in ones (`TypeSymbol`, and `PageHeaderKind` for the item page's header).
- **Platform rules.** Flag `#available` checks, compatibility shims, hard-coded user-facing strings, a committed team identifier or version, and new custom chrome where a system control exists.
- **Tests touch real data.** Flag a test that reaches the Keychain, the default store location, or a server, and a UI test run without `-MAPPSampleLibrary`.
- **Stale instructions.** Flag a change that leaves an `AGENTS.md`, the README, or a comment untrue. Fix it in the same pull request.
