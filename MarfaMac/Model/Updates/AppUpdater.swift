import Foundation
import Observation
import Sparkle

/// What decides whether the app updates itself, and which versions it may be offered. Pure, so a test can run it.
nonisolated enum UpdateSettings {
    /// The `Info.plist` keys Sparkle reads, which the build settings `MARFA_MAC_UPDATE_FEED_URL` and
    /// `MARFA_MAC_UPDATE_PUBLIC_KEY` fill. Both are empty in the repository, so only a release build carries them.
    static let feedKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"
    /// Sparkle's own switch for looking by itself, which it keeps in the defaults under this name.
    static let automaticChecksKey = "SUEnableAutomaticChecks"
    /// Settings > General > Marfa for Mac > Try beta versions. Stays on this Mac.
    static let betaKey = "betaVersions"
    /// The channel a release candidate's appcast item is in.
    static let betaChannel = "beta"

    /// Whether this build is one that updates itself: it has both a feed and a key to check what the feed offers.
    static func isConfigured(in info: [String: Any]?) -> Bool {
        [feedKey, publicKeyKey].allSatisfy { key in
            guard let value = info?[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The channels besides the default one that the updater may look in.
    static func allowedChannels(betaIsOn: Bool) -> Set<String> {
        betaIsOn ? [betaChannel] : []
    }
}

/// The app's updater: Sparkle's standard controller, made once at launch and only for a build that carries a feed and a
/// key. A build without them has no updater and no update controls in General.
@Observable
final class AppUpdater {
    /// Whether a check may start now, which is not so while one runs.
    private(set) var canCheckForUpdates = false
    /// Whether the updater looks by itself, once a day.
    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    private var availableVersion: String?
    private var isUpToDate = false

    var checkSummary: String? {
        if let availableVersion { return String(localized: "Update available: \(availableVersion).") }
        guard let checked = controller.updater.lastUpdateCheckDate else { return nil }
        let format = DateFormat.stored()
        let when = DateDisplay.timeOfDay(of: checked, format: format)
        let reading = Calendar.current.isDateInToday(checked)
            ? String(localized: "Checked today at \(when).")
            : String(localized: "Checked \(checked.formatted(date: .abbreviated, time: .omitted)) at \(when).")
        return isUpToDate ? String(localized: "Up to date. \(reading)") : reading
    }

    private let controller: SPUStandardUpdaterController
    private let channels: Channels
    private var observation: NSKeyValueObservation?

    /// The updater for this build, or nil where the build carries no feed or key.
    static func standard(info: [String: Any]? = Bundle.main.infoDictionary, defaults: UserDefaults = .standard) -> AppUpdater? {
        UpdateSettings.isConfigured(in: info) ? AppUpdater(defaults: defaults) : nil
    }

    init(defaults: UserDefaults, startingUpdater: Bool = true) {
        let channels = Channels(defaults: defaults)
        let controller = SPUStandardUpdaterController(startingUpdater: startingUpdater, updaterDelegate: channels, userDriverDelegate: nil)
        self.channels = channels
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        channels.owner = self
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    /// Asks the feed now and shows the answer, whether there is a new version or not.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Settings > General > Reset puts the choice back to the one the app ships with.
    func resetChoices() {
        checksAutomatically = true
    }

    /// Answers which channels the updater may look in each time it checks, so a change to Beta Versions applies to the
    /// next check without a restart.
    private final class Channels: NSObject, SPUUpdaterDelegate {
        private let defaults: UserDefaults
        weak var owner: AppUpdater?

        init(defaults: UserDefaults) {
            self.defaults = defaults
        }

        func allowedChannels(for updater: SPUUpdater) -> Set<String> {
            UpdateSettings.allowedChannels(betaIsOn: defaults.bool(forKey: UpdateSettings.betaKey))
        }

        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            owner?.availableVersion = item.displayVersionString
            owner?.isUpToDate = false
        }

        func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
            owner?.availableVersion = nil
            let reason = (error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber
            owner?.isUpToDate = reason?.int32Value == SPUNoUpdateFoundReason.onLatestVersion.rawValue
        }
    }
}
