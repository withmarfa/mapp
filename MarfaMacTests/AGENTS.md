# Tests

`MarfaMacTests/` holds the Swift Testing unit tests, hosted in the app's background-only `Debug Tests` build, which starts with no scene (`TestHost`). `MarfaMacUITests/` holds the XCTest UI tests, which drive the running app through its accessibility tree.

## Running tests

- A pull request runs no Mac job (the organization has 5 macOS runners). Before an admin merge, run locally the Debug `build-for-testing`, the suites the change touches (`-only-testing:MarfaMacTests/<Suite>`) and, for any screen it touches, its UI class (`-only-testing:MarfaMacUITests/<Class>`) with the screen free. Run the Release compile too when the change touches `#if DEBUG`, build settings, `Config/`, `Info.plist` or the project file.
- After a merge, `main.yml` runs the whole `Unit` plan with a Debug build whose warnings are errors, and compiles Release. `release.yml` runs the `UI` plan before it publishes.
- A plan given a server creates and deletes items there, so give it a test instance only. Name it with the `instance_id` that `GET <address>/` reports (`TEST_RUNNER_MARFA_TEST_INSTANCE_ID`): a run refuses an address that reports another.

## Commands

For the owner-page `Live` tests, use a key with `instance.read`, `audit.read`, `backups.manage`, `sign_ins.manage`, `keys.mint` and `webhooks.manage`, such as the test instance's admin key.

```sh
# Debug build for testing, as CI does.
xcodebuild -project MarfaMac.xcodeproj -scheme MarfaMac -testPlan Unit -destination 'platform=macOS' -derivedDataPath build build-for-testing
# Release compile, as main.yml does.
xcodebuild -project MarfaMac.xcodeproj -scheme MarfaMac -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build-release CODE_SIGNING_ALLOWED=NO build
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

Under the unit test host, previews, and the sample library, `Libraries.standard()` uses `ScriptedSignIns` and a temporary store. In the unit test host each `Browser` has its own defaults. Use `ThrowawayDefaults.make(name)` to create a test domain and keep the returned object alive while the test uses it. A unit test drives `MarfaLibrary` through `FakeItemSource` or the sample's fake copy (`WorkingCopy.fake`). Only the `Live` plan reaches a server, and only a test instance.

## Code Review Rules

- **Tests touch real data.** Flag a test that reaches the Keychain, the default store location, or a server, and a UI test run without `-MarfaMacSampleLibrary`.
- **Defaults left behind.** Flag a test or test host that creates or clears a named preferences domain. Named domains leave plists in `~/Library/Preferences`. Create test domains with `ThrowawayDefaults.make`. To read the same domain from another thread, open its `suite` while the original object is still alive.
- **Sleep instead of waiting.** Flag a loop of short sleeps, an `async` suite without `.hangLimit`, or a fixed sleep with no comment saying what it waits for.
