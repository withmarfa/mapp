# Tests

`MAPPTests/` holds the Swift Testing unit tests, hosted in the app's background-only `Debug Tests` build, which starts with no scene (`TestHost`). `MAPPUITests/` holds the XCTest UI tests, which drive the running app through its accessibility tree.

## Running tests

- Run only the tests a change touches, while working and before merging: `-only-testing:MAPPTests/<Suite>`. CI runs the whole `Unit` plan once the pull request is ready.
- UI tests take over the keyboard and mouse. Run them (`-only-testing:MAPPUITests/<Class>`, or the whole `UI` plan) when a change needs them and the screen is free. No merge or release requires them, and CI builds them, so a change that breaks them is seen.
- A plan given a server creates and deletes items there, so give it a test instance only. Name it with the `instance_id` that `GET <address>/` reports (`TEST_RUNNER_MARFA_TEST_INSTANCE_ID`): a run refuses an address that reports another.

## Commands

```sh
# Unit tests: no window, no Dock icon, so they can run while the Mac is in use.
xcodebuild -project MAPP.xcodeproj -scheme MAPP -destination 'platform=macOS' -derivedDataPath build test
# UI tests: take control of the keyboard and mouse.
xcodebuild -project MAPP.xcodeproj -scheme 'MAPP UI Tests' -destination 'platform=macOS' -derivedDataPath build test
# Before a release: the Live plan, against a Marfa test instance only.
TEST_RUNNER_MARFA_API_URL=<address> TEST_RUNNER_MARFA_API_KEY=<key> TEST_RUNNER_MARFA_TEST_INSTANCE_ID=<instance_id> \
  xcodebuild -project MAPP.xcodeproj -scheme MAPP -testPlan Live -destination 'platform=macOS' -derivedDataPath build test
```

Replace `test` with `build` to build only. `Scripts/measure-ui.sh` times the window on a test instance's library, with the screen to itself; its header says how.

## Test plans

`TestPlans/` holds these plans:

- `Unit` (the `MAPP` scheme's default) runs every unit test not tagged `live`. The `measure` suites skip by their own switch.
- `Live` runs only the tests tagged `live`, against a Marfa test instance.
- `UI` (the `MAPP UI Tests` scheme's) runs the UI tests.
- `Measure` and `Measure UI` time the app and print lines to read, never a gate.

## Waiting

- A test waits with `eventually` or `eventuallyAsking` (`MAPPTests/Waiting.swift`), never a loop of short sleeps.
- A suite with an `async` test carries `.hangLimit`, except a `Live` suite and `NavigationCostTests`. A test sets no limit of its own.
- A fixed sleep is only for checking that something did not happen, or letting an animation or scroll settle in a UI test. A comment says what it waits for.

## Fakes and sample data

- `FakeItemLibrary` holds items in memory for view models and the editor.
- `FakeItemSource` is a source a test drives, for `MarfaLibrary`.
- A Debug build launched with `-MAPPSampleLibrary` uses a sample library held in memory, beside `-MAPPSampleUnconfigured`, `-MAPPCollectionSample` or `-MAPPSelectItem <item id>`. UI tests open it through `XCUIApplication.sample()`. With `MAPP_TEST_MARFA_URL` and `MAPP_TEST_MARFA_KEY` set, it connects to that test server and keeps the key in memory only.

## Tests never touch real data

Under the unit tests' background-only host, previews and the sample library, `Libraries.standard()` uses `MemorySignIns`, a temporary store and defaults of its own, never the Keychain or the saved server. A unit test drives `MarfaLibrary` through `FakeItemSource` or the sample's fake copy (`WorkingCopy.fake`). Only the `Live` plan reaches a server, and only a test instance.

## Code Review Rules

- **Tests touch real data.** Flag a test that reaches the Keychain, the default store location, or a server, and a UI test run without `-MAPPSampleLibrary`.
- **Sleep instead of waiting.** Flag a loop of short sleeps, an `async` suite without `.hangLimit`, or a fixed sleep with no comment saying what it waits for.
