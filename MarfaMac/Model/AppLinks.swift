import Foundation

/// The addresses the app opens in the browser, all in one place: the Help menu, the About panel and the command palette.
nonisolated enum AppLinks {
    static let source = URL(string: "https://github.com/withmarfa/marfa-mac")!
    static let license = URL(string: "https://github.com/withmarfa/marfa-mac/blob/main/LICENSE")!
    /// The project's README, which is the app's help until a help book exists.
    static let help = URL(string: "https://github.com/withmarfa/marfa-mac#readme")!
    static let releases = URL(string: "https://github.com/withmarfa/marfa-mac/releases")!
    static let marfaDocumentation = URL(string: "https://docs.marfa.so")!
    private static let newIssue = URL(string: "https://github.com/withmarfa/marfa-mac/issues/new")!

    /// A new issue with the app's version and the Mac's system version in its body. It carries nothing about the person
    /// or their library: no name, no server address, no item.
    static func reportAProblem(version: String, build: String, system: String) -> URL {
        var parts = URLComponents(url: newIssue, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "body", value: """
            What happened?


            What did you expect?


            ---
            Marfa for Mac \(version) (\(build))
            macOS \(system)
            """)]
        return parts.url!
    }

    /// The same for the app and the Mac that are running.
    static var reportFromThisMac: URL {
        let info = Bundle.main.infoDictionary
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return reportAProblem(
            version: info?["CFBundleShortVersionString"] as? String ?? "", build: info?["CFBundleVersion"] as? String ?? "",
            system: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)")
    }
}
