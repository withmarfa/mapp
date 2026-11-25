# Tests

`MarfaMacTests/` holds the Swift Testing unit tests, hosted in the app's background-only `Debug Tests` build, which starts with no scene (`TestHost`). `MarfaMacUITests/` holds the XCTest UI tests, which drive the running app through its accessibility tree.

## Running tests

- **What to run before a merge** is in `.agents/skills/land-a-pull-request/SKILL.md`. CI runs no UI tests; `main.yml` runs the unit tests and compiles Release after a merge.
- **Run one suite with `-only-testing:MarfaMacTests/<Suite>`** and one UI class with `-only-testing:MarfaMacUITests/<Class>`, with the screen free.
- **Give a plan only a test instance,** because it creates and deletes items there. A run refuses an address whose `instance_id` (from `GET <address>/`) differs from the one named.

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

`Scripts/measure-ui.sh` times the window on a test instance's library; its header says how.

## Test plans

In `TestPlans/`:

- The unit plan (the `MarfaMac` scheme's default) runs every unit test not tagged `live`. The `measure` suites skip by their own switch.
- `Live` runs only the tests tagged `live`, against a Marfa test instance.
- `UI` (the `MarfaMac UI Tests` scheme's) runs the UI tests.
- `Measure` and `Measure UI` time the app and print lines to read, never a gate.

## Waiting

- A test waits with `eventually` or `eventuallyAsking` (`MarfaMacTests/Waiting.swift`), never a loop of short sleeps.
- A suite with an `async` test carries `.hangLimit`, except a `Live` suite and a `measure` suite, which a person reads. 
- A fixed sleep is only for checking that something did not happen, or letting an animation or scroll settle in a UI test. A comment says what it waits for.

## Fakes and sample data

- `FakeItemLibrary` holds items in memory for view models and the editor.
- `FakeItemSource` is a source a test drives, for `MarfaLibrary`.
- **A Debug build launched with `-MarfaMacSampleLibrary` uses a sample library in memory.** Search the app for `-MarfaMac` to find the other arguments. It forgets what an earlier run stored unless given `-MarfaMacKeepSampleSettings`. UI tests open it with `XCUIApplication.sample()`.
- **With `MARFA_MAC_TEST_MARFA_URL` and `MARFA_MAC_TEST_MARFA_KEY` set,** it connects to that test server and keeps the key in memory. `-MarfaMacSyncSettings` also keeps the app's settings on that server, so they change there.

## Tests never touch real data

Under the unit test host, previews, and the sample library, `Libraries.standard()` uses `ScriptedSignIns` and a temporary store. In the unit test host each `Browser` has its own defaults. Use `ThrowawayDefaults.make(name)` to create a test domain and keep the returned object alive while the test uses it. A unit test may also use the sample's fake copy (`WorkingCopy.fake`). Only `Live` reaches a server.

## Code Review Rules

- **Tests touch real data.** Flag a test that reaches the Keychain, the default store location, or a server, and a UI test run without `-MarfaMacSampleLibrary`.
- **Defaults left behind.** Flag a test or test host that creates or clears a named preferences domain. Named domains leave plists in `~/Library/Preferences`. Create test domains with `ThrowawayDefaults.make`. To read the same domain from another thread, open its `suite` while the original object is still alive.
- **Sleep instead of waiting.** Flag a loop of short sleeps, an `async` suite without `.hangLimit`, or a fixed sleep with no comment saying what it waits for.
