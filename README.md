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

## Contributing

[AGENTS.md](AGENTS.md) covers conventions, architecture, signing, and releases.

## License

[Apache-2.0](LICENSE). `editor/src/style.css` is adapted from another project and keeps its own MIT notice.
