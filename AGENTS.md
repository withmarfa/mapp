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
- GitHub-hosted checks (`.github/workflows/checks.yml`) run on pull requests, each only when its files changed: the editor's tests, typecheck, format check and a rebuild of the page that must match the committed `editor.html`; and the app's `Unit` test plan, then a build of the UI tests, which never run there, and, beside them, a Release build. A change that touches only views, the String Catalog, assets or UI tests compiles everything but skips the unit-test run, since those tests cover logic, not styling. A draft pull request runs no Swift job: open the pull request as a draft, run the tests locally, and mark it ready when it is reviewed, so CI runs once. The hosted run builds first, then runs the tests one at a time through `.github/scripts/run-unit-tests.sh` with a 12 minute limit; a run that reaches the limit samples its test host, uploads the samples as the `unit-test-diagnostics` artifact and fails. A failed test fails the check; nothing is retried. The final job, `Checks`, always runs and is the one to require. Xcode Cloud only archives tagged releases. Run the `Unit` and `UI` plans locally before you merge.
- While working, run only the tests a change touches (`-only-testing:MAPPTests/<Suite>`), and every test once before merging.
- A test waits for what it needs with `eventually` or `eventuallyAsking` (`MAPPTests/Waiting.swift`), never a loop of short sleeps: a wait returns as soon as its condition holds, and the shared `waitLimit` allows for a slow hosted runner. A suite with an `async` test carries `.hangLimit` (`MAPPTests/Waiting.swift`), so a test that awaits something that never arrives fails by name and the run goes on, instead of holding the job to its limit. A test sets no limit of its own. Two kinds of suite are left out: a `Live` suite, whose tests each set a limit that allows for a real server, and `NavigationCostTests`, which only the Measure plan runs and a person reads. A fixed sleep is only for checking that something did not happen, with a comment saying what it gives time for.
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
- A gallery card (`GalleryCard`) takes only its own inputs and compares by them, so a selection that moves, or another card's change, never runs a card's body: the selection ring is its own view (`GalleryRing`) and the button, menu and drag around the card are `GalleryCell`, which reads the selection. What a card derives from its item is `GalleryCardFacts`, worked out only when the card's own inputs change. The soft selection's marks (`SoftSelection`) watch the one table or outline view and its clip view, and the selected rows' own frames, never every view in the window, and place themselves once for a change, for the selected rows in view and a few beside them only (Select All on a long list marks the rows on screen, not every row). The marks read the selection lazily, through a closure, so the view that places them does not run its body again for every change of selection. The note list compares by its browser and order (`NoteList` is `Equatable`), so the window's own changes do not run its body, and sets each row's list traits (selection, separators, drag) in the `ForEach` itself, never inside the row's view: a trait inside a row's view has SwiftUI run every row's body, out of sight too, to read it. Select All in the note list goes through the list's selection binding (`selectsAll`, `SelectAllRoute`, sent by `MAPPApplication`), never through its table: SwiftUI treats a split view column's selection as navigation and makes the view of every row the table adds, which held the window for over a minute on about 10,000 items. A click on a SwiftUI list's row selects the row but does not give the list the keyboard, so the note list, the table and the timeline each ask for it when clicked (`takesKeyboardOnClick`); without that, Select All, Return, Command-Delete and the arrow keys had nothing to reach. AppKit turns Command-Delete into `deleteToBeginningOfLine:` before SwiftUI sees the key, so the note list and the gallery answer that command too. The list itself is its own view (`SelectableList`), and so is the drag of the selection (`dragsSelection(of:)`, which the gallery uses too): each reads the selection in its own body, so a change of selection runs those small bodies and never the note list's, which lists every item the place holds. The window's saved state is written when the place, the selection or the layout changes (`Browser.snapshotParts`), never by encoding a snapshot on every run of the window's body. The snapshot keeps the selected ids only up to `Browser.restoredSelectionLimit` (200); a larger selection is saved as none and the list opens at its first rows, so Select All never sorts or encodes thousands. The palette ranks the titles of its commands, places and items first and builds an entry for every matching command and place and for only the best 50 items (`PaletteMatch.Titles.picks`), and keeps the ranking until the query, the commands' titles or what the items depend on changes (`CommandPalette.Listing`), so an arrow key ranks nothing. The commands are built on every run of the body, since they read the editor, the browser and the host, which change under an open palette; a search is never held, since its answer arrives through the library's own state. A file's window makes no editor (`NoteWindow.pageEditor`), and file text over 64 KB is drawn by an `NSTextView` (`PlainTextFilePage`), since SwiftUI's `Text` laid out 4 MB in about 12 seconds.
- App Sandbox and the hardened runtime stay on. The sandbox allows outgoing connections for four reasons: WebKit's page process needs them, the library talks to its Marfa server, the app fetches the pictures at web addresses that a note's page or a sealed web page asks for (`PictureFetcher`), and a build that carries a report destination sends errors and timings to WithMarfa (`Reporting`). Neither page loads anything from the network itself.

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
- The bundle identifier, display name, and version are build settings. A Debug build has its own bundle identifier, `com.withmarfa.mapp.debug`, so it never shares the installed app's container, defaults, saved server, Marfa store or keychain items; Release is `com.withmarfa.mapp`. Key anything that must differ between them (the keychain service) on `Bundle.main.bundleIdentifier`, never a literal. `MAPP/Info.plist` holds only what build settings cannot express (the note drag type, and the two report-destination settings below) and is excluded from the app's resources.
- `MAPP/Model/`: the data model, free of SwiftUI. `Items/` holds the library protocol and item types; `Marfa/` holds the Marfa library; `Telemetry/` holds the app's logs and signposts (`MAPP/Model/AGENTS.md`).
- `MAPP/Views/`: windows, panes, toolbars, commands, and Settings.
- `MAPP/Tuning/`: the Debug-only tuning panel. Every file in it is wrapped in `#if DEBUG`, so Release has no panel, no Developer menu and no registry. The panel is empty ("No knobs yet") until a design value needs comparing. A *knob* is a named value (slider, switch or choice) adjusted live in the panel, which the `Copy` button turns into text to paste into a chat. To add one, declare it with `Knob.slider`, `.toggle` or `.picker`, default it to the code's own constant, list it in `Tuning.shared`, and read it in the view with `Tuning.shared.number(_:)`, `.flag` or `.choice`, behind `#if DEBUG` with the constant in the `#else`. Remove a knob, its use and its list entry in the same change that settles its value; none stays as a setting. Its text is not localized. When August wants to compare or adjust design values (spacing, strengths, materials), add a knob for them in the panel instead of building variants, and delete the knob when the value is settled.
- `MAPP/Editor/`: the Swift host for the editor page. `editor/`: the page's TypeScript source.
- `MAPPTests/`: Swift Testing unit tests. They are hosted in the app built with the `Debug Tests` configuration, which marks it background-only (`LSBackgroundOnly`), so the host never shows in the Dock, never becomes the active app and puts no window in front of the person; under XCTest it starts the app's `MAPPApplication` with no scene (`TestHost` in `MAPP/MAPPApp.swift`). `FakeItemLibrary` holds items in memory for testing view models and the editor without a server. `FakeItemSource` is a source the test drives, for testing `MarfaLibrary` without a server.
- `MAPPUITests/`: XCTest UI tests that drive the running app through its accessibility tree.
- `TestPlans/`: the test plans. `Unit`, the `MAPP` scheme's default, runs every unit test except those tagged `live`; `Live` runs only those; `Measure` runs only the tests tagged `measure`, which the other plans leave out by their own switch (the plan sets `MAPP_MEASURE`), which time and count what moving around a window costs on 650 generated items, and Select All in the list and moving between the table's places on about 10,000 (`NavigationCostTests`, `Cost`) and print `COST|`, `COUNT|` and `HOSTED|` lines for a person to read, never a gate; `SidebarFramesTests` hosts the whole window and prints `FRAME|` lines, the sidebar's selection, marks and scroll offset on the turns after the window changes shape (`xcodebuild -testPlan Measure`, in a Debug Tests build). Given a test instance's address and key through `TEST_RUNNER_MARFA_API_URL` and `TEST_RUNNER_MARFA_API_KEY`, `Measure` also runs `EngineCostTests`, which time the engine, the source and the library over a real copy and print `ENGINE|` lines; without them it skips them. It creates and purges items on that instance, so give it a test instance only; `UI`, the `MAPP UI Tests` scheme's, runs the UI tests. `Measure UI`, in the same scheme, runs only `SpeedMeasureTests`, which the `UI` plan leaves out: it times launch (cold and warm), choosing places, moving between the table's places, selecting in the table and the gallery, opening items, New, Search and typing in the real window, on a library held by a Marfa test instance, and prints `UI|<name>|<median>|<max>|<unit>` lines for a person to read, never a gate. It takes over the screen and needs a test instance (see Commands); without `MAPP_MEASURE_UI` and the instance's address and key, each test skips.
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

- Time the window on a test instance's library, with the screen and keyboard to itself and no other UI run active. The `Measure UI` plan's tests print what UI testing saw; the app's own signposts, launch milestones and slow events come from the unified log, which a sandboxed UI test cannot read, so `Scripts/measure-ui.sh` records the log around the run and prints those lines too. The one write is a note made for the typing step, which the script deletes and purges afterwards with the `marfa` command line. The Debug-only `-MAPPKeepTestStore` flag keeps the copy the last launch left, which is how a warm launch is timed; add `SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule` for numbers close to a release's. UI testing's own queries of a library this size take seconds, so the tests click by coordinate and use shortcuts, and the signposts are the finer number:

  ```sh
  TEST_RUNNER_MARFA_API_URL=<address> TEST_RUNNER_MARFA_API_KEY=<key> Scripts/measure-ui.sh build
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
- **Error reports.** `Config/Signing.xcconfig` leaves `MARFA_POSTHOG_HOST` and `MARFA_POSTHOG_PROJECT_TOKEN` empty, and `Info.plist` carries them into the build. A build with both sends the app's errors and timings (`MAPP/Model/Telemetry/Reporting.swift`); a build from this source sends nothing. Write them into `Config/Local.xcconfig` the same way as the team, and never commit either. In the cloud checkout, `ci_scripts/ci_post_clone.sh` writes them from the workflow secrets `MAPP_POSTHOG_HOST` and `MAPP_POSTHOG_PROJECT_TOKEN` when the workflow sets both, and stops the build when it sets only one or either is not an `https` host or a `phc_` token.

## Versions and releases

- A version exists only as a git tag: `v` followed by the version, such as `v0.0.5`. Every version is `0.0.x` until the first public release, and each release is the latest release tag plus `0.0.1`.
- A **release candidate** is a tag with `-rc` and a number after the version it is a candidate for, such as `v0.0.25-rc1`, then `-rc2`. It builds as version 0.0.25 with the next build number, so TestFlight shows one version with several builds and the version number grows only when a release is cut. A candidate is never counted as the latest release tag.
- **Tag soon after any merge to `main` that changes what a person sees or does**, within reason. Take the next candidate of the next version by default. Cut the release itself (`v0.0.25`) when a candidate has been tried, when a logical set of work is complete, or when the brief says so. Merges that change only tests, CI, docs or notes are not tagged. A tag build only archives, and the team's Xcode Cloud allowance is far from used, so do not hold work back to save version numbers.
- Never write a version into a file. `MARKETING_VERSION` stays `0.0.0` in the repository.
- To release or make a candidate, tag the merged commit on `main` and push the tag. A tag beginning with `v` starts the Xcode Cloud workflow, which archives the app and gives it to internal TestFlight testers. There is no other distribution, so no Sparkle and no notarization.
- In the cloud checkout, `ci_scripts/ci_post_clone.sh` writes `Config/Local.xcconfig` from the workflow secrets (`MAPP_DEVELOPMENT_TEAM`, and the two above) when the workflow sets them (otherwise Xcode Cloud signs with its own managed signing) and sets `MARKETING_VERSION` from the tag, without a `-rc` suffix. A tag build stops if the tag is not a version or the version was not written. Xcode Cloud numbers the builds.
- Agents cannot see Xcode Cloud. Check a release in App Store Connect: the build for the tag's version appears under TestFlight.

## Code Review Rules

Report only a problem you can show: name the input, state, or step, and what goes wrong. Leave formatting to the tools. Nested files add rules for their own code.

- **Person's text lost.** Flag any path where a write that fails, is refused, or races another change is dropped or written over newer text. Safe path: keep it as a conflicted copy, in the queue, or on the clipboard, and tell the person.
- **Bytes rewritten.** Flag any change that rewrites a note the person did not edit, or changes blocks outside the edit. Safe path: edit in place and add a fixture to `editor/fixtures/corpus/` for any form found rewritten.
- **Library type leaks.** Flag a view, command, or editor change that names `MarfaLibrary` outside a preview, offers Delete Immediately without checking `reachesServer`, or names an item type other than Marfa's built-in ones (`PageHeaderKind` for the item page's header), or names an SF Symbol for a type (a type's icon is `ItemType.icon` from the catalogue, drawn by the SDK's `TypeIcon`).
- **Platform rules.** Flag `#available` checks, compatibility shims, hard-coded user-facing strings, a committed team identifier or version, and new custom chrome where a system control exists.
- **Tests touch real data.** Flag a test that reaches the Keychain, the default store location, or a server, and a UI test run without `-MAPPSampleLibrary`.
- **Stale instructions.** Flag a change that leaves an `AGENTS.md`, the README, or a comment untrue. Fix it in the same pull request.
