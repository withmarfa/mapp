---
name: land-a-pull-request
description: Merge your own pull request, from draft to merged, with an admin merge once it passes locally, and fix a broken main forward. Use when a pull request in this repository is finished and needs to reach main, or when main is broken.
---

# Land a pull request

A session merges its own pull request once the review its risk calls for is done, with that depth stated on the pull request: squash, branch deleted. Getting finished work to `main` comes first, and `main` is not precious.

GitHub lets the organization run only 5 macOS jobs at once, so a pull request runs no Mac job. Its `Checks` (the required check) covers only Linux jobs. Do not wait on CI. Never set auto-merge.

## Merge

1. Keep the pull request draft until you push the final changes. Push review fixes together.
2. Run locally, from `MarfaMacTests/AGENTS.md`:
   - the Debug `build-for-testing`;
   - the unit suites the change touches (`-only-testing`);
   - the UI test class of any screen the change touches;
   - a Release compile when the change touches `#if DEBUG`, build settings, `Config/`, `Info.plist` or the project file. Debug-only code broke releases v0.0.21 to v0.0.24-rc1.
3. Mark it ready with `gh pr ready <number>` (GitHub merges no draft), then merge: `gh pr merge <number> --squash --admin --delete-branch`. Say on the pull request what you ran.

A branch does not need to be up to date with `main` to merge. Update it only for a conflict or for something on `main` it needs.

## After the merge

`main.yml` compiles Release and runs the unit tests on the newest commit on `main`. A failure opens or comments on the issue "Main build failed", and a pass closes it. A broken `main` is acceptable for a while. Fix it forward in a small pull request, and start with the issue if one is open. CI runs no UI tests, so run the UI test class for any screen a change touches locally.

A change to stored notes, access, a migration or a release needs the full local run above, and the dry run when it touches `release.yml`, `Scripts/release/`, `Config/` or `Info.plist`.

## Afterward

Run `git worktree remove .claude/worktrees/<name>`, `git branch -D <branch>` (a squash-merge looks unmerged) and `git pull --ff-only` on `main`.
