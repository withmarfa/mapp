import XCTest

extension XCUIApplication {
    /// The app as a UI test runs it: on the sample library, held in memory for the run, with no windows restored
    /// from an earlier run, so a test never reaches the person's data.
    ///
    /// - Parameters:
    ///   - settings: User defaults for the run, each a name and its value.
    ///   - flags: Further launch flags that take no value, such as `-MAPPSampleUnconfigured`.
    static func sample(settings: KeyValuePairs<String, String> = [:], flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // A flag takes no value, so the flags come after every name and value, or one would be read as a value.
        app.launchArguments = settings.flatMap { ["-\($0.key)", $0.value] }
            + ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleLibrary"] + flags
        return app
    }
}
