# Tests

`MarfaMacTests/` holds the Swift Testing unit tests, hosted in the app's background-only `Debug Tests` build, which starts with no scene (`TestHost`). `MarfaMacUITests/` holds the XCTest UI tests, which drive the running app through its accessibility tree.

## Running tests

- Run only the tests a change touches, while working and before merging: `-only-testing:MarfaMacTests/<Suite>`. CI runs the whole `Unit` plan for ready pull requests with logic changes.
- Run UI tests locally (`-only-testing:MarfaMacUITests/<Class>` or the `UI` plan) with the screen free. CI builds them when their files, a test plan, the project, or `checks.yml` change.
- A plan given a server creates and deletes items there, so give it a test instance only. Name it with the `instance_id` that `GET <address>/` reports (`TEST_RUNNER_MARFA_TEST_INSTANCE_ID`): a run refuses an address that reports another.

## Commands

For the owner-page `Live` tests, use a key with `instance.read`, `audit.read`, `backups.manage`, `sign_ins.manage`, `keys.mint` and `webhooks.manage`, such as the test instance's admin key.

```sh
# Unit tests: no window, no Dock icon, so they can run while the Mac is in use.
xcodebuild -project MarfaMac.xcodeproj -scheme MarfaMac -destination 'platform=macOS' -derivedDataPath build test
# UI tests: take control of the keyboard and mouse.
xcodebuild -project MarfaMac.xcodeproj -scheme 'MarfaMac UI Tests' -destination 'platform=macOS' -derivedDataPath build test
# Before a release: the Live plan, against a Marfa test instance only.
TEST_RUNNER_MARFA_API_URL=<address> TEST_RUNNER_MARFA_API_KEY=<key> TEST_RUNNER_MARFA_TEST_INSTANCE_ID=<instance_id> \
  xcodebuild -project MarfaMac.xcodeproj -scheme MarfaMac -testPlan Live -destination 'platform=macOS' -derivedDataPath build test
```

Replace `test` with `build` to build only. `Scripts/measure-ui.sh` times the window on a test instance's library, with the screen to itself; its header says how.

## Test plans

`TestPlans/` holds these plans:

- `Unit` (the `MarfaMac` scheme's default) runs every unit test not tagged `live`. The `measure` suites skip by their own switch.
- `Live` runs only the tests tagged `live`, against a Marfa test instance.
- `UI` (the `MarfaMac UI Tests` scheme's) runs the UI tests.
- `Measure` and `Measure UI` time the app and print lines to read, never a gate.

## Waiting

- A test waits with `eventually` or `eventuallyAsking` (`MarfaMacTests/Waiting.swift`), never a loop of short sleeps.
- A suite with an `async` test carries `.hangLimit`, except a `Live` suite and a `measure` suite, which a person reads. A test sets no limit of its own.
- A fixed sleep is only for checking that something did not happen, or letting an animation or scroll settle in a UI test. A comment says what it waits for.

## Fakes and sample data

- `FakeItemLibrary` holds items in memory for view models and the editor.
- `FakeItemSource` is a source a test drives, for `MarfaLibrary`.
- A Debug build launched with `-MarfaMacSampleLibrary` uses a sample library held in memory, beside `-MarfaMacSampleUnconfigured`, `-MarfaMacCollectionSample`, `-MarfaMacSelectItem <item id>` or `-MarfaMacOpenPlace <type id>` with `-MarfaMacLayout <layout>`, and `-MarfaMacAppearance dark|light`. A sample launch forgets the settings an earlier run kept, a table's columns and a saved view's layout among them (`SampleLibrary.forgetStoredChoices`), unless `-MarfaMacKeepSampleSettings` is given. UI tests open it through `XCUIApplication.sample()`. With `MARFA_MAC_TEST_MARFA_URL` and `MARFA_MAC_TEST_MARFA_KEY` set, it connects to that test server and keeps the key in memory only; with `-MarfaMacSyncSettings` too, this app's settings are kept in that server's `app.marfa-mac.preferences` item, so the settings of this debug build start empty and a test server's settings change.

## Tests never touch real data

Under the unit tests' background-only host, previews and the sample library, `Libraries.standard()` uses `ScriptedSignIns` (a `MemoryKeychain` holding the package's `Credential`, with the browser and code answers scripted), a temporary store and defaults of its own, never the Keychain or the saved server, and each `Browser` keeps its Mac settings in defaults of its own, so what one test leaves in a place's default view never reaches another's. A test's own defaults come from `ThrowawayDefaults.make(name)`, a file in the temporary folder that goes when the last reference does, never `UserDefaults(suiteName:)`, which leaves a file in `~/Library/Preferences` that nothing removes. A unit test drives `MarfaLibrary` through `FakeItemSource` or the sample's fake copy (`WorkingCopy.fake`). Only the `Live` plan reaches a server, and only a test instance.

## Code Review Rules

- **Tests touch real data.** Flag a test that reaches the Keychain, the default store location, or a server, and a UI test run without `-MarfaMacSampleLibrary`.
- **Defaults left behind.** Flag `UserDefaults(suiteName:)` or `removePersistentDomain` in a test or the test host: a named domain leaves a `.plist` in `~/Library/Preferences` on every run. Safe path: `ThrowawayDefaults.make`.
- **Sleep instead of waiting.** Flag a loop of short sleeps, an `async` suite without `.hangLimit`, or a fixed sleep with no comment saying what it waits for.
