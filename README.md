# MAPP

MAPP is a native macOS notes app for a Marfa server. Its editor is built on [Inkkit](https://github.com/aicayzer/inkkit).

## Requirements

- macOS 27 and Xcode 27
- A Marfa server to connect to

## Build and test

```sh
xcodebuild -project MAPP.xcodeproj -scheme MAPP -destination 'platform=macOS' -derivedDataPath build test
```

This builds the app and runs the unit tests. To run the app, open `MAPP.xcodeproj` in Xcode and run the `MAPP` scheme.

## Signing

A checkout builds without a developer account and signs to run locally. `Config/Signing.xcconfig`, the project's base configuration, leaves the team empty and includes the ignored `Config/Local.xcconfig`.

- To sign with a team, write `DEVELOPMENT_TEAM = <team ID>` into `Config/Local.xcconfig`. The repository holds no tool for keeping that line.
- To send errors and timings (`MAPP/Model/Telemetry/Reporting.swift`), write `MARFA_POSTHOG_HOST` and `MARFA_POSTHOG_PROJECT_TOKEN` into `Config/Local.xcconfig` the same way. `Info.plist` carries them into the build; a build without both sends nothing.
- Never commit a team identifier or either report setting.

In Xcode Cloud, `ci_scripts/ci_post_clone.sh` writes `Config/Local.xcconfig` from the workflow secrets `MAPP_DEVELOPMENT_TEAM`, `MAPP_POSTHOG_HOST` and `MAPP_POSTHOG_PROJECT_TOKEN`. Without a team, Xcode Cloud uses its own managed signing. The script stops the build when only one report setting is set, or when the host is not `https` or the token does not start with `phc_`.

## Releasing

- A version exists only as a git tag: `v` followed by the version, such as `v0.0.5`. Every version is `0.0.x` until the first public release, and each release is the latest release tag plus `0.0.1`.
- A release candidate is a tag with `-rc` and a number after the version it is a candidate for, such as `v0.0.25-rc1`, then `-rc2`. It builds as version 0.0.25 with the next build number, so TestFlight shows one version with several builds. A candidate is never counted as the latest release tag.
- Tag soon after any merge to `main` that changes what a person sees or does. Take the next candidate of the next version by default. Cut the release itself (`v0.0.25`) when a candidate has been tried, when a logical set of work is complete, or when the brief says so. Merges that change only tests, CI, docs, or notes are not tagged. A tag build only archives, so don't hold work back to save version numbers.
- Never write a version into a file. `MARKETING_VERSION` stays `0.0.0` in the repository.
- To release or make a candidate, tag the merged commit on `main` and push the tag. A tag that begins with `v` starts the Xcode Cloud workflow, which archives the app and gives it to internal TestFlight testers. There is no other distribution, so there is no Sparkle and no notarization.
- `ci_scripts/ci_post_clone.sh` sets `MARKETING_VERSION` from the tag, without the `-rc` suffix, and stops the build if the tag is not a version or the version wasn't written. Xcode Cloud numbers the builds.
- Agents can't see Xcode Cloud. Check a release in App Store Connect: the build for the tag's version appears under TestFlight.

## Contributing

[AGENTS.md](AGENTS.md) covers conventions, architecture, and the rules for each part of the code.

## License

[Apache-2.0](LICENSE). `editor/src/style.css` is adapted from another project and keeps its own MIT notice.
