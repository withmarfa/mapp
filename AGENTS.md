# MAPP

This file governs every session that works in this repository.

## What this repository is

MAPP: a native macOS markdown notes app with a sidebar, a list and a page, in the manner of Notes and Mail. SwiftUI throughout, AppKit only where SwiftUI cannot express something. Notes are markdown files in a folder the person chooses.

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
- The toolbar over a note is laid out as Notes lays out its own (`MAPP/Views/NoteToolbar.swift`): New Note leading, the formatting tools in the centre, and Share and a More menu trailing, beside search. It is customizable, and every item in it is also a menu command, since a toolbar can be hidden or changed. The command palette on ⌘K (`MAPP/Views/CommandPalette.swift`) offers the same commands, the sidebar's places and the notes by title, and lists only what could be done at that moment. ⌘P and ⌥⌘F search notes; ⇧⌘P prints, since ⌘P is search.
- App Sandbox and hardened runtime stay on. The sandbox allows outgoing connections only because WebKit's page process needs them; the page itself loads nothing. Every user-facing string goes through the String Catalog.
- A checkout builds without a developer account and signs to run locally. `Config/Signing.xcconfig`, the project's base configuration, leaves the team empty and includes the ignored `Config/Local.xcconfig`, which `aic-infisical-run -- scripts/render-local-signing.sh` writes from Infisical to sign with the team. Never commit a team identifier or edit the rendered file by hand.

## Versions

- A version exists only as a git tag, and tags are the maintainer's. Agents never create a tag or write a version into a file; `MARKETING_VERSION` stays `0.0.0`.

## Layout

- `MAPP.xcodeproj` is a native Xcode project whose `MAPP/`, `MAPPTests/` and `MAPPUITests/` groups follow the folders on disk; add files by creating them, not by editing the project file. The bundle identifier and display name live in the target's build settings. `MAPP/Info.plist` holds only what build settings cannot express (the note drag type) and is excluded from the app's resources.
- `MAPP/Model/` holds the notes model, free of SwiftUI; `MAPP/Views/` the windows and panes; `MAPP/AppIcon.icon` is the Icon Composer app icon. `MAPPTests/` holds the Swift Testing unit tests, hosted in the app; `MAPPUITests/` the XCTest UI tests that drive the running app through its accessibility tree. `Design/` holds artwork that is not built into the app.
- `MAPP/Localizable.xcstrings` is kept in sync by building in Xcode; `xcodebuild` alone does not update it.
- `editor/` is the note editor: Milkdown on ProseMirror in TypeScript, built by Vite into one self-contained page, `MAPP/Editor/Page/editor.html`, which is committed so the app builds without Node. After changing anything in `editor/`, run `pnpm build` there and commit the page with the change. `MAPP/Editor/` holds the Swift side: the web view, the controller that drives the page, and the bridge's messages. The page fetches nothing and never navigates: images in the notes folder reach it from the app, and any other image shows its name. An image's width, set by dragging its edge, is kept in its alt text as `![name|400](…)`, as Obsidian reads it. A note's text runs to a reading width, which Settings adjusts, unless Full Width is chosen in the View menu or Settings; the width comes from the page's margins, so a click beside the text still places the caret. Every size on the page is in `rem`, so the text size chosen in Settings scales the whole note, reading width included. Printing and Export as PDF print the page itself through WebKit, laid out by its `@media print` styles.
- `MAPP/Types/` holds Marfa Types, which sits with Recently Deleted at the foot of the sidebar, below however many folders there are: `marfa-types.html` is a copy of the page Marfa's type browser generates from its type definitions, self-contained with its own navigation and search, and is refreshed by replacing the file whole, never by editing it. Picked, it takes the list's column and the note's together, so the window has two columns rather than three, and the toolbar's search there searches the page rather than the notes, as do Find and the page's own /; Search Notes goes to All Notes to search. The app hides the page's heading and search box as it loads, since the toolbar gives it both, and gives its list of types the page's own background, so the file itself is never adapted. The page stays below the toolbar, since WebKit draws a hard edge under the toolbar over any page that reaches beneath it. View > Back and Forward (⌘[ and ⌘]) move through the types it has shown. The page fetches nothing, moves only between its own sections, and opens a web link in the browser.
- Notes are held byte for byte. A note opened and left alone is never rewritten; an edited note keeps the text of every block the edit did not reach, and only edited or new blocks take the editor's canonical form (`editor/src/preserve.ts`). The app keeps each file's envelope, its front matter, byte-order mark and Windows line endings (`MAPP/Model/NoteFile.swift`), and the page only ever sees the body; link definitions are kept by the page. `editor/fixtures/corpus/` holds notes in unusual but valid markdown, each with one paragraph marked for the tests to edit; add a fixture for any form found to be rewritten.

## Storage and Marfa

- Notes are `.md` files in the folder the person picks; each directory at the top of it is a folder, and the files at the top are the Inbox. Anything whose name starts with a dot, such as Marfa's `.marfa`, and the `Attachments` folder are not notes. The folder is remembered as a security-scoped bookmark.
- The folder is shaped so Marfa's folder device can sync it. Front matter is found by Marfa's rule (`NoteFile.frontMatterLength`); a note's title is its `title` property, otherwise its file name; `pinned: true` is a property; every other property, `marfa_id` among them, is kept as written. Front matter is edited line by line and never re-emitted.
- `NoteStore` is where notes are kept, in Marfa's words (trash, restore, purge). `FolderStore` keeps them as files and keeps the trash in the app's own storage, since a file moved within the folder reads to Marfa as a rename. A Marfa store is meant to take over the trash, restore and purge; conflicts between writers are Marfa's to settle, not the app's.
- `NoteLibrary` decides every path and hands the store one change at a time, which the store makes in order off the main thread, coordinated and whole. A new note has no file until its first line is finished, its typing pauses, or it is left.
- A note's file is named after its first line as it reads (`NoteText.name(for:)`, the one place a name is made safe), and follows the line while the note goes by it: once the person leaves a note whose first line changed, the file is renamed, so Marfa sees one rename rather than one per word. A name given with Rename Note that is not the line's stops the following. A first line with characters a file name cannot hold is also kept whole as the note's `title`.
- Debug builds launched with `-MAPPSampleFolder` open a fresh folder of sample notes in the app's own storage; the UI tests use it.

## Releases

- Builds reach TestFlight through Xcode Cloud: a workflow started by the maintainer's tag archives the app and gives it to internal testers. There is no other distribution, so no Sparkle and no notarisation.
- `ci_scripts/ci_post_clone.sh` runs in the cloud checkout: it writes `Config/Local.xcconfig` from the workflow's secret `MAPP_DEVELOPMENT_TEAM`, and sets `MARKETING_VERSION` from the tag (`1.2.3` or `v1.2.3`) in that copy only. Xcode Cloud numbers the builds. The repository still never holds a team or a version.

## Commands

- `xcodebuild -project MAPP.xcodeproj -scheme MAPP -destination 'platform=macOS' -derivedDataPath build test` builds and runs every test. The UI tests take control of the keyboard and mouse; add `-only-testing:MAPPTests` for the unit tests alone.
- The built app is `build/Build/Products/Debug/MAPP.app`.
- In `editor/`: `pnpm install`, then `pnpm test` (the editor's own tests, in jsdom), `pnpm typecheck` and `pnpm build`. `MAPPTests/EditorTests.swift` runs the built page in real WebKit through the app's bridge.
