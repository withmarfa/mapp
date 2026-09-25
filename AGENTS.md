# MAPP

This file governs every session that works in this repository.

## What this repository is

MAPP: a native macOS markdown notes app with a sidebar, a list and a page, in the manner of Notes and Mail. SwiftUI throughout, AppKit only where SwiftUI cannot express something. Content is sample data held in memory; there is no storage yet.

## Conventions

- **American English** in code, comments, commits and repository files.
- **Scoped Conventional Commits**, for example `feat(app):`, `fix(editor):`, `test(model):`. Present tense, lowercase, short.
- **Branches and pull requests.** Work goes on a branch and reaches `main` through a pull request, squash-merged once the tests pass and a reviewer has read it. There is no CI; the tests are run locally before merging.
- **Comments explain why, not what.** A comment survives only if it carries a reason the code cannot.
- **No personal detail.** No absolute paths, machine names, account names or credentials in any file here.
- **No legacy.** No compatibility shims, deprecation aliases or migration paths. Removed means gone.
- **No time estimates.**

## Platform

- macOS 27 and Xcode 27 only. No `#available` checks and no fallbacks for earlier systems.
- Swift 6 language mode, main-actor isolation by default, Swift Testing.
- Native containers and controls (`NavigationSplitView`, `List`, toolbars, commands, system materials) so the system supplies the look. Custom chrome needs a reason. Check API and design questions against Apple's documentation and the Human Interface Guidelines, not memory.
- App Sandbox and hardened runtime stay on. Every user-facing string goes through the String Catalog.

## Versions

- A version exists only as a git tag, and tags are the maintainer's. Agents never create a tag or write a version into a file; `MARKETING_VERSION` stays `0.0.0`.

## Layout

- `MAPP.xcodeproj` is a native Xcode project whose `MAPP/`, `MAPPTests/` and `MAPPUITests/` groups follow the folders on disk; add files by creating them, not by editing the project file. The bundle identifier and display name live in the target's build settings. `MAPP/Info.plist` holds only what build settings cannot express (the note drag type) and is excluded from the app's resources.
- `MAPP/Model/` holds the notes model, free of SwiftUI; `MAPP/Views/` the windows and panes; `MAPP/AppIcon.icon` is the Icon Composer app icon. `MAPPTests/` holds the Swift Testing unit tests, hosted in the app; `MAPPUITests/` the XCTest UI tests that drive the running app through its accessibility tree. `Design/` holds artwork that is not built into the app.
- `MAPP/Localizable.xcstrings` is kept in sync by building in Xcode; `xcodebuild` alone does not update it.

## Commands

- `xcodebuild -project MAPP.xcodeproj -scheme MAPP -destination 'platform=macOS' -derivedDataPath build test` builds and runs every test. The UI tests take control of the keyboard and mouse; add `-only-testing:MAPPTests` for the unit tests alone.
- The built app is `build/Build/Products/Debug/MAPP.app`.
