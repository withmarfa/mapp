# MAPP

This file governs every session that works in this repository.

## What this repository is

MAPP: a native macOS markdown notes app with a sidebar, a list and a page, in the manner of Notes and Mail. SwiftUI throughout, AppKit only where SwiftUI cannot express something. Content is sample data held in memory; there is no storage yet.

## Conventions

- **American English** in code, comments, commits and repository files.
- **Scoped Conventional Commits**, for example `feat(app):`, `fix(editor):`, `test(model):`. Present tense, lowercase, short.
- **Branches and pull requests** once the repository has a remote; until then, focused commits on `main`.
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

- `MAPP.xcodeproj` is a native Xcode project whose `MAPP/` and `MAPPTests/` groups follow the folders on disk; add files by creating them, not by editing the project file. The bundle identifier and display name live in the target's build settings.
- `MAPP/` holds the app; `MAPP/AppIcon.icon` is the Icon Composer app icon. `MAPPTests/` holds the Swift Testing target, hosted in the app. `Design/` holds artwork that is not built into the app.

## Commands

- `xcodebuild -project MAPP.xcodeproj -scheme MAPP -destination 'platform=macOS' -derivedDataPath build test` builds and runs the tests.
- The built app is `build/Build/Products/Debug/MAPP.app`.
