# Marfa for Mac

Marfa for Mac is a native macOS app for the items in a Marfa server. Its editor is built on [Inkkit](https://github.com/aicayzer/inkkit).

## Requirements

- macOS 27 and Xcode 27
- A Marfa server to connect to

## Build and test

```sh
xcodebuild -project MarfaMac.xcodeproj -scheme MarfaMac -destination 'platform=macOS' -derivedDataPath build test
```

This builds the app and runs the unit tests. To run the app, open `MarfaMac.xcodeproj` in Xcode and run the `MarfaMac` scheme.

## Signing

A checkout builds without a developer account and signs to run locally. `Config/Signing.xcconfig`, the project's base configuration, leaves each of the settings below empty and includes the ignored `Config/Local.xcconfig`.

- The Debug configurations leave the hardened runtime off and Release keeps it. Under the hardened runtime, an app signed to run locally refuses to load Sparkle, which is signed the same way, because library validation accepts no locally signed library. Xcode turns the runtime off for such a build itself only when it is not optimized.
- To sign with a team, write `DEVELOPMENT_TEAM = <team ID>` into `Config/Local.xcconfig`. The repository holds no tool for keeping that line.
- To send errors and timings (`MarfaMac/Model/Telemetry/Reporting.swift`), write `MARFA_MAC_POSTHOG_HOST` and `MARFA_MAC_POSTHOG_PROJECT_TOKEN` into `Config/Local.xcconfig` the same way. `Info.plist` carries them into the build; a build without both sends nothing.
- To make a build that updates itself, write `MARFA_MAC_UPDATE_FEED_URL` (the address of the appcast) and `MARFA_MAC_UPDATE_PUBLIC_KEY` (the public half of the Sparkle signing key) the same way. A build without both has no updater, no **Check for Updates…** and no Updates section in Settings, so a local build never offers to replace itself. In an xcconfig file, write the `://` of an address as `:/$()/`, since `//` starts a comment.
- Never commit a team identifier, a report setting or an update setting.

The release workflow writes `Config/Local.xcconfig` for a release build from the values of its environment.

## Releasing

A tag publishes a release. The workflow in `.github/workflows/release.yml` builds the app, signs it with a Developer ID, notarizes and staples it, packs it in a disk image that it signs, notarizes and staples too, and signs the image for Sparkle. It then creates the GitHub release, uploads the disk image and the appcast to `https://downloads.withmarfa.com/marfa-mac/`, and checks that each file is served as uploaded. The app updates itself from that appcast through [Sparkle](https://sparkle-project.org).

### Versions and tags

- A version exists only as a git tag: `v` followed by three numbers, such as `v0.0.59`. Every version is `0.0.x` until the first public release, and each release is the latest release tag plus `0.0.1`.
- A release candidate is a tag with `-rc` and a number from 1 to 98 after the version it is a candidate for, such as `v0.0.59-rc1`, then `-rc2`. It builds as version 0.0.59.
- A candidate goes to the beta channel: only people who turn on **Beta Versions** in **Settings > General > Updates** are offered it. A release goes to everyone, and to the website's download, `Marfa.dmg`. A candidate is never counted as the latest release tag.
- The build number comes from the tag, so nothing is written into a file: `X*10000000 + Y*100000 + Z*100 + N` for the candidate `vX.Y.Z-rcN`, and the same with 99 for N for the release `vX.Y.Z`. `v0.0.59-rc1` builds as 5901 and `v0.0.59` as 5999. Sparkle compares build numbers, so a candidate is older than its release, and a rebuilt tag keeps its number. `MARKETING_VERSION` stays `0.0.0` in the repository.
- The workflow refuses a tag that is not that shape, that would build version 0.0.0, or that is not on the history of `main`.
- Tag soon after any merge to `main` that changes what a person sees or does. Take the next candidate of the next version by default. Cut the release itself (`v0.0.59`) when a candidate has been tried, when a logical set of work is complete, or when the brief says so. Merges that change only tests, CI, docs, or notes are not tagged. Try a choice in a local build first, because a release is installed on every Mac that checks for updates.

### Make a release or a candidate

1. Merge the work into `main`.
2. Tag the merged commit and push the tag:

   ```sh
   git tag v0.0.59-rc1 <commit>
   git push origin v0.0.59-rc1
   ```

3. Check the release, as described below.

To rebuild a tag, re-run its workflow run. The run replaces the disk image on the GitHub release and the tag's item in the appcast.

### Check a release

1. In GitHub, open the **Actions** tab and check that the **Release** run for the tag has finished. Its `build` job signs and notarizes, and its `publish` job releases and uploads.
2. Open the repository's **Releases** page. The release for the tag lists the disk image, and a candidate is marked as a pre-release.
3. Fetch the appcast and look for the tag's item at the top. A candidate's item has `<sparkle:channel>beta</sparkle:channel>`; a release's item has no channel:

   ```sh
   curl -s https://downloads.withmarfa.com/marfa-mac/appcast.xml | head -40
   ```

4. To try the update, run an older build that carries a feed, choose **Marfa > Check for Updates…**, and install the new version.

### Dry run

A pull request that changes `.github/workflows/release.yml`, `Scripts/release/`, the project or `Config/`, and a manual run of the workflow, make a dry run. It archives with ad hoc signing, makes the disk image, signs it with a throwaway Sparkle key and builds an appcast from a fixture feed. It skips the export, notarizing and every upload, reads no secret, and keeps the disk image and the appcast as the `dry-run` artifact. A tag run stops if the environment lacks any value it needs.

### Release scripts

`Scripts/release/` holds the steps the workflow runs, each of which you can read on its own. The tag and the appcast are handled by Python 3 scripts with unit tests:

```sh
python3 -m unittest discover -s Scripts/release
```

## Contributing

[AGENTS.md](AGENTS.md) covers conventions and the rules for each part of the code, and [docs/](docs/) explains the concepts and the agreed design.

## License

[Apache-2.0](LICENSE). `editor/src/style.css` is adapted from another project and keeps its own MIT notice. `MarfaMac/Views/Reader/` holds [Mozilla Readability](https://github.com/mozilla/readability) 0.6.0, unmodified and under the Apache-2.0 license; `READABILITY-NOTICE.txt` there has its notice and how to update it.
