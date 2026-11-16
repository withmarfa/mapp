---
name: land-a-pull-request
description: Merge your own MAPP pull request, from draft to merged, including the five admin merges that go ahead without waiting for the ready run's Checks and a fix to a red main. Use when a pull request in this repository is finished and needs to reach main, or when main is red.
---

# Land a pull request

A session merges its own pull request once the review its risk calls for is done, with that depth stated on the pull request: squash, branch deleted. Getting finished work to `main` comes first. Run the least CI a change needs and do not wait on CI for its own sake.

## Merge

`Checks` is the one required check, and it reports on a draft too. A draft runs no Swift job, so its green says nothing about the tests, and a run that the next event cancels can report green as well. Auto-merge is off here, and `--auto` would merge on that green anyway.

1. Run the tests yourself while the pull request is a draft.
2. Mark it ready with no push in flight: `gh pr ready <number>`.
3. Read the job list until the ready run's `Checks` has passed on the head commit, with `Unit tests` among its jobs where the change runs it.
4. Merge: `gh pr merge <number> --squash --delete-branch`.

A branch does not need to be up to date with `main` to merge. Update it only for a conflict or for something on `main` it needs, never only to be current.

## Merging without waiting for Checks

In the five cases below, merge with `gh pr merge <number> --squash --admin --delete-branch` and say on the pull request which case applies and why. GitHub merges no draft, so mark a draft ready and cancel the run that starts (`gh run cancel <run>`) first. Nothing runs on a push to `main` here, so the next pull request's run is the check after an admin merge.

- **Jobs the change cannot affect.** Check the change locally, cancel the run, merge, and correct the rule in the `Changes` job of `.github/workflows/checks.yml` so the next change of that kind runs only what it needs.
- **Check bookkeeping on a head that passed its full checks:** a required check left "expected" because a later run on the same commit was cancelled.
- **A fix for a red `main`.** When `main` is red, for example because two pull requests that each passed clash, or because a test is flaky, fix it before other work, in one small pull request, because a red `main` fails every open pull request's checks. A fix that changes only tests merges once its local quick checks pass. A change to a workflow is not test-only, because a workflow can reach secrets. Any other fix follows the usual rules.
- **A pull request that failed only because `main` was red.** Once `main` is fixed, it merges when the only failed jobs are the ones `main` broke and its local quick checks pass. Do not rebase it and run everything again.
- **A clean update from `main` of a head that passed the ready run's `Checks`:** the only change since that run is a merge or rebase from `main` with no conflict. Cancel the run the update starts, and show that nothing else changed: `git diff origin/main...HEAD` lists the same files and content as before the update, or the update was GitHub's **Update branch** with no conflict.

A change to stored notes, access, a migration or a release always waits for the ready run's `Checks` to pass, after an update from `main` too.

## Afterward

Run `git worktree remove .claude/worktrees/<name>`, `git branch -D <branch>` (a squash-merge looks unmerged) and `git pull --ff-only` on `main`.
